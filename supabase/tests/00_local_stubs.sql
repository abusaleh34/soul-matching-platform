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
-- extra columns the app depends on (real Supabase provides these)
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS is_anonymous BOOLEAN DEFAULT false;

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

-- --------------------------------------------------------------------
-- Stubs for pg_net + Vault so migration 0008's analysis trigger can be
-- CREATED and its FIRING behaviour tested against a stock Postgres.
-- net.http_post records each outbound call into net._sent instead of
-- making a real HTTP request. Real Supabase provides the genuine objects.
-- --------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS net;
CREATE SCHEMA IF NOT EXISTS vault;

CREATE TABLE IF NOT EXISTS net._sent (
    id      BIGSERIAL PRIMARY KEY,
    url     TEXT,
    body    JSONB,
    headers JSONB,
    created TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Signature mirrors pg_net's named params (url/body/params/headers/timeout).
CREATE OR REPLACE FUNCTION net.http_post(
    url                    TEXT,
    body                   JSONB DEFAULT '{}'::jsonb,
    params                 JSONB DEFAULT '{}'::jsonb,
    headers                JSONB DEFAULT '{}'::jsonb,
    timeout_milliseconds   INTEGER DEFAULT 5000
) RETURNS BIGINT
LANGUAGE sql
AS $$
    INSERT INTO net._sent(url, body, headers) VALUES (url, body, headers) RETURNING id;
$$;

-- Minimal vault.decrypted_secrets with a seeded webhook_secret.
CREATE TABLE IF NOT EXISTS vault._secrets (name TEXT PRIMARY KEY, decrypted_secret TEXT);
INSERT INTO vault._secrets(name, decrypted_secret)
    VALUES ('webhook_secret', 'stub-secret')
    ON CONFLICT (name) DO NOTHING;
CREATE OR REPLACE VIEW vault.decrypted_secrets AS
    SELECT name, decrypted_secret FROM vault._secrets;

-- Empty supabase_realtime publication (real Supabase ships this) so migration
-- 0009 can add the core tables to it and the membership can be tested locally.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;
