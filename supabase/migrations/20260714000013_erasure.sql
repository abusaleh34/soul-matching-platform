-- ====================================================================
-- Migration 0013 — right to erasure (PDPL) / B3
-- --------------------------------------------------------------------
-- erase_user() hard-deletes the identity; FK cascades remove the deleter's
-- profile, messages and notifications. Two deliberate choices so the PARTNER
-- degrades gracefully instead of losing everything or crashing:
--   * matches.user{1,2}_id become ON DELETE SET NULL (was CASCADE) + nullable,
--     so the shared room survives (marked 'closed') with the deleter's slot
--     nulled — the partner sees "conversation ended", not a vanished room.
--   * messages.sender_id stays ON DELETE CASCADE, so the DELETER's messages are
--     purged from the partner's copy (the partner must not retain them); the
--     partner's own messages remain.
-- ====================================================================

alter table public.matches alter column user1_id drop not null;
alter table public.matches alter column user2_id drop not null;

alter table public.matches drop constraint if exists matches_user1_id_fkey;
alter table public.matches drop constraint if exists matches_user2_id_fkey;
alter table public.matches
    add constraint matches_user1_id_fkey foreign key (user1_id)
        references public.profiles(id) on delete set null;
alter table public.matches
    add constraint matches_user2_id_fkey foreign key (user2_id)
        references public.profiles(id) on delete set null;

create or replace function public.erase_user(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    -- 1. End the deleter's live rooms so the partner sees a closed conversation.
    update public.matches set room_status = 'closed'
    where (user1_id = p_uid or user2_id = p_uid)
      and room_status in ('pending', 'active');

    -- 2. Purge the deleter's messages from every room (explicit; the sender_id
    --    cascade below would also do this — belt and suspenders).
    delete from public.messages where sender_id = p_uid;

    -- 3. Hard-delete the identity. Cascades: profile, notifications, remaining
    --    deleter messages; matches.user{1,2}_id -> NULL (room preserved).
    delete from auth.users where id = p_uid;
end;
$$;

-- Callable only by the trusted backend (service role), never by clients.
revoke all on function public.erase_user(uuid) from public, anon, authenticated;
grant execute on function public.erase_user(uuid) to service_role;
