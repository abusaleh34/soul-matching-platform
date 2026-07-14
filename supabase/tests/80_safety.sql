-- ====================================================================
-- Safety (migration 0014): block excludes + closes; report visible to admin
-- only; unmatch closes room with an IDOR guard.
-- ====================================================================

-- block: closes the room, records the block, excludes the pair -----------
DO $$
DECLARE
    a uuid := '00000000-0000-0000-0000-0000000fa001';
    b uuid := '00000000-0000-0000-0000-0000000fa002';
    v_city text := 'safety-block'; mid uuid;
BEGIN
    DELETE FROM public.matches WHERE user1_id IN (a,b) OR user2_id IN (a,b);
    DELETE FROM public.match_exclusions WHERE user_a IN (a,b) OR user_b IN (a,b);
    DELETE FROM public.blocks WHERE blocker_id IN (a,b) OR blocked_id IN (a,b);
    DELETE FROM public.profiles WHERE id IN (a,b); DELETE FROM auth.users WHERE id IN (a,b);
    INSERT INTO auth.users(id,email) VALUES (a,'a@s'),(b,'b@s');
    INSERT INTO public.profiles(id,first_name,gender,age,city,account_status) VALUES
        (a,'A','ذكر',30,v_city,'pending'),(b,'B','أنثى',30,v_city,'pending');
    SELECT id INTO mid FROM public.matches WHERE user1_id IN (a,b) AND user2_id IN (a,b) LIMIT 1;

    PERFORM set_config('request.jwt.claim.sub', a::text, true);
    PERFORM public.block_user(b);

    IF (SELECT room_status FROM public.matches WHERE id = mid) <> 'closed' THEN RAISE EXCEPTION 'FAIL: block did not close the room'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.blocks WHERE blocker_id = a AND blocked_id = b) THEN RAISE EXCEPTION 'FAIL: block not recorded'; END IF;
    IF public.hunter_try_match(a) IS NOT NULL THEN RAISE EXCEPTION 'FAIL: blocked pair was re-matched'; END IF;

    DELETE FROM public.matches WHERE user1_id IN (a,b) OR user2_id IN (a,b);
    DELETE FROM public.match_exclusions WHERE user_a IN (a,b) OR user_b IN (a,b);
    DELETE FROM public.blocks WHERE blocker_id IN (a,b) OR blocked_id IN (a,b);
    DELETE FROM public.profiles WHERE id IN (a,b); DELETE FROM auth.users WHERE id IN (a,b);
    RAISE NOTICE 'OK: block closes room, records block, excludes re-match';
END $$;

-- report: admin can read; non-admin cannot -----------------------------
DO $$
DECLARE
    a uuid := '00000000-0000-0000-0000-0000000fa010';
    b uuid := '00000000-0000-0000-0000-0000000fa011';
    adm uuid := '00000000-0000-0000-0000-0000000fa012';
    rid uuid; n int;
BEGIN
    DELETE FROM public.reports WHERE reporter_id IN (a,b,adm) OR reported_id IN (a,b,adm);
    DELETE FROM public.profiles WHERE id IN (a,b,adm); DELETE FROM auth.users WHERE id IN (a,b,adm);
    INSERT INTO auth.users(id,email) VALUES (a,'a@r'),(b,'b@r'),(adm,'adm@r');
    INSERT INTO public.profiles(id,first_name,account_status) VALUES (a,'A','active'),(b,'B','active');
    INSERT INTO public.profiles(id,first_name,account_status,is_admin) VALUES (adm,'ADM','active',true);

    PERFORM set_config('request.jwt.claim.sub', a::text, true);
    rid := public.report_user(b, null, 'harassment');
    IF rid IS NULL THEN RAISE EXCEPTION 'FAIL: report not created'; END IF;

    PERFORM set_config('request.jwt.claim.sub', adm::text, true);
    SELECT count(*) INTO n FROM public.admin_list_reports() WHERE id = rid;
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL: admin cannot see the report (%)', n; END IF;

    BEGIN
        PERFORM set_config('request.jwt.claim.sub', b::text, true);
        PERFORM public.admin_list_reports();
        RAISE EXCEPTION 'FAIL: non-admin read reports';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;

    DELETE FROM public.reports WHERE id = rid;
    DELETE FROM public.profiles WHERE id IN (a,b,adm); DELETE FROM auth.users WHERE id IN (a,b,adm);
    RAISE NOTICE 'OK: report visible to admin only';
END $$;

-- unmatch + IDOR -------------------------------------------------------
DO $$
DECLARE
    d uuid := '00000000-0000-0000-0000-0000000fa020';
    e uuid := '00000000-0000-0000-0000-0000000fa021';
    f uuid := '00000000-0000-0000-0000-0000000fa022';
    v_city text := 'safety-unmatch'; mid uuid;
BEGIN
    DELETE FROM public.matches WHERE user1_id IN (d,e,f) OR user2_id IN (d,e,f);
    DELETE FROM public.profiles WHERE id IN (d,e,f); DELETE FROM auth.users WHERE id IN (d,e,f);
    INSERT INTO auth.users(id,email) VALUES (d,'d@u'),(e,'e@u'),(f,'f@u');
    INSERT INTO public.profiles(id,first_name,gender,age,city,account_status) VALUES
        (d,'D','ذكر',30,v_city,'pending'),(e,'E','أنثى',30,v_city,'pending'),(f,'F','ذكر',40,'other','active');
    SELECT id INTO mid FROM public.matches WHERE user1_id IN (d,e) AND user2_id IN (d,e) LIMIT 1;

    BEGIN
        PERFORM set_config('request.jwt.claim.sub', f::text, true);
        PERFORM public.unmatch(mid);
        RAISE EXCEPTION 'FAIL: non-participant unmatched (IDOR)';
    EXCEPTION WHEN no_data_found THEN NULL; END;

    PERFORM set_config('request.jwt.claim.sub', d::text, true);
    PERFORM public.unmatch(mid);
    IF (SELECT room_status FROM public.matches WHERE id = mid) <> 'closed' THEN RAISE EXCEPTION 'FAIL: unmatch did not close the room'; END IF;

    DELETE FROM public.matches WHERE user1_id IN (d,e,f) OR user2_id IN (d,e,f);
    DELETE FROM public.profiles WHERE id IN (d,e,f); DELETE FROM auth.users WHERE id IN (d,e,f);
    RAISE NOTICE 'OK: unmatch closes room; IDOR blocked';
END $$;
