#!/usr/bin/env bash
# ====================================================================
# Deploy gate: run verify_rls.sql against the TARGET database and exit
# non-zero on any failed security invariant. Read-only (catalog SELECTs).
#
# Usage:
#   export SUPABASE_DB_URL='postgresql://postgres.<ref>:<pw>@<host>:5432/postgres?sslmode=require'
#   ./supabase/verify_rls.sh
#
# Intended order in a deploy: apply migrations -> verify_rls -> deploy app.
# Fails loud: a missing SUPABASE_DB_URL or any invariant violation stops
# the deploy.
# ====================================================================
set -euo pipefail

: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL (Dashboard > Project Settings > Database > Connection string > URI, port 5432).}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL="$HERE/verify_rls.sql"

echo "== verify_rls: asserting RLS + column grants + partner projection =="
if psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -f "$SQL"; then
    echo ">>> verify_rls PASSED"
else
    echo ">>> verify_rls FAILED — do NOT deploy" >&2
    exit 1
fi
