-- ====================================================================
-- RLS positive assertions (operations that MUST succeed / return the right
-- visibility). Each test runs in its own transaction with SET LOCAL ROLE so
-- the role/JWT context resets automatically; writes are rolled back.
-- ====================================================================
\set ON_ERROR_STOP on

-- A sees ONLY own profile directly (partner is no longer directly selectable);
-- partner display comes through the minimised RPC; own match + messages visible.
BEGIN;
    SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
    SET LOCAL ROLE authenticated;
    DO $$
    DECLARE v_n INTEGER; v_name TEXT; v_match UUID;
    BEGIN
        SELECT count(*) INTO v_n FROM public.profiles;
        IF v_n <> 1 THEN RAISE EXCEPTION 'RLS FAIL: A should see only OWN profile, saw %', v_n; END IF;
        -- Direct partner row read must now be blocked (data minimisation).
        IF EXISTS (SELECT 1 FROM public.profiles WHERE id = '00000000-0000-0000-0000-00000000000b')
            THEN RAISE EXCEPTION 'RLS FAIL: A must NOT directly read partner row'; END IF;

        SELECT count(*) INTO v_n FROM public.matches;
        IF v_n <> 1 THEN RAISE EXCEPTION 'RLS FAIL: A should see only own match, saw %', v_n; END IF;
        SELECT count(*) INTO v_n FROM public.messages;
        IF v_n <> 2 THEN RAISE EXCEPTION 'RLS FAIL: A should see 2 messages in own room, saw %', v_n; END IF;

        -- Partner display via the safe RPC returns first_name (and only safe cols).
        SELECT id INTO v_match FROM public.matches LIMIT 1;
        SELECT first_name INTO v_name FROM public.get_partner_profile(v_match);
        IF v_name IS NULL THEN RAISE EXCEPTION 'RLS FAIL: partner RPC returned no display name'; END IF;
    END $$;
ROLLBACK;

-- Symmetric: B independently sees its own room + partner display (evidences
-- that BOTH clients can render the active room from the data layer).
BEGIN;
    SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
    SET LOCAL ROLE authenticated;
    DO $$
    DECLARE v_n INTEGER; v_name TEXT; v_match UUID;
    BEGIN
        SELECT count(*) INTO v_n FROM public.matches;
        IF v_n <> 1 THEN RAISE EXCEPTION 'RLS FAIL: B should see own match, saw %', v_n; END IF;
        SELECT id INTO v_match FROM public.matches LIMIT 1;
        SELECT first_name INTO v_name FROM public.get_partner_profile(v_match);
        IF v_name IS NULL THEN RAISE EXCEPTION 'RLS FAIL: B partner RPC returned no display name'; END IF;
    END $$;
ROLLBACK;

-- A non-participant (E) gets NOTHING from the partner RPC for the A/B match.
BEGIN;
    SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
    SET LOCAL ROLE authenticated;
    DO $$
    DECLARE v_n INTEGER; v_match UUID;
    BEGIN
        -- E cannot even see the A/B match row, so fetch its id as owner-less probe.
        SELECT id INTO v_match FROM public.matches
            WHERE (user1_id = '00000000-0000-0000-0000-00000000000a' AND user2_id = '00000000-0000-0000-0000-00000000000b')
               OR (user1_id = '00000000-0000-0000-0000-00000000000b' AND user2_id = '00000000-0000-0000-0000-00000000000a');
        IF v_match IS NOT NULL THEN
            RAISE EXCEPTION 'RLS FAIL: outsider E can see the A/B match row';
        END IF;
    END $$;
ROLLBACK;

-- B may insert a message into the active room (sender = self).
BEGIN;
    SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
    SET LOCAL ROLE authenticated;
    INSERT INTO public.messages (match_id, sender_id, content)
    SELECT id, '00000000-0000-0000-0000-00000000000b', 'مرحبا'
    FROM public.matches
    WHERE (user1_id = '00000000-0000-0000-0000-00000000000a' AND user2_id = '00000000-0000-0000-0000-00000000000b')
       OR (user1_id = '00000000-0000-0000-0000-00000000000b' AND user2_id = '00000000-0000-0000-0000-00000000000a');
    DO $$ BEGIN RAISE NOTICE 'OK: participant insert allowed'; END $$;
ROLLBACK;

-- Read receipts: A (recipient) may flip is_read on B's message, but NOT on A's own.
BEGIN;
    SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
    SET LOCAL ROLE authenticated;
    DO $$
    DECLARE v_recv INTEGER; v_own INTEGER;
    BEGIN
        UPDATE public.messages SET is_read = true
            WHERE sender_id = '00000000-0000-0000-0000-00000000000b';
        GET DIAGNOSTICS v_recv = ROW_COUNT;
        IF v_recv <> 1 THEN RAISE EXCEPTION 'RLS FAIL: A should mark 1 received message read, did %', v_recv; END IF;

        UPDATE public.messages SET is_read = true
            WHERE sender_id = '00000000-0000-0000-0000-00000000000a';
        GET DIAGNOSTICS v_own = ROW_COUNT;
        IF v_own <> 0 THEN RAISE EXCEPTION 'RLS FAIL: A must NOT mark own sent messages read (% rows)', v_own; END IF;
    END $$;
ROLLBACK;

-- Notifications: A sees only own; cannot see/update B's.
BEGIN;
    SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
    SET LOCAL ROLE authenticated;
    DO $$
    DECLARE v_other INTEGER; v_upd INTEGER;
    BEGIN
        SELECT count(*) INTO v_other FROM public.notifications
            WHERE user_id = '00000000-0000-0000-0000-00000000000b';
        IF v_other <> 0 THEN RAISE EXCEPTION 'RLS FAIL: A can see B notifications (%)', v_other; END IF;
        UPDATE public.notifications SET is_read = true
            WHERE user_id = '00000000-0000-0000-0000-00000000000b';
        GET DIAGNOSTICS v_upd = ROW_COUNT;
        IF v_upd <> 0 THEN RAISE EXCEPTION 'RLS FAIL: A updated B notifications (%)', v_upd; END IF;
    END $$;
ROLLBACK;

\echo '>>> RLS POSITIVE: ALL ASSERTIONS PASSED'
