-- ====================================================================
-- Migration 0010 — declare required extensions explicitly
-- --------------------------------------------------------------------
-- The app depends on pg_net (webhook), pg_cron (room expiry) and
-- supabase_vault (webhook secret storage). Hosted Supabase pre-enables
-- these, so earlier migrations assumed them — but that assumption is
-- exactly the class of "lives outside the migrations" gap that broke us
-- on re-provision. Declare them here so the requirement is encoded and a
-- fresh apply (incl. a future self-hosted / KSA-resident Supabase) enables
-- them rather than silently depending on defaults.
--
-- Guarded on availability so the migration still no-ops on a stock Postgres
-- (local test DB / CI) where these extensions are not present.
--
-- NOTE: supabase_vault must exist BEFORE migration 0007's function (which
-- reads vault.decrypted_secrets) is created. On hosted Supabase it always
-- does. On self-hosted, enable it first — see DEPLOYMENT.md.
-- ====================================================================

do $$
declare
  ext text;
begin
  foreach ext in array array['supabase_vault', 'pg_net', 'pg_cron'] loop
    if exists (select 1 from pg_available_extensions where name = ext) then
      if not exists (select 1 from pg_extension where extname = ext) then
        execute format('create extension if not exists %I', ext);
        raise notice '0010: enabled extension %', ext;
      end if;
    else
      raise notice '0010: extension % unavailable in this environment — skipped', ext;
    end if;
  end loop;
end $$;
