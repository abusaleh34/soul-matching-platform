-- ====================================================================
-- Migration 0014 — safety minimum (block / report / unmatch / admin) / B5
-- --------------------------------------------------------------------
-- Writes go through SECURITY DEFINER RPCs (reporter/blocker id is taken from
-- auth.uid(), never trusted from the client). Reports are readable ONLY via an
-- admin SECURITY DEFINER function — RLS is NOT broadened for admins. Blocked
-- pairs are permanently excluded from matching.
-- ====================================================================

create table if not exists public.blocks (
    blocker_id uuid not null references public.profiles(id) on delete cascade,
    blocked_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id)
);
alter table public.blocks enable row level security;
drop policy if exists blocks_select_own on public.blocks;
create policy blocks_select_own on public.blocks
    for select to authenticated using (blocker_id = (select auth.uid()));
revoke all on public.blocks from anon, authenticated;
grant select on public.blocks to authenticated;  -- own rows only (policy); writes via RPC

create table if not exists public.reports (
    id          uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references public.profiles(id) on delete cascade,
    reported_id uuid references public.profiles(id) on delete set null,
    match_id    uuid references public.matches(id) on delete set null,
    reason      text,
    status      text not null default 'open',
    created_at  timestamptz not null default now()
);
alter table public.reports enable row level security;
-- No client policy: reports are readable ONLY via admin_list_reports().
revoke all on public.reports from anon, authenticated;

-- block: record it, close any live room, exclude the pair from re-matching ---
create or replace function public.block_user(p_blocked_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid());
begin
    if v_uid is null or p_blocked_id = v_uid then
        raise exception 'invalid block' using errcode = 'check_violation';
    end if;
    insert into public.blocks(blocker_id, blocked_id) values (v_uid, p_blocked_id)
        on conflict do nothing;
    update public.matches set room_status = 'closed'
        where room_status in ('pending', 'active')
          and ((user1_id = v_uid and user2_id = p_blocked_id)
            or (user1_id = p_blocked_id and user2_id = v_uid));
    update public.profiles set account_status = 'active'
        where id in (v_uid, p_blocked_id) and account_status = 'matched';
    insert into public.match_exclusions(user_a, user_b, reason)
        values (least(v_uid, p_blocked_id), greatest(v_uid, p_blocked_id), 'blocked')
        on conflict do nothing;
end $$;
grant execute on function public.block_user(uuid) to authenticated;

create or replace function public.report_user(p_reported_id uuid, p_match_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_id uuid;
begin
    if v_uid is null then raise exception 'not authenticated'; end if;
    insert into public.reports(reporter_id, reported_id, match_id, reason)
        values (v_uid, p_reported_id, p_match_id, p_reason) returning id into v_id;
    return v_id;
end $$;
grant execute on function public.report_user(uuid, uuid, text) to authenticated;

-- unmatch: a participant closes the room (IDOR-guarded) -----------------
create or replace function public.unmatch(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_m public.matches%rowtype;
begin
    select * into v_m from public.matches where id = p_match_id for update;
    if not found or v_uid not in (v_m.user1_id, v_m.user2_id) then
        raise exception 'match not found' using errcode = 'no_data_found';
    end if;
    update public.matches set room_status = 'closed' where id = p_match_id;
    update public.profiles set account_status = 'active'
        where id in (v_m.user1_id, v_m.user2_id) and account_status = 'matched';
end $$;
grant execute on function public.unmatch(uuid) to authenticated;

-- admin: read reports + a reported room's messages (admin only) ---------
create or replace function public.admin_list_reports()
returns setof public.reports language plpgsql security definer set search_path = '' as $$
begin
    if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin) then
        raise exception 'admin only' using errcode = 'insufficient_privilege';
    end if;
    return query select * from public.reports order by created_at desc;
end $$;
grant execute on function public.admin_list_reports() to authenticated;

create or replace function public.admin_room_messages(p_match_id uuid)
returns setof public.messages language plpgsql security definer set search_path = '' as $$
begin
    if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin) then
        raise exception 'admin only' using errcode = 'insufficient_privilege';
    end if;
    return query select * from public.messages where match_id = p_match_id order by created_at;
end $$;
grant execute on function public.admin_room_messages(uuid) to authenticated;

-- hunter: also exclude BLOCKED pairs (either direction) ----------------
create or replace function public.hunter_try_match(p_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
    v_me public.profiles%rowtype; v_cand public.profiles%rowtype;
    v_match_id uuid; v_compat integer;
begin
    select * into v_me from public.profiles
    where id = p_id and account_status in ('pending', 'active') for update;
    if not found then return null; end if;

    if exists (select 1 from public.matches
               where (user1_id = p_id or user2_id = p_id) and room_status in ('pending', 'active')) then
        return null;
    end if;

    select * into v_cand from public.profiles c
    where c.id <> v_me.id
      and c.account_status in ('pending', 'active')
      and c.gender is not null and v_me.gender is not null and c.gender <> v_me.gender
      and c.city   is not null and v_me.city   is not null and c.city = v_me.city
      and c.age    is not null and v_me.age    is not null and abs(c.age - v_me.age) <= 10
      and not exists (select 1 from public.matches m
            where (m.user1_id = c.id or m.user2_id = c.id) and m.room_status in ('pending', 'active'))
      and not exists (select 1 from public.match_exclusions e
            where e.user_a = least(v_me.id, c.id) and e.user_b = greatest(v_me.id, c.id))
      and not exists (select 1 from public.blocks bl
            where (bl.blocker_id = v_me.id and bl.blocked_id = c.id)
               or (bl.blocker_id = c.id and bl.blocked_id = v_me.id))
    order by c.created_at asc limit 1 for update skip locked;
    if not found then return null; end if;

    v_compat := greatest(80, 99 - abs(v_me.age - v_cand.age));
    insert into public.matches (user1_id, user2_id, match_percentage, ai_reasoning, room_status, expires_at)
    values (v_me.id, v_cand.id, v_compat,
            'تم اكتشاف توافق مبدئي بناءً على المدينة والعمر والتوجه.', 'pending', null)
    returning id into v_match_id;
    update public.profiles set account_status = 'matched' where id in (v_me.id, v_cand.id);
    return v_match_id;
end $$;
