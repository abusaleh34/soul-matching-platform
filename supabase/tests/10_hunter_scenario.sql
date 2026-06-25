-- ====================================================================
-- Hunter engine behavioural test (BRD §6 End-to-End Match Validation).
-- Runs as the trusted/owner role. Raises an exception on any failed
-- assertion so the harness exits non-zero. Persists data (COMMIT) so the
-- RLS suite can run against it afterwards.
-- ====================================================================
\set ON_ERROR_STOP on

-- Fixed UUIDs
\set A '''00000000-0000-0000-0000-00000000000a'''
\set B '''00000000-0000-0000-0000-00000000000b'''
\set C '''00000000-0000-0000-0000-00000000000c'''
\set D '''00000000-0000-0000-0000-00000000000d'''
\set E '''00000000-0000-0000-0000-00000000000e'''

-- Clean slate
DELETE FROM public.notifications;
DELETE FROM public.messages;
DELETE FROM public.matches;
DELETE FROM public.profiles;
DELETE FROM auth.users;

INSERT INTO auth.users (id, email) VALUES
    (:A, 'a@test.dev'), (:B, 'b@test.dev'), (:C, 'c@test.dev'),
    (:D, 'd@test.dev'), (:E, 'e@test.dev');

-- 1. User A enters the queue (pending). No partner yet.
INSERT INTO public.profiles (id, first_name, gender, age, city, account_status)
VALUES (:A, 'آدم', 'ذكر', 30, 'الرياض', 'pending');

DO $$ BEGIN
    IF (SELECT count(*) FROM public.matches) <> 0 THEN
        RAISE EXCEPTION 'FAIL: a match was created with only one user in the queue';
    END IF;
END $$;

-- 2. User B enters the queue (pending) -> Hunter must fire instantly.
INSERT INTO public.profiles (id, first_name, gender, age, city, account_status)
VALUES (:B, 'حواء', 'أنثى', 28, 'الرياض', 'pending');

-- 3. Exactly one match; 4. both matched; 5. expires_at = +24h; compat set.
DO $$
DECLARE
    v_cnt   INTEGER;
    v_a     TEXT;
    v_b     TEXT;
    v_exp   TIMESTAMPTZ;
    v_made  TIMESTAMPTZ;
    v_pct   INTEGER;
BEGIN
    SELECT count(*) INTO v_cnt FROM public.matches;
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL: expected exactly 1 match, got %', v_cnt; END IF;

    SELECT account_status INTO v_a FROM public.profiles WHERE id = '00000000-0000-0000-0000-00000000000a';
    SELECT account_status INTO v_b FROM public.profiles WHERE id = '00000000-0000-0000-0000-00000000000b';
    IF v_a <> 'matched' OR v_b <> 'matched' THEN
        RAISE EXCEPTION 'FAIL: both users must be matched (A=%, B=%)', v_a, v_b;
    END IF;

    SELECT expires_at, created_at, match_percentage INTO v_exp, v_made, v_pct FROM public.matches LIMIT 1;
    IF v_exp < v_made + interval '23 hours' OR v_exp > v_made + interval '25 hours' THEN
        RAISE EXCEPTION 'FAIL: expires_at must be ~24h after creation (created=%, expires=%)', v_made, v_exp;
    END IF;
    IF v_pct IS NULL OR v_pct < 80 THEN
        RAISE EXCEPTION 'FAIL: compatibility not set sensibly (got %)', v_pct;
    END IF;
    RAISE NOTICE 'OK: A+B matched, 1 room, expires ~24h, compat=%', v_pct;
END $$;

-- 6. Duplicate-matching impossible: a 3rd eligible woman cannot steal A.
INSERT INTO public.profiles (id, first_name, gender, age, city, account_status)
VALUES (:C, 'سارة', 'أنثى', 29, 'الرياض', 'pending');

DO $$ BEGIN
    IF (SELECT count(*) FROM public.matches) <> 1 THEN
        RAISE EXCEPTION 'FAIL: C should not have matched the already-matched A';
    END IF;
    IF (SELECT account_status FROM public.profiles WHERE id = '00000000-0000-0000-0000-00000000000c') <> 'pending' THEN
        RAISE EXCEPTION 'FAIL: C should still be pending';
    END IF;
END $$;

-- 7. A new eligible man pairs with C -> second room.
INSERT INTO public.profiles (id, first_name, gender, age, city, account_status)
VALUES (:D, 'خالد', 'ذكر', 31, 'الرياض', 'pending');

DO $$ BEGIN
    IF (SELECT count(*) FROM public.matches) <> 2 THEN
        RAISE EXCEPTION 'FAIL: expected 2 rooms after D joins, got %', (SELECT count(*) FROM public.matches);
    END IF;
END $$;

-- 8. Notifications: 2 per match, correct BRD payload.
DO $$
DECLARE v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM public.notifications
        WHERE type = 'match' AND title = 'تم ربط التوافق الروحي بنجاح!';
    IF v_n <> 4 THEN RAISE EXCEPTION 'FAIL: expected 4 match notifications, got %', v_n; END IF;
END $$;

-- 9. Re-running the matcher on an already-matched user is a safe no-op.
DO $$
DECLARE v_r UUID;
BEGIN
    v_r := public.hunter_try_match('00000000-0000-0000-0000-00000000000a');
    IF v_r IS NOT NULL THEN RAISE EXCEPTION 'FAIL: matched user re-matched'; END IF;
    IF (SELECT count(*) FROM public.matches) <> 2 THEN RAISE EXCEPTION 'FAIL: room count changed on no-op'; END IF;
END $$;

-- 10. Lone pending user fails safely (no partner of opposite gender).
INSERT INTO public.profiles (id, first_name, gender, age, city, account_status)
VALUES (:E, 'عمر', 'ذكر', 33, 'الرياض', 'pending');
DO $$ BEGIN
    IF (SELECT count(*) FROM public.matches) <> 2 THEN
        RAISE EXCEPTION 'FAIL: E should not have matched (no available woman)';
    END IF;
END $$;

-- 11. Admin sweep is callable and idempotent (no spurious rooms).
DO $$
DECLARE v_made INTEGER;
BEGIN
    v_made := public.run_hunter_sweep();
    IF v_made <> 0 THEN RAISE EXCEPTION 'FAIL: sweep created % unexpected rooms', v_made; END IF;
END $$;

-- 12. Expiry job flips elapsed rooms to 'expired'.
UPDATE public.matches SET expires_at = now() - interval '1 hour'
    WHERE id = (SELECT id FROM public.matches ORDER BY created_at LIMIT 1);
DO $$
DECLARE v_exp INTEGER;
BEGIN
    v_exp := public.expire_stale_rooms();
    IF v_exp <> 1 THEN RAISE EXCEPTION 'FAIL: expected 1 room expired, got %', v_exp; END IF;
END $$;

-- Seed a couple of messages for the RLS read-receipt suite (room A<->B).
-- Re-activate that room first so inserts model a live conversation.
UPDATE public.matches SET room_status = 'active', expires_at = now() + interval '24 hours'
    WHERE (user1_id = :A AND user2_id = :B) OR (user1_id = :B AND user2_id = :A);
INSERT INTO public.messages (match_id, sender_id, content)
    SELECT id, :B, 'رسالة من حواء' FROM public.matches
    WHERE (user1_id = :A AND user2_id = :B) OR (user1_id = :B AND user2_id = :A);
INSERT INTO public.messages (match_id, sender_id, content)
    SELECT id, :A, 'رد من آدم' FROM public.matches
    WHERE (user1_id = :A AND user2_id = :B) OR (user1_id = :B AND user2_id = :A);

\echo '>>> HUNTER SCENARIO: ALL ASSERTIONS PASSED'
