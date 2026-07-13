-- ====================================================================
-- Match consent (migration 0012): pending room, mutual-accept activation,
-- reject -> closed + pool + exclusion, IDOR guard, idempotency.
-- ====================================================================

-- accept/accept + IDOR + idempotency ----------------------------------
DO $$
DECLARE
    a uuid := '00000000-0000-0000-0000-00000000c001';
    b uuid := '00000000-0000-0000-0000-00000000c002';
    c uuid := '00000000-0000-0000-0000-00000000c003';
    v_city text := 'مدينة-قبول-اختبار';
    mid uuid; v_status text; v_exp timestamptz;
BEGIN
    DELETE FROM public.matches WHERE user1_id IN (a,b,c) OR user2_id IN (a,b,c);
    DELETE FROM public.match_exclusions WHERE user_a IN (a,b,c) OR user_b IN (a,b,c);
    DELETE FROM public.profiles WHERE id IN (a,b,c);
    DELETE FROM auth.users WHERE id IN (a,b,c);
    INSERT INTO auth.users(id,email) VALUES (a,'a@t'),(b,'b@t'),(c,'c@t');
    INSERT INTO public.profiles(id,first_name,gender,age,city,account_status) VALUES (a,'A','ذكر',30,v_city,'pending');
    INSERT INTO public.profiles(id,first_name,gender,age,city,account_status) VALUES (b,'B','أنثى',30,v_city,'pending');

    SELECT id INTO mid FROM public.matches WHERE user1_id IN (a,b) AND user2_id IN (a,b) LIMIT 1;
    IF mid IS NULL THEN RAISE EXCEPTION 'setup: hunter did not create a match'; END IF;
    SELECT room_status, expires_at INTO v_status, v_exp FROM public.matches WHERE id = mid;
    IF v_status <> 'pending' OR v_exp IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: new match must be pending with no clock (got % %)', v_status, v_exp;
    END IF;

    -- IDOR: a non-participant cannot decide
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', c::text, true);
        PERFORM public.decide_match(mid, 'accepted');
        RAISE EXCEPTION 'FAIL: non-participant decided the match (IDOR)';
    EXCEPTION WHEN no_data_found THEN NULL; END;

    -- one-sided accept stays pending, no clock
    PERFORM set_config('request.jwt.claim.sub', a::text, true);
    IF public.decide_match(mid, 'accepted') <> 'pending' THEN RAISE EXCEPTION 'FAIL: one-sided accept should be pending'; END IF;
    SELECT room_status INTO v_status FROM public.matches WHERE id = mid;
    IF v_status <> 'pending' THEN RAISE EXCEPTION 'FAIL: room activated before mutual accept'; END IF;

    -- mutual accept -> active + 24h clock
    PERFORM set_config('request.jwt.claim.sub', b::text, true);
    IF public.decide_match(mid, 'accepted') <> 'active' THEN RAISE EXCEPTION 'FAIL: mutual accept did not activate'; END IF;
    SELECT room_status, expires_at INTO v_status, v_exp FROM public.matches WHERE id = mid;
    IF v_status <> 'active' OR v_exp IS NULL THEN RAISE EXCEPTION 'FAIL: not active/clock-started (% %)', v_status, v_exp; END IF;

    -- deciding after resolution is rejected
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', a::text, true);
        PERFORM public.decide_match(mid, 'accepted');
        RAISE EXCEPTION 'FAIL: decide after resolution should error';
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;

    DELETE FROM public.matches WHERE id = mid;
    DELETE FROM public.profiles WHERE id IN (a,b,c);
    DELETE FROM auth.users WHERE id IN (a,b,c);
    RAISE NOTICE 'OK: pending room + IDOR blocked + mutual-accept activates + idempotent';
END $$;

-- reject -> closed, both back to pool, pair excluded from re-match -----
DO $$
DECLARE
    d uuid := '00000000-0000-0000-0000-00000000c010';
    e uuid := '00000000-0000-0000-0000-00000000c011';
    v_city text := 'مدينة-رفض-اختبار';
    mid uuid; v_status text; v_d text; v_e text;
BEGIN
    DELETE FROM public.matches WHERE user1_id IN (d,e) OR user2_id IN (d,e);
    DELETE FROM public.match_exclusions WHERE user_a IN (d,e) OR user_b IN (d,e);
    DELETE FROM public.profiles WHERE id IN (d,e);
    DELETE FROM auth.users WHERE id IN (d,e);
    INSERT INTO auth.users(id,email) VALUES (d,'d@t'),(e,'e@t');
    INSERT INTO public.profiles(id,first_name,gender,age,city,account_status) VALUES (d,'D','ذكر',30,v_city,'pending');
    INSERT INTO public.profiles(id,first_name,gender,age,city,account_status) VALUES (e,'E','أنثى',30,v_city,'pending');

    SELECT id INTO mid FROM public.matches WHERE user1_id IN (d,e) AND user2_id IN (d,e) LIMIT 1;

    PERFORM set_config('request.jwt.claim.sub', d::text, true);
    IF public.decide_match(mid, 'rejected') <> 'closed' THEN RAISE EXCEPTION 'FAIL: reject did not close'; END IF;

    SELECT room_status INTO v_status FROM public.matches WHERE id = mid;
    SELECT account_status INTO v_d FROM public.profiles WHERE id = d;
    SELECT account_status INTO v_e FROM public.profiles WHERE id = e;
    IF v_status <> 'closed' THEN RAISE EXCEPTION 'FAIL: room not closed'; END IF;
    IF v_d <> 'active' OR v_e <> 'active' THEN RAISE EXCEPTION 'FAIL: users not returned to pool (% %)', v_d, v_e; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.match_exclusions WHERE user_a = least(d,e) AND user_b = greatest(d,e)) THEN
        RAISE EXCEPTION 'FAIL: exclusion not recorded';
    END IF;
    -- must not be re-matched to each other
    IF public.hunter_try_match(d) IS NOT NULL THEN RAISE EXCEPTION 'FAIL: rejected pair re-matched'; END IF;

    DELETE FROM public.matches WHERE user1_id IN (d,e) OR user2_id IN (d,e);
    DELETE FROM public.match_exclusions WHERE user_a IN (d,e) OR user_b IN (d,e);
    DELETE FROM public.profiles WHERE id IN (d,e);
    DELETE FROM auth.users WHERE id IN (d,e);
    RAISE NOTICE 'OK: reject closes + returns to pool + excludes re-match';
END $$;
