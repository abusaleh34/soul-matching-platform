-- ====================================================================
-- Migration 0007 — Profile-analysis webhook (as code)
-- --------------------------------------------------------------------
-- Replaces the previously dashboard-configured Supabase Database Webhook.
-- When a profile becomes 'pending', asynchronously POST the row to the
-- backend `/webhook/analyze-profile` via pg_net so it can generate the
-- psychological profile and activate the account.
--
-- SECURITY: the shared X-Webhook-Secret is read at call time from Supabase
-- Vault (secret name 'webhook_secret') and is NEVER stored in this file or
-- in git. Set it out-of-band with:
--   select vault.create_secret('<secret>', 'webhook_secret');
-- and configure the SAME value as SUPABASE_WEBHOOK_SECRET on the backend.
--
-- PORTABILITY: pg_net / vault / pg_cron exist on Supabase but not on a stock
-- Postgres (local throwaway test DB / CI). Every block below is guarded so
-- the migration applies cleanly there too — it simply no-ops the webhook and
-- cron wiring when the extensions are unavailable.
-- ====================================================================

-- Webhook trigger — only where pg_net is available (i.e. real Supabase).
do $do$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice '0007: pg_net unavailable (non-Supabase env) — webhook trigger skipped';
  else
    create extension if not exists pg_net;

    execute $fn$
      create or replace function public.trigger_profile_analysis()
      returns trigger
      language plpgsql
      security definer
      set search_path = ''
      as $body$
      declare
        v_secret text;
      begin
        select decrypted_secret into v_secret
        from vault.decrypted_secrets
        where name = 'webhook_secret'
        limit 1;

        -- Fail loud (log) rather than POST without authentication.
        if v_secret is null then
          raise warning 'webhook_secret missing from vault; profile-analysis webhook skipped for %', new.id;
          return new;
        end if;

        perform net.http_post(
          url := 'https://soul-matching-api.onrender.com/webhook/analyze-profile',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'X-Webhook-Secret', v_secret
          ),
          body := jsonb_build_object(
            'type', tg_op,
            'table', 'profiles',
            'schema', 'public',
            'record', to_jsonb(new),
            'old_record', case when tg_op = 'UPDATE' then to_jsonb(old) else null end
          )
        );
        return new;
      end;
      $body$;
    $fn$;

    execute 'revoke all on function public.trigger_profile_analysis() from public, anon, authenticated';
    execute 'drop trigger if exists trg_profile_analysis on public.profiles';
    execute $tg$
      create trigger trg_profile_analysis
        after insert or update of account_status on public.profiles
        for each row
        when (new.account_status = 'pending')
        execute function public.trigger_profile_analysis()
    $tg$;

    raise notice '0007: profile-analysis webhook trigger created';
  end if;
end
$do$;

-- pg_cron: expire stale focus rooms every 15 minutes (infra for Stage B / B5).
do $cron$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice '0007: pg_cron unavailable — expire-stale-rooms schedule left as a documented stub';
  else
    create extension if not exists pg_cron;
    if exists (select 1 from cron.job where jobname = 'expire-stale-rooms') then
      perform cron.unschedule('expire-stale-rooms');
    end if;
    perform cron.schedule('expire-stale-rooms', '*/15 * * * *', 'select public.expire_stale_rooms();');
    raise notice '0007: scheduled expire-stale-rooms every 15 minutes';
  end if;
exception when others then
  raise notice '0007: pg_cron scheduling skipped (%); left as a documented stub', sqlerrm;
end
$cron$;
