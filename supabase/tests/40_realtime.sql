-- ====================================================================
-- Realtime publication test: messages/matches/notifications must be members
-- of supabase_realtime (migration 0009), else the app's streams never receive
-- INSERT/UPDATE events. Raises on failure so the harness exits non-zero.
-- ====================================================================
DO $$
DECLARE
    v_n int;
BEGIN
    SELECT count(*) INTO v_n
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename IN ('messages', 'matches', 'notifications');

    IF v_n <> 3 THEN
        RAISE EXCEPTION 'FAIL: realtime publication is missing core tables (have % of 3)', v_n;
    END IF;

    RAISE NOTICE 'OK: realtime enabled for messages/matches/notifications';
END $$;
