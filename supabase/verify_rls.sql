-- ====================================================================
-- verify_rls.sql — DEPLOY GATE (run against the TARGET database).
-- --------------------------------------------------------------------
-- Asserts the security invariants that must hold before the app is
-- allowed to serve traffic. Any failed assertion RAISEs an exception;
-- run with `psql -v ON_ERROR_STOP=1 -f verify_rls.sql` so the process
-- exits NON-ZERO on the first failure (fail loud — no partial pass).
--
-- Read-only: SELECTs catalogs only, mutates nothing.
-- Invariants:
--   1. Row-Level Security ENABLED on profiles/matches/messages/notifications.
--   2. Column privileges (migration 0005): `authenticated` cannot write the
--      privileged columns (is_admin / account_status / psychological_profile)
--      and CAN write an allowed column (proves grants are actually applied,
--      not merely all-revoked).
--   3. Messages: `authenticated` may update ONLY is_read (not content/sender_id).
--   4. get_partner_profile exists and its body never exposes sensitive columns.
-- ====================================================================

-- 1. RLS enabled on all four core tables ------------------------------
DO $$
DECLARE
    v_missing text;
BEGIN
    SELECT string_agg(t, ', ')
    INTO v_missing
    FROM unnest(ARRAY['profiles','matches','messages','notifications']) AS t
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = t AND c.relrowsecurity
    );
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'RLS DISABLED on: %', v_missing;
    END IF;
    RAISE NOTICE 'OK: RLS enabled on profiles/matches/messages/notifications';
END $$;

-- 2. Privileged profile columns are NOT client-writable ---------------
DO $$
DECLARE
    v_leaked text;
BEGIN
    SELECT string_agg(column_name || ':' || privilege_type, ', ')
    INTO v_leaked
    FROM information_schema.column_privileges
    WHERE grantee = 'authenticated'
      AND table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name IN ('is_admin','account_status','psychological_profile')
      AND privilege_type IN ('INSERT','UPDATE');
    IF v_leaked IS NOT NULL THEN
        RAISE EXCEPTION 'authenticated can write privileged profile columns: %', v_leaked;
    END IF;
    RAISE NOTICE 'OK: is_admin / account_status / psychological_profile are not client-writable';
END $$;

-- 2b. An allowed profile column IS writable (grants really applied) ----
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.column_privileges
        WHERE grantee = 'authenticated'
          AND table_schema = 'public'
          AND table_name = 'profiles'
          AND column_name = 'first_name'
          AND privilege_type = 'UPDATE'
    ) THEN
        RAISE EXCEPTION 'expected authenticated to have UPDATE on profiles.first_name (0005 grants missing?)';
    END IF;
    RAISE NOTICE 'OK: allowed column profiles.first_name is client-writable';
END $$;

-- 3. messages: authenticated may update only is_read ------------------
DO $$
DECLARE
    v_bad text;
BEGIN
    SELECT string_agg(column_name, ', ')
    INTO v_bad
    FROM information_schema.column_privileges
    WHERE grantee = 'authenticated'
      AND table_schema = 'public'
      AND table_name = 'messages'
      AND privilege_type = 'UPDATE'
      AND column_name <> 'is_read';
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'authenticated can UPDATE non-read-receipt message columns: %', v_bad;
    END IF;
    RAISE NOTICE 'OK: messages UPDATE limited to is_read';
END $$;

-- 4. get_partner_profile exists with a safe projection ----------------
DO $$
DECLARE
    v_def text;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'get_partner_profile'
    ) THEN
        RAISE EXCEPTION 'function public.get_partner_profile is missing (migration 0006 not applied?)';
    END IF;

    v_def := pg_get_functiondef('public.get_partner_profile(uuid)'::regprocedure);
    IF v_def ILIKE '%questionnaire_answers%'
       OR v_def ILIKE '%psychological_profile%'
       OR v_def ILIKE '%is_admin%' THEN
        RAISE EXCEPTION 'get_partner_profile projection leaks a sensitive column';
    END IF;
    RAISE NOTICE 'OK: get_partner_profile exists and exposes only safe columns';
END $$;

\echo '>>> verify_rls: ALL INVARIANTS HOLD'
