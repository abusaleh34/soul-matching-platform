-- ====================================================================
-- Versioned consent (migration 0015): record_consent stamps the caller only,
-- server-timestamped; invalid versions rejected.
-- ====================================================================
DO $$
DECLARE
    u uuid := '00000000-0000-0000-0000-00000000c0a1';
    w uuid := '00000000-0000-0000-0000-00000000c0a2';
    v int; ts timestamptz;
BEGIN
    DELETE FROM public.profiles WHERE id IN (u,w); DELETE FROM auth.users WHERE id IN (u,w);
    INSERT INTO auth.users(id,email) VALUES (u,'u@c'),(w,'w@c');
    INSERT INTO public.profiles(id,first_name,account_status) VALUES (u,'U','active'),(w,'W','active');

    PERFORM set_config('request.jwt.claim.sub', u::text, true);
    PERFORM public.record_consent(1);

    SELECT consent_version, consented_at INTO v, ts FROM public.profiles WHERE id = u;
    IF v <> 1 OR ts IS NULL THEN RAISE EXCEPTION 'FAIL: consent not recorded (v=%, ts=%)', v, ts; END IF;

    -- isolation: the other user is untouched
    IF (SELECT consent_version FROM public.profiles WHERE id = w) <> 0 THEN
        RAISE EXCEPTION 'FAIL: consent leaked to another user';
    END IF;

    -- invalid version rejected
    BEGIN
        PERFORM public.record_consent(0);
        RAISE EXCEPTION 'FAIL: invalid consent version accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;

    DELETE FROM public.profiles WHERE id IN (u,w); DELETE FROM auth.users WHERE id IN (u,w);
    RAISE NOTICE 'OK: consent recorded for caller only, server-stamped, invalid rejected';
END $$;
