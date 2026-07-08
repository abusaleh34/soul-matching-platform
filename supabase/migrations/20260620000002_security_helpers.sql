-- ====================================================================
-- Migration 0002 — Security Helper Functions
-- --------------------------------------------------------------------
-- SECURITY DEFINER helpers used by RLS policies. Defining them as
-- SECURITY DEFINER lets a policy check membership against `matches`
-- WITHOUT recursively evaluating matches' own RLS (avoids policy
-- recursion and keeps policies fast).
--
-- Hardening applied to every SECURITY DEFINER function:
--   * SET search_path = '' and fully-qualify every identifier
--   * No dynamic SQL
--   * STABLE where read-only
--   * EXECUTE granted only to authenticated (not anon)
-- BRD reference: §4.1 (RLS / chat access rule), §4.2 (definer isolation).
-- ====================================================================

-- True when the current user (auth.uid()) is a participant of p_match_id.
CREATE OR REPLACE FUNCTION public.is_match_participant(p_match_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.matches m
        WHERE m.id = p_match_id
          AND (m.user1_id = (SELECT auth.uid()) OR m.user2_id = (SELECT auth.uid()))
    );
$$;

-- True when the room exists, is active, and has not expired yet.
CREATE OR REPLACE FUNCTION public.is_room_active(p_match_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.matches m
        WHERE m.id = p_match_id
          AND m.room_status = 'active'
          AND m.expires_at > now()
    );
$$;

-- True when an ACTIVE match links the current user to p_other (used to
-- authorise reading a matched partner's profile).
CREATE OR REPLACE FUNCTION public.is_active_partner(p_other UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.matches m
        WHERE m.room_status = 'active'
          AND (
                (m.user1_id = (SELECT auth.uid()) AND m.user2_id = p_other)
             OR (m.user2_id = (SELECT auth.uid()) AND m.user1_id = p_other)
          )
    );
$$;

REVOKE ALL ON FUNCTION public.is_match_participant(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_room_active(UUID)       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_active_partner(UUID)    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_match_participant(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_room_active(UUID)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_active_partner(UUID)    TO authenticated;
