-- ====================================================================
-- Migration 0003 — "The Hunter" Automated Matchmaking Engine
-- --------------------------------------------------------------------
-- BRD §3.2: matchmaking must run inside the database, use atomic queuing
-- (FOR UPDATE SKIP LOCKED), inject exactly one matches row, set the
-- compatibility, set a 24h expiry, and flip BOTH users to 'matched'
-- atomically without race conditions or double-matching.
--
-- DESIGN NOTE — why AFTER (not a raw BEFORE) trigger:
--   The BRD asks for a BEFORE INSERT OR UPDATE trigger. A BEFORE trigger
--   cannot safely perform this work, because:
--     1. The matches row has a FK to profiles(id); in a BEFORE INSERT the
--        triggering profile row is not yet persisted, so inserting a match
--        that references it would violate the FK / be transactionally
--        ambiguous.
--     2. The engine must mutate a *second* row (the partner) and the
--        triggering row itself — cross-row mutation that re-fires the
--        trigger and risks infinite recursion.
--   The safe PostgreSQL-equivalent (and the documented tradeoff) is:
--     * An AFTER INSERT OR UPDATE trigger (row already persisted → FK ok),
--       guarded by WHEN (status becomes eligible) so flipping rows to
--       'matched' does NOT re-enter the engine (recursion-safe),
--     * delegating to a SECURITY DEFINER function that takes row locks with
--       FOR UPDATE SKIP LOCKED so a candidate is never grabbed twice.
--   This preserves every BRD guarantee (atomic, no double-match, single
--   match row, 24h expiry, simultaneous status flip) while remaining
--   correct under concurrency.
-- ====================================================================

-- Core matcher. Returns the new match id, or NULL when no candidate.
-- SECURITY DEFINER so it can write matches/profiles and bypass RLS as the
-- trusted system worker (BRD §4.2 "Security Definer Isolation").
CREATE OR REPLACE FUNCTION public.hunter_try_match(p_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_me        public.profiles%ROWTYPE;
    v_cand      public.profiles%ROWTYPE;
    v_match_id  UUID;
    v_compat    INTEGER;
BEGIN
    -- 1. Lock the subject row. Plain FOR UPDATE (NOT skip locked): if it is
    --    already locked by a concurrent matcher we must wait, so we never
    --    operate on stale state. Only act while still eligible.
    SELECT * INTO v_me
    FROM public.profiles
    WHERE id = p_id
      AND account_status IN ('pending', 'active')
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NULL;  -- already matched / not eligible
    END IF;

    -- 2. Idempotency: never create a second active room for someone.
    IF EXISTS (
        SELECT 1 FROM public.matches
        WHERE (user1_id = p_id OR user2_id = p_id)
          AND room_status = 'active'
    ) THEN
        RETURN NULL;
    END IF;

    -- 3. Atomic candidate selection. FOR UPDATE SKIP LOCKED guarantees a
    --    single pending candidate is never handed to two matchers at once
    --    (BRD §3.2 Atomic Locking). Deterministic FIFO order (created_at).
    SELECT * INTO v_cand
    FROM public.profiles c
    WHERE c.id <> v_me.id
      AND c.account_status IN ('pending', 'active')
      AND c.gender IS NOT NULL AND v_me.gender IS NOT NULL AND c.gender <> v_me.gender
      AND c.city   IS NOT NULL AND v_me.city   IS NOT NULL AND c.city = v_me.city
      AND c.age    IS NOT NULL AND v_me.age    IS NOT NULL AND abs(c.age - v_me.age) <= 10
      AND NOT EXISTS (
            SELECT 1 FROM public.matches m
            WHERE (m.user1_id = c.id OR m.user2_id = c.id)
              AND m.room_status = 'active'
      )
    ORDER BY c.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF NOT FOUND THEN
        RETURN NULL;  -- fail safely: no candidate yet
    END IF;

    -- 4. Deterministic compatibility (BRD allows hardcoded/algorithmic, e.g. 99%).
    v_compat := greatest(80, 99 - abs(v_me.age - v_cand.age));

    -- 5. Inject exactly one matches row, with a hard 24h expiry (BRD §3.3).
    INSERT INTO public.matches (user1_id, user2_id, match_percentage, ai_reasoning,
                                room_status, expires_at)
    VALUES (v_me.id, v_cand.id, v_compat,
            'تم اكتشاف توافق مبدئي بين الطرفين بناءً على المدينة والعمر والتوجه.',
            'active', now() + interval '24 hours')
    RETURNING id INTO v_match_id;

    -- 6. Flip BOTH users to 'matched' in a SINGLE statement (atomic /
    --    simultaneous). The AFTER trigger re-fires for these rows but its
    --    WHEN guard (status IN pending/active) is now false → no recursion.
    UPDATE public.profiles
    SET account_status = 'matched'
    WHERE id IN (v_me.id, v_cand.id);

    RETURN v_match_id;
END;
$$;

-- Trigger entry point. Fires only while the row is eligible, so the
-- 'matched' flip above cannot re-enter the engine.
CREATE OR REPLACE FUNCTION public.hunter_on_profile_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM public.hunter_try_match(NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS hunter_matchmaking_trigger ON public.profiles;
CREATE TRIGGER hunter_matchmaking_trigger
    AFTER INSERT OR UPDATE OF account_status ON public.profiles
    FOR EACH ROW
    WHEN (NEW.account_status IN ('pending', 'active'))
    EXECUTE FUNCTION public.hunter_on_profile_change();

-- Manual admin sweep (BRD §3.6 "force run the matchmaking loop cycle on
-- demand"). Re-runs the Hunter across the whole eligible queue — useful for
-- profiles that became eligible before the trigger existed. Returns the
-- number of new rooms created.
CREATE OR REPLACE FUNCTION public.run_hunter_sweep()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    r        RECORD;
    v_made   INTEGER := 0;
BEGIN
    FOR r IN
        SELECT id FROM public.profiles
        WHERE account_status IN ('pending', 'active')
        ORDER BY created_at ASC
    LOOP
        IF public.hunter_try_match(r.id) IS NOT NULL THEN
            v_made := v_made + 1;
        END IF;
    END LOOP;
    RETURN v_made;
END;
$$;

-- Expire rooms whose countdown elapsed. Safe to call from a cron/admin.
CREATE OR REPLACE FUNCTION public.expire_stale_rooms()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE public.matches
    SET room_status = 'expired'
    WHERE room_status = 'active'
      AND expires_at <= now();
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- The sweep is privileged: callable only by the backend service role,
-- never by client (anon/authenticated) roles.
REVOKE ALL ON FUNCTION public.run_hunter_sweep()    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expire_stale_rooms()  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hunter_try_match(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_hunter_sweep()   TO service_role;
GRANT EXECUTE ON FUNCTION public.expire_stale_rooms() TO service_role;
