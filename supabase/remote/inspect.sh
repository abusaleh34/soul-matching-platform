#!/usr/bin/env bash
# ====================================================================
# READ-ONLY pre-flight inspection of the LIVE Supabase database.
# Run this BEFORE apply.sh to confirm the migrations will land cleanly.
# It mutates nothing.
#
# Usage:
#   export SUPABASE_DB_URL='postgresql://postgres.<ref>:<password>@<host>:5432/postgres?sslmode=require'
#   ./supabase/remote/inspect.sh
# ====================================================================
set -euo pipefail
: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL (Supabase Dashboard > Project Settings > Database > Connection string > URI). Use the Session pooler or Direct connection (port 5432), NOT the transaction pooler (6543).}"

PSQL=(psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -X)

echo "================ CONNECTION ================"
"${PSQL[@]}" -c "select current_database() as db, current_user as role, version();"

echo "================ CORE TABLES (columns) ================"
"${PSQL[@]}" -c "
select table_name, count(*) as columns
from information_schema.columns
where table_schema='public' and table_name in ('profiles','matches','messages','notifications')
group by table_name order by table_name;"

echo "================ ROW COUNTS ================"
for t in profiles matches messages notifications; do
  "${PSQL[@]}" -tAc "select '$t = ' || count(*) from public.$t" 2>/dev/null || echo "$t = (missing)"
done

echo "================ account_status values (CHECK-constraint safety) ================"
"${PSQL[@]}" -c "select account_status, count(*) from public.profiles group by account_status order by 1;" 2>/dev/null || echo "(profiles not present yet)"

echo "================ EXISTING RLS POLICIES ================"
"${PSQL[@]}" -c "
select tablename, policyname, cmd
from pg_policies
where schemaname='public' and tablename in ('profiles','matches','messages','notifications')
order by tablename, policyname;"

echo "================ EXISTING TRIGGERS ================"
"${PSQL[@]}" -c "
select event_object_table as table, trigger_name, action_timing, event_manipulation
from information_schema.triggers
where trigger_schema='public'
order by 1,2;"

echo "================ DOES THE HUNTER ALREADY EXIST? ================"
"${PSQL[@]}" -c "select tgname from pg_trigger where tgname='hunter_matchmaking_trigger';"

echo "================ MIGRATION HISTORY (if any) ================"
"${PSQL[@]}" -c "select version, name from supabase_migrations.schema_migrations order by version;" 2>/dev/null || echo "(no supabase migration history table yet — first push will create it)"

echo ""
echo ">>> Inspection complete. Review the above, then run ./supabase/remote/apply.sh"
