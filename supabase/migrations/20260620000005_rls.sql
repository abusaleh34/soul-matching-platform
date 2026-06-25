-- ====================================================================
-- Migration 0005 — Row-Level Security & Column Privileges
-- --------------------------------------------------------------------
-- BRD §4.1: RLS explicitly enabled on profiles, matches, messages,
-- notifications, with the chat-access rule and privilege isolation.
--
-- Strategy:
--   * Row visibility/mutation gated by RLS policies (auth.uid()).
--   * Column-level GRANTs additionally restrict WHICH columns the client
--     may write — this is how "only allowed mutable columns" and "cannot
--     change is_admin / account_status / sender_id" are enforced at the
--     engine level (privileged columns are simply not granted to clients).
--   * The Hunter & notification functions are SECURITY DEFINER (owned by
--     the migration role) and therefore bypass these client restrictions.
--   * The backend uses the service_role key, which bypasses RLS entirely.
-- ====================================================================

-- --------------------------------------------------------------------
-- PROFILES
-- --------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_select_own        ON public.profiles;
DROP POLICY IF EXISTS profiles_select_partner    ON public.profiles;
DROP POLICY IF EXISTS profiles_insert_own        ON public.profiles;
DROP POLICY IF EXISTS profiles_update_own        ON public.profiles;

-- Read your own profile
CREATE POLICY profiles_select_own ON public.profiles
    FOR SELECT TO authenticated
    USING (id = (SELECT auth.uid()));

-- Read your matched partner's profile, only while an active match links you
CREATE POLICY profiles_select_partner ON public.profiles
    FOR SELECT TO authenticated
    USING (public.is_active_partner(id));

-- Create only your own profile row
CREATE POLICY profiles_insert_own ON public.profiles
    FOR INSERT TO authenticated
    WITH CHECK (id = (SELECT auth.uid()));

-- Update only your own profile row
CREATE POLICY profiles_update_own ON public.profiles
    FOR UPDATE TO authenticated
    USING (id = (SELECT auth.uid()))
    WITH CHECK (id = (SELECT auth.uid()));

-- Column privileges: clients may never write is_admin / account_status /
-- psychological_profile / timestamps. (account_status is driven only by the
-- Hunter / service role; is_admin only by an admin out-of-band.)
REVOKE ALL    ON public.profiles FROM anon;
REVOKE INSERT, UPDATE ON public.profiles FROM authenticated;
GRANT  SELECT ON public.profiles TO authenticated;
GRANT  INSERT (id, first_name, gender, age, height, body_type, marital_status,
               has_children, children_living_with_user, polygamy_preference,
               country, city, location_verified, education_level,
               employment_status, smoking_habit, pref_min_age, pref_max_age,
               pref_min_height, pref_body_type, questionnaire_answers)
       ON public.profiles TO authenticated;
GRANT  UPDATE (id, first_name, gender, age, height, body_type, marital_status,
               has_children, children_living_with_user, polygamy_preference,
               country, city, location_verified, education_level,
               employment_status, smoking_habit, pref_min_age, pref_max_age,
               pref_min_height, pref_body_type, questionnaire_answers)
       ON public.profiles TO authenticated;

-- --------------------------------------------------------------------
-- MATCHES  (read-only for clients; created only by the Hunter)
-- --------------------------------------------------------------------
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS matches_select_participant ON public.matches;

CREATE POLICY matches_select_participant ON public.matches
    FOR SELECT TO authenticated
    USING (user1_id = (SELECT auth.uid()) OR user2_id = (SELECT auth.uid()));

-- No INSERT/UPDATE/DELETE policy => clients cannot write matches at all.
REVOKE ALL    ON public.matches FROM anon, authenticated;
GRANT  SELECT ON public.matches TO authenticated;

-- --------------------------------------------------------------------
-- MESSAGES
-- --------------------------------------------------------------------
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS messages_select_participant ON public.messages;
DROP POLICY IF EXISTS messages_insert_participant ON public.messages;
DROP POLICY IF EXISTS messages_update_recipient   ON public.messages;

-- Read messages only for rooms you participate in
CREATE POLICY messages_select_participant ON public.messages
    FOR SELECT TO authenticated
    USING (public.is_match_participant(match_id));

-- Insert only as yourself, only into your active (non-expired) room
CREATE POLICY messages_insert_participant ON public.messages
    FOR INSERT TO authenticated
    WITH CHECK (
        sender_id = (SELECT auth.uid())
        AND public.is_match_participant(match_id)
        AND public.is_room_active(match_id)
    );

-- Update read-state ONLY on messages you received (never your own)
CREATE POLICY messages_update_recipient ON public.messages
    FOR UPDATE TO authenticated
    USING (public.is_match_participant(match_id) AND sender_id <> (SELECT auth.uid()))
    WITH CHECK (public.is_match_participant(match_id) AND sender_id <> (SELECT auth.uid()));

REVOKE ALL    ON public.messages FROM anon, authenticated;
GRANT  SELECT ON public.messages TO authenticated;
GRANT  INSERT (match_id, sender_id, content) ON public.messages TO authenticated;
GRANT  UPDATE (is_read) ON public.messages TO authenticated;   -- read-receipts only

-- --------------------------------------------------------------------
-- NOTIFICATIONS
-- --------------------------------------------------------------------
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notifications_select_own ON public.notifications;
DROP POLICY IF EXISTS notifications_update_own ON public.notifications;
-- remove the looser policies from the original schema if present
DROP POLICY IF EXISTS "Users can view their own notifications"   ON public.notifications;
DROP POLICY IF EXISTS "Users can update their own notifications" ON public.notifications;

CREATE POLICY notifications_select_own ON public.notifications
    FOR SELECT TO authenticated
    USING (user_id = (SELECT auth.uid()));

CREATE POLICY notifications_update_own ON public.notifications
    FOR UPDATE TO authenticated
    USING (user_id = (SELECT auth.uid()))
    WITH CHECK (user_id = (SELECT auth.uid()));

-- No INSERT policy => only SECURITY DEFINER triggers create notifications.
REVOKE ALL    ON public.notifications FROM anon, authenticated;
GRANT  SELECT ON public.notifications TO authenticated;
GRANT  UPDATE (is_read) ON public.notifications TO authenticated;
