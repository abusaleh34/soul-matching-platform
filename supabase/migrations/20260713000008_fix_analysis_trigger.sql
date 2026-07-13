-- ====================================================================
-- Migration 0008 — fix the profile-analysis trigger event
-- --------------------------------------------------------------------
-- BUG (found in prod): migration 0007 attached the analysis trigger to
--   AFTER INSERT OR UPDATE OF account_status ... WHEN (account_status='pending')
-- But onboarding writes the questionnaire as an UPDATE of `questionnaire_answers`
-- (account_status is untouched). Result: the analysis fired at profile INSERT
-- (empty questionnaire) and NEVER when the questionnaire was actually submitted,
-- so `psychological_profile` was never generated and the account never activated.
--
-- FIX: fire on the questionnaire-completion event, only while still pending and
-- only once a questionnaire is present.
--
-- Guarded on net.http_post existence (real pg_net on Supabase, or a test stub in
-- the local suite) so it applies cleanly on a stock Postgres too.
-- ====================================================================

do $do$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'net' and p.proname = 'http_post'
  ) then
    raise notice '0008: net.http_post absent (non-Supabase env) — analysis trigger skipped';
  else
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

    -- Re-point the trigger at the questionnaire-completion event.
    execute 'drop trigger if exists trg_profile_analysis on public.profiles';
    execute $tg$
      create trigger trg_profile_analysis
        after insert or update of questionnaire_answers on public.profiles
        for each row
        when (new.account_status = 'pending' and new.questionnaire_answers is not null)
        execute function public.trigger_profile_analysis()
    $tg$;

    raise notice '0008: analysis trigger now fires on questionnaire completion';
  end if;
end
$do$;
