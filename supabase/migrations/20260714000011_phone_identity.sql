-- ====================================================================
-- Migration 0011 — phone as the durable identity anchor (Stage B / B1)
-- --------------------------------------------------------------------
-- * profiles.phone: normalized E.164, UNIQUE. Server-controlled (NOT granted
--   to clients) and populated from the verified auth.users.phone, so a client
--   cannot claim a number it did not verify.
-- * verification_level: 'otp' now, 'nafath' later — Nafath upgrades the SAME
--   row in place (no re-registration).
-- * allow-list as DATA (allowed_phone_prefixes): Saudi-only at launch; adding a
--   GCC country is one INSERT, not a refactor. This is the DB "last wall"
--   (enforced by trigger so it can read the config table — a static CHECK
--   cannot). It holds even against direct API writes.
-- * legacy anonymous rows -> 'legacy_unverified', excluded from matching.
-- ====================================================================

-- 1. Allow-list config (single source of truth at the DB layer) --------
create table if not exists public.allowed_phone_prefixes (
    prefix       text primary key,
    format_regex text not null,
    note         text
);
insert into public.allowed_phone_prefixes(prefix, format_regex, note)
values ('+9665', '^\+9665\d{8}$', 'Saudi mobile (+966 5X XXX XXXX)')
on conflict (prefix) do nothing;

-- config table is server-only
revoke all on public.allowed_phone_prefixes from anon, authenticated;

create or replace function public.phone_is_allowed(p_phone text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.allowed_phone_prefixes a
        where p_phone like a.prefix || '%'
          and p_phone ~ a.format_regex
    );
$$;

-- 2. Columns -----------------------------------------------------------
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists verification_level text not null default 'otp';

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'profiles_phone_unique') then
        alter table public.profiles add constraint profiles_phone_unique unique (phone);
    end if;
    if not exists (select 1 from pg_constraint where conname = 'profiles_verification_level_chk') then
        alter table public.profiles add constraint profiles_verification_level_chk
            check (verification_level in ('otp', 'nafath'));
    end if;
end $$;

-- account_status now includes 'legacy_unverified'
alter table public.profiles drop constraint if exists profiles_account_status_chk;
alter table public.profiles add constraint profiles_account_status_chk
    check (account_status in ('pending', 'active', 'matched', 'legacy_unverified')) not valid;

-- 3. Last wall: reject any phone not on the allow-list (direct writes too)
create or replace function public.enforce_phone_allowlist()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.phone is not null and not public.phone_is_allowed(new.phone) then
        raise exception 'phone % is not on the allowed prefix list', new.phone
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists trg_profiles_phone_allowlist on public.profiles;
create trigger trg_profiles_phone_allowlist
    before insert or update of phone on public.profiles
    for each row execute function public.enforce_phone_allowlist();

-- 4. Server-controlled population from the verified auth phone ----------
create or replace function public.sync_phone_from_auth()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_e164 text;
begin
    if new.phone is null or new.phone = '' then
        return new;
    end if;
    v_e164 := case when left(new.phone, 1) = '+' then new.phone else '+' || new.phone end;
    -- only sync allow-listed numbers; never break auth on a stray value
    if public.phone_is_allowed(v_e164) then
        update public.profiles set phone = v_e164 where id = new.id;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_sync_phone_from_auth on auth.users;
create trigger trg_sync_phone_from_auth
    after insert or update of phone on auth.users
    for each row execute function public.sync_phone_from_auth();

-- 5. Migrate legacy anonymous rows (no verified phone) -----------------
update public.profiles
set account_status = 'legacy_unverified'
where phone is null
  and id in (select id from auth.users where coalesce(is_anonymous, false) = true);

-- hunter_try_match already filters account_status IN ('pending','active'),
-- so 'legacy_unverified' is excluded from both subject and candidate — no
-- change needed there (verified by the DB suite).
