#!/usr/bin/env bash
# ====================================================================
# Apply all migrations to the LIVE Supabase database via psql.
# Each migration runs in its OWN transaction (--single-transaction): if a
# file errors, that file rolls back atomically and the script stops.
# Migrations are idempotent (IF NOT EXISTS / CREATE OR REPLACE / DROP ...
# IF EXISTS), so re-running is safe.
#
# Usage:
#   export SUPABASE_DB_URL='postgresql://postgres.<ref>:<password>@<host>:5432/postgres?sslmode=require'
#   ./supabase/remote/apply.sh            # apply
#   DRY_RUN=1 ./supabase/remote/apply.sh  # list what would run, do nothing
#
# Use the Session pooler or Direct connection (port 5432), NOT the
# transaction pooler (6543) — multi-statement transactions need a session.
# ====================================================================
set -euo pipefail
: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL (Dashboard > Project Settings > Database > Connection string > URI, port 5432).}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIG="$HERE/../migrations"

echo "== Connectivity check =="
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -tAc "select 'connected as ' || current_user" \
  || { echo "ERROR: cannot connect. Check SUPABASE_DB_URL (host/password/sslmode and port 5432)."; exit 1; }

for f in "$MIG"/*.sql; do
  base="$(basename "$f")"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "DRY_RUN would apply: $base"
    continue
  fi
  echo "== applying $base =="
  psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 --single-transaction -q -f "$f"
  echo "   ✅ $base"
done

[ "${DRY_RUN:-0}" = "1" ] && { echo ">>> DRY_RUN only — nothing applied."; exit 0; }

echo ""
echo ">>> All migrations applied. Post-checks:"
psql "$SUPABASE_DB_URL" -X -tAc "select 'hunter trigger: ' || count(*) from pg_trigger where tgname='hunter_matchmaking_trigger';"
psql "$SUPABASE_DB_URL" -X -tAc "select 'RLS-enabled core tables: ' || count(*) from pg_class where relname in ('profiles','matches','messages','notifications') and relrowsecurity;"
psql "$SUPABASE_DB_URL" -X -tAc "select 'partner RPC present: ' || count(*) from pg_proc where proname='get_partner_profile';"
echo ""
echo ">>> Optional: match users who were already pending/active before the trigger existed:"
echo "    psql \"\$SUPABASE_DB_URL\" -c 'select public.run_hunter_sweep();'"
