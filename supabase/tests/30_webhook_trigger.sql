-- ====================================================================
-- Analysis-webhook trigger FIRING test (regression for the prod defect:
-- 0007 fired on account_status, so it never fired on questionnaire
-- completion). Uses the net.http_post stub (records into net._sent).
-- Raises an exception on any failed assertion so the harness exits non-zero.
-- ====================================================================
DO $$
DECLARE
    v_uid uuid := '00000000-0000-0000-0000-0000000dbf01';
    v_n   int;
    v_rec jsonb;
BEGIN
    TRUNCATE net._sent RESTART IDENTITY;
    DELETE FROM public.profiles WHERE id = v_uid;
    INSERT INTO auth.users(id, email) VALUES (v_uid, 'dbf01@test') ON CONFLICT DO NOTHING;

    -- Unique city so the Hunter cannot match this row and flip it off 'pending'.
    -- 1. INSERT a pending profile with NO questionnaire -> analysis must NOT fire.
    INSERT INTO public.profiles(id, first_name, gender, age, city, account_status)
    VALUES (v_uid, 'احمد', 'ذكر', 30, 'اختبار-ويبهوك', 'pending');
    SELECT count(*) INTO v_n FROM net._sent;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'FAIL: analysis fired at INSERT with empty questionnaire (% calls)', v_n;
    END IF;

    -- 2. UPDATE questionnaire_answers -> analysis MUST fire exactly once.
    UPDATE public.profiles
    SET questionnaire_answers = '{"q1":"القراءة","q9":"الإخلاص"}'::jsonb
    WHERE id = v_uid;
    SELECT count(*) INTO v_n FROM net._sent;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'FAIL: analysis did not fire on questionnaire completion (% calls)', v_n;
    END IF;

    -- The outbound body carries the record to the backend (name-stripping happens
    -- server-side; here we only assert the correct row was dispatched).
    SELECT body INTO v_rec FROM net._sent ORDER BY id DESC LIMIT 1;
    IF (v_rec -> 'record' ->> 'id') <> v_uid::text THEN
        RAISE EXCEPTION 'FAIL: outbound record id mismatch';
    END IF;

    -- 3. UPDATE account_status only -> must NOT fire again (not a questionnaire event).
    UPDATE public.profiles SET account_status = 'active' WHERE id = v_uid;
    SELECT count(*) INTO v_n FROM net._sent;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'FAIL: analysis re-fired on a non-questionnaire update (% calls)', v_n;
    END IF;

    RAISE NOTICE 'OK: analysis trigger fires only on questionnaire completion';
    DELETE FROM public.profiles WHERE id = v_uid;
END $$;
