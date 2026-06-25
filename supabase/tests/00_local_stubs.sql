-- ====================================================================
-- LOCAL TEST STUBS ONLY — emulates the parts of the Supabase platform the
-- migrations depend on (auth schema, auth.uid(), the anon/authenticated/
-- service_role roles). DO NOT run in production: real Supabase already
-- provides all of these. Used by run_local_db_tests.sh to validate the
-- migrations against a throwaway Postgres instance.
-- ====================================================================
CREATE SCHEMA IF NOT EXISTS auth;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon')          THEN CREATE ROLE anon NOLOGIN; END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role')  THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;

CREATE TABLE IF NOT EXISTS auth.users (
    id    UUID PRIMARY KEY,
    email TEXT
);

-- Emulates Supabase's auth.uid(): reads the JWT subject from a session GUC.
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA auth   TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;
GRANT SELECT ON auth.users TO anon, authenticated, service_role;
