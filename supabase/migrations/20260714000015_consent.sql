-- ====================================================================
-- Migration 0015 — versioned consent / B2
-- --------------------------------------------------------------------
-- profiles.consent_version + consented_at, written only via record_consent()
-- (SECURITY DEFINER; consented_at = server now(), cannot be backdated by a
-- client). The app compares the stored version to its current constant and
-- routes to the consent screen when the stored version is older (re-consent).
-- ====================================================================

alter table public.profiles add column if not exists consent_version integer not null default 0;
alter table public.profiles add column if not exists consented_at timestamptz;

create or replace function public.record_consent(p_version integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := (select auth.uid());
begin
    if v_uid is null then raise exception 'not authenticated'; end if;
    if p_version < 1 then raise exception 'invalid consent version %', p_version using errcode = 'check_violation'; end if;
    update public.profiles
    set consent_version = p_version, consented_at = now()
    where id = v_uid;
end;
$$;

revoke all on function public.record_consent(integer) from public, anon;
grant execute on function public.record_consent(integer) to authenticated;
