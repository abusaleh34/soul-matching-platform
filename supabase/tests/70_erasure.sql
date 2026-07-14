-- ====================================================================
-- Right to erasure (migration 0013): erase_user removes the deleter and
-- their messages; the partner keeps their own message and a 'closed' room
-- (graceful degradation), never the deleter's content.
-- ====================================================================
DO $$
DECLARE
    a uuid := '00000000-0000-0000-0000-0000000e0001';
    b uuid := '00000000-0000-0000-0000-0000000e0002';
    mid uuid;
    n_a_prof int; n_a_auth int; n_a_msgs int; n_b_msgs int; n_b_notif int;
    v_status text;
BEGIN
    DELETE FROM public.matches WHERE user1_id IN (a,b) OR user2_id IN (a,b);
    DELETE FROM public.profiles WHERE id IN (a,b);
    DELETE FROM auth.users WHERE id IN (a,b);
    INSERT INTO auth.users(id,email) VALUES (a,'a@erase'),(b,'b@erase');
    INSERT INTO public.profiles(id,first_name,gender,age,city,account_status) VALUES
        (a,'A','ذكر',30,'erasure-اختبار','matched'),
        (b,'B','أنثى',30,'erasure-اختبار','matched');
    INSERT INTO public.matches(user1_id,user2_id,room_status,expires_at)
        VALUES (a,b,'active', now()+interval '24 hours') RETURNING id INTO mid;
    INSERT INTO public.messages(match_id,sender_id,content) VALUES
        (mid,a,'رسالة من A'), (mid,b,'رسالة من B');
    INSERT INTO public.notifications(user_id,title,body,type) VALUES (b,'ت','ب','system');

    PERFORM public.erase_user(a);

    -- deleter fully erased
    SELECT count(*) INTO n_a_prof FROM public.profiles WHERE id = a;
    SELECT count(*) INTO n_a_auth FROM auth.users WHERE id = a;
    SELECT count(*) INTO n_a_msgs FROM public.messages WHERE sender_id = a;
    IF n_a_prof <> 0 OR n_a_auth <> 0 OR n_a_msgs <> 0 THEN
        RAISE EXCEPTION 'FAIL: deleter not fully erased (profile=%, auth=%, messages=%)', n_a_prof, n_a_auth, n_a_msgs;
    END IF;

    -- partner keeps their own message; the deleter is no longer referenced
    SELECT count(*) INTO n_b_msgs FROM public.messages WHERE sender_id = b;
    IF n_b_msgs <> 1 THEN RAISE EXCEPTION 'FAIL: partner message wrongly deleted (%)', n_b_msgs; END IF;
    IF EXISTS (SELECT 1 FROM public.matches WHERE user1_id = a OR user2_id = a) THEN
        RAISE EXCEPTION 'FAIL: deleter still referenced by a match';
    END IF;

    -- the room survives as 'closed' with the partner still attached
    SELECT room_status INTO v_status FROM public.matches WHERE id = mid;
    IF v_status <> 'closed' THEN RAISE EXCEPTION 'FAIL: room not closed (got %)', v_status; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.matches WHERE id = mid AND (user1_id = b OR user2_id = b)) THEN
        RAISE EXCEPTION 'FAIL: partner lost their room';
    END IF;

    -- partner's own data intact (they accrued notifications from match/message
    -- triggers; erasing A must not wipe B's notifications)
    SELECT count(*) INTO n_b_notif FROM public.notifications WHERE user_id = b;
    IF n_b_notif < 1 THEN RAISE EXCEPTION 'FAIL: partner notifications wrongly deleted (%)', n_b_notif; END IF;

    DELETE FROM public.matches WHERE id = mid;
    DELETE FROM public.profiles WHERE id = b;
    DELETE FROM auth.users WHERE id = b;
    RAISE NOTICE 'OK: erasure removes deleter + their messages; partner keeps own message + closed room';
END $$;
