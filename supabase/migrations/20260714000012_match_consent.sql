-- ====================================================================
-- Migration 0012 — match consent (accept/reject before the room opens) / B4
-- --------------------------------------------------------------------
-- Before: the Hunter FORCED a match and dropped both users into an active
-- 24h chat room. Unacceptable for a marriage context. Now:
--   * Hunter creates the match in room_status='pending', clock NOT started.
--   * Each participant records a decision via decide_match() (SECURITY DEFINER;
--     the client cannot flip room_status/decisions directly).
--   * Mutual 'accepted'  -> room_status='active', expires_at = now()+24h.
--   * Any 'rejected'     -> room_status='closed', both return to the pool, and
--     the pair is excluded from re-matching (cooldown).
-- ====================================================================

-- decisions + a nullable clock (pending rooms have no countdown yet) ----
alter table public.matches add column if not exists user1_decision text not null default 'pending';
alter table public.matches add column if not exists user2_decision text not null default 'pending';
alter table public.matches alter column expires_at drop not null;

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'matches_user1_decision_chk') then
        alter table public.matches add constraint matches_user1_decision_chk
            check (user1_decision in ('pending', 'accepted', 'rejected'));
    end if;
    if not exists (select 1 from pg_constraint where conname = 'matches_user2_decision_chk') then
        alter table public.matches add constraint matches_user2_decision_chk
            check (user2_decision in ('pending', 'accepted', 'rejected'));
    end if;
    if not exists (select 1 from pg_constraint where conname = 'matches_room_status_chk') then
        alter table public.matches add constraint matches_room_status_chk
            check (room_status in ('pending', 'active', 'expired', 'closed'));
    end if;
end $$;

-- cooldown: a rejected pair is never re-matched -----------------------
create table if not exists public.match_exclusions (
    user_a     uuid not null,
    user_b     uuid not null,     -- always store the ordered pair (a < b)
    reason     text not null default 'rejected',
    created_at timestamptz not null default now(),
    primary key (user_a, user_b)
);
revoke all on public.match_exclusions from anon, authenticated;

-- ---------------------------------------------------------------------
-- Hunter: create a PENDING room (no clock), skip excluded pairs.
-- ---------------------------------------------------------------------
create or replace function public.hunter_try_match(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me       public.profiles%rowtype;
    v_cand     public.profiles%rowtype;
    v_match_id uuid;
    v_compat   integer;
begin
    select * into v_me from public.profiles
    where id = p_id and account_status in ('pending', 'active')
    for update;
    if not found then return null; end if;

    if exists (
        select 1 from public.matches
        where (user1_id = p_id or user2_id = p_id)
          and room_status in ('pending', 'active')
    ) then
        return null;
    end if;

    select * into v_cand
    from public.profiles c
    where c.id <> v_me.id
      and c.account_status in ('pending', 'active')
      and c.gender is not null and v_me.gender is not null and c.gender <> v_me.gender
      and c.city   is not null and v_me.city   is not null and c.city = v_me.city
      and c.age    is not null and v_me.age    is not null and abs(c.age - v_me.age) <= 10
      and not exists (
            select 1 from public.matches m
            where (m.user1_id = c.id or m.user2_id = c.id)
              and m.room_status in ('pending', 'active')
      )
      and not exists (
            select 1 from public.match_exclusions e
            where e.user_a = least(v_me.id, c.id) and e.user_b = greatest(v_me.id, c.id)
      )
    order by c.created_at asc
    limit 1
    for update skip locked;
    if not found then return null; end if;

    v_compat := greatest(80, 99 - abs(v_me.age - v_cand.age));

    -- PENDING room: no countdown until both accept.
    insert into public.matches (user1_id, user2_id, match_percentage, ai_reasoning,
                                room_status, expires_at)
    values (v_me.id, v_cand.id, v_compat,
            'تم اكتشاف توافق مبدئي بناءً على المدينة والعمر والتوجه.',
            'pending', null)
    returning id into v_match_id;

    update public.profiles set account_status = 'matched'
    where id in (v_me.id, v_cand.id);

    return v_match_id;
end;
$$;

-- ---------------------------------------------------------------------
-- decide_match: the ONLY way a participant records accept/reject.
-- ---------------------------------------------------------------------
create or replace function public.decide_match(p_match_id uuid, p_decision text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid  uuid := (select auth.uid());
    v_m    public.matches%rowtype;
    v_is_u1 boolean;
begin
    if p_decision not in ('accepted', 'rejected') then
        raise exception 'invalid decision %', p_decision using errcode = 'check_violation';
    end if;

    select * into v_m from public.matches where id = p_match_id for update;
    -- IDOR guard: 404-equivalent for non-participants (do not leak existence).
    if not found or v_uid not in (v_m.user1_id, v_m.user2_id) then
        raise exception 'match not found' using errcode = 'no_data_found';
    end if;

    if v_m.room_status <> 'pending' then
        -- idempotent: re-sending the same decision on a still-pending room is a
        -- no-op above; once resolved, further decisions are rejected.
        raise exception 'match already resolved (%).', v_m.room_status using errcode = 'invalid_parameter_value';
    end if;

    v_is_u1 := (v_uid = v_m.user1_id);
    if v_is_u1 then
        update public.matches set user1_decision = p_decision where id = p_match_id;
        v_m.user1_decision := p_decision;
    else
        update public.matches set user2_decision = p_decision where id = p_match_id;
        v_m.user2_decision := p_decision;
    end if;

    if p_decision = 'rejected' then
        update public.matches set room_status = 'closed' where id = p_match_id;
        -- Record the exclusion BEFORE returning users to the pool: reactivating
        -- their account_status re-fires the Hunter, which must already see the
        -- exclusion so it cannot immediately re-match the same pair.
        insert into public.match_exclusions(user_a, user_b, reason)
        values (least(v_m.user1_id, v_m.user2_id), greatest(v_m.user1_id, v_m.user2_id), 'rejected')
        on conflict do nothing;
        update public.profiles set account_status = 'active'
        where id in (v_m.user1_id, v_m.user2_id);
        return 'closed';
    end if;

    -- accepted: activate only on MUTUAL acceptance (start the 24h clock).
    if v_m.user1_decision = 'accepted' and v_m.user2_decision = 'accepted' then
        update public.matches
        set room_status = 'active', expires_at = now() + interval '24 hours'
        where id = p_match_id;
        return 'active';
    end if;

    return 'pending';  -- waiting on the other party
end;
$$;

revoke all on function public.decide_match(uuid, text) from public, anon;
grant execute on function public.decide_match(uuid, text) to authenticated;
