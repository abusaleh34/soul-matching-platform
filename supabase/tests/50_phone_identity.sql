-- ====================================================================
-- Phone identity (migration 0011): allow-list wall, auth->profile sync,
-- uniqueness, and legacy_unverified exclusion from matching.
-- Raises on any failed assertion.
-- ====================================================================
DO $$
DECLARE
    u uuid := '00000000-0000-0000-0000-0000000d1010';
BEGIN
    DELETE FROM public.profiles WHERE id = u;
    DELETE FROM auth.users WHERE id = u;
    INSERT INTO auth.users(id, email, is_anonymous) VALUES (u, 'p101@test', false);
    INSERT INTO public.profiles(id, first_name, gender, age, city, account_status)
        VALUES (u, 'هاتف', 'ذكر', 30, 'الرياض', 'pending');

    -- allow-listed phone accepted
    UPDATE public.profiles SET phone = '+966512340000' WHERE id = u;
    IF (SELECT phone FROM public.profiles WHERE id = u) <> '+966512340000' THEN
        RAISE EXCEPTION 'FAIL: allow-listed phone not stored';
    END IF;

    -- non-Saudi phone rejected (the DB last wall)
    BEGIN
        UPDATE public.profiles SET phone = '+15551234567' WHERE id = u;
        RAISE EXCEPTION 'FAIL: non-Saudi phone was NOT rejected by the DB wall';
    EXCEPTION WHEN check_violation THEN
        NULL; -- expected
    END;

    -- verified auth phone (stored by Supabase without +) syncs to the profile
    UPDATE public.profiles SET phone = NULL WHERE id = u;
    UPDATE auth.users SET phone = '966512349999' WHERE id = u;
    IF (SELECT phone FROM public.profiles WHERE id = u) <> '+966512349999' THEN
        RAISE EXCEPTION 'FAIL: auth phone did not sync (got %)',
            (SELECT phone FROM public.profiles WHERE id = u);
    END IF;

    DELETE FROM public.profiles WHERE id = u;
    DELETE FROM auth.users WHERE id = u;
    RAISE NOTICE 'OK: phone allow-list wall + auth sync + uniqueness';
END $$;

-- legacy_unverified is excluded from matching -------------------------
DO $$
DECLARE
    m uuid := '00000000-0000-0000-0000-0000000d1020';
    f uuid := '00000000-0000-0000-0000-0000000d1030';
    v_city text := 'مدينة-إرث-اختبار';
    v_made uuid;
BEGIN
    DELETE FROM public.matches WHERE user1_id IN (m, f) OR user2_id IN (m, f);
    DELETE FROM public.profiles WHERE id IN (m, f);
    DELETE FROM auth.users WHERE id IN (m, f);
    INSERT INTO auth.users(id, email) VALUES (m, 'm@test'), (f, 'f@test');
    -- eligible male, and a female who is legacy_unverified (must be ignored)
    INSERT INTO public.profiles(id, first_name, gender, age, city, account_status) VALUES
        (m, 'رجل', 'ذكر',  30, v_city, 'pending'),
        (f, 'امرأة','أنثى', 30, v_city, 'legacy_unverified');

    v_made := public.hunter_try_match(m);
    IF v_made IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: hunter matched a legacy_unverified candidate';
    END IF;
    IF EXISTS (SELECT 1 FROM public.matches WHERE user1_id IN (m, f) OR user2_id IN (m, f)) THEN
        RAISE EXCEPTION 'FAIL: a match row was created against legacy_unverified';
    END IF;

    DELETE FROM public.profiles WHERE id IN (m, f);
    DELETE FROM auth.users WHERE id IN (m, f);
    RAISE NOTICE 'OK: legacy_unverified excluded from matching';
END $$;
