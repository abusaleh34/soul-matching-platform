-- ====================================================================
-- Migration 0009 — enable Realtime for the core tables
-- --------------------------------------------------------------------
-- The Flutter app subscribes to Supabase Realtime streams on messages,
-- matches and notifications. Realtime only broadcasts changes for tables
-- that are members of the `supabase_realtime` publication — previously a
-- manual dashboard step (Database → Replication) that was never done on
-- the new project, so new messages never reached the partner's stream.
--
-- Add the tables to the publication as code (idempotent). RLS still gates
-- what each subscriber receives (the messages SELECT policy), so this does
-- not widen visibility.
-- ====================================================================

do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice '0009: supabase_realtime publication absent (non-Supabase env) — realtime membership skipped';
    return;
  end if;

  foreach t in array array['messages', 'matches', 'notifications'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;

  raise notice '0009: realtime enabled for messages/matches/notifications';
end $$;
