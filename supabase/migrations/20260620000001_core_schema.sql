-- ====================================================================
-- Migration 0001 — Core Schema Contracts
-- Soul Matching Platform
-- --------------------------------------------------------------------
-- Defines the authoritative table contracts for profiles, matches,
-- messages and notifications. Written to be IDEMPOTENT and SAFE to run
-- against an existing Supabase database where some of these tables may
-- already exist (CREATE TABLE IF NOT EXISTS + ADD COLUMN IF NOT EXISTS).
--
-- BRD references: §3.1 (profiles), §3.2/§3.3 (matches), §3.3 (messages),
-- §3.4 (notifications).
-- ====================================================================

-- Required extension for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- --------------------------------------------------------------------
-- profiles  (id == auth.users.id)
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    first_name TEXT,
    gender TEXT,                       -- 'ذكر' | 'أنثى'
    age INTEGER,
    height INTEGER,
    body_type TEXT,
    marital_status TEXT,
    has_children BOOLEAN,
    children_living_with_user TEXT,
    polygamy_preference TEXT,
    country TEXT,
    city TEXT,
    location_verified BOOLEAN DEFAULT false,
    education_level TEXT,
    employment_status TEXT,
    smoking_habit TEXT,
    pref_min_age INTEGER,
    pref_max_age INTEGER,
    pref_min_height INTEGER,
    pref_body_type TEXT,
    questionnaire_answers JSONB,
    psychological_profile TEXT,
    account_status TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'active' | 'matched'
    is_admin BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Backfill columns on pre-existing deployments
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS first_name TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS gender TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS age INTEGER;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS height INTEGER;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS body_type TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS marital_status TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS has_children BOOLEAN;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS children_living_with_user TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS polygamy_preference TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS country TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS city TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS location_verified BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS education_level TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS employment_status TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS smoking_habit TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pref_min_age INTEGER;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pref_max_age INTEGER;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pref_min_height INTEGER;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pref_body_type TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS questionnaire_answers JSONB;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS psychological_profile TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS account_status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Ensure defaults exist even when the column pre-dated this migration (so the
-- client may omit account_status/is_admin and rely on the DB default).
ALTER TABLE public.profiles ALTER COLUMN account_status SET DEFAULT 'pending';
ALTER TABLE public.profiles ALTER COLUMN is_admin SET DEFAULT false;

-- Constrain account_status to known states. NOT VALID so the migration is safe
-- against an existing table that may hold legacy values: the constraint is
-- enforced on all new writes but pre-existing rows are not retro-validated.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_account_status_chk') THEN
        ALTER TABLE public.profiles
            ADD CONSTRAINT profiles_account_status_chk
            CHECK (account_status IN ('pending', 'active', 'matched')) NOT VALID;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_profiles_matching
    ON public.profiles (account_status, city, gender, age);

-- --------------------------------------------------------------------
-- matches  (the Focus Room record)
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user1_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    user2_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    match_percentage INTEGER NOT NULL DEFAULT 99,
    ai_reasoning TEXT,
    room_status TEXT NOT NULL DEFAULT 'active',     -- 'active' | 'expired' | 'closed'
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 hours'),
    user1_wants_extension BOOLEAN NOT NULL DEFAULT false,
    user2_wants_extension BOOLEAN NOT NULL DEFAULT false,
    extension_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT matches_distinct_users_chk CHECK (user1_id <> user2_id)
);

ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS match_percentage INTEGER NOT NULL DEFAULT 99;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS ai_reasoning TEXT;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS room_status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 hours');
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS user1_wants_extension BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS user2_wants_extension BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS extension_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_matches_user1 ON public.matches (user1_id);
CREATE INDEX IF NOT EXISTS idx_matches_user2 ON public.matches (user2_id);
CREATE INDEX IF NOT EXISTS idx_matches_room_status ON public.matches (room_status);

-- --------------------------------------------------------------------
-- messages
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_read BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_messages_match ON public.messages (match_id, created_at);

-- --------------------------------------------------------------------
-- notifications  (extends the original notifications table)
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'system',   -- 'match' | 'message' | 'system'
    match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE,
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'system';
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications (user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_match ON public.notifications (match_id);

-- keep updated_at fresh on profiles
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
CREATE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
