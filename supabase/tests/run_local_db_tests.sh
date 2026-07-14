#!/usr/bin/env bash
# ====================================================================
# Local migration + Hunter + RLS validation against a throwaway Postgres.
# Requires Docker. Produces real pass/fail evidence for the remediation
# report. Does NOT touch any production / Supabase database.
# ====================================================================
set -euo pipefail

CONTAINER="soul_pg_test"
PGPORT="55432"
DB="soul"
export PGPASSWORD="postgres"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIG="$HERE/../migrations"
PSQL=(psql -h 127.0.0.1 -p "$PGPORT" -U postgres -d "$DB" -v ON_ERROR_STOP=1 -X -q)

pass=0; fail=0
ok()   { echo "  ✅ $1"; pass=$((pass+1)); }
bad()  { echo "  ❌ $1"; fail=$((fail+1)); }

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== Starting throwaway Postgres 15 =="
cleanup
docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB="$DB" \
    -p "$PGPORT:5432" postgres:15 >/dev/null

echo -n "   waiting for readiness"
for _ in $(seq 1 30); do
    if docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then break; fi
    echo -n "."; sleep 1
done
echo " ready"

echo "== Applying stubs + migrations =="
"${PSQL[@]}" -f "$HERE/00_local_stubs.sql" >/dev/null
for f in "$MIG"/*.sql; do
    "${PSQL[@]}" -f "$f" >/dev/null && ok "applied $(basename "$f")" || bad "apply $(basename "$f")"
done

echo "== Schema objects present =="
check_obj() { # label  sql-returning-boolean
    local got
    got="$("${PSQL[@]}" -tAc "$2" | tr -d '[:space:]')"
    [ "$got" = "t" ] && ok "$1" || bad "$1 (got '$got')"
}
check_obj "profiles/matches/messages/notifications tables exist" \
  "SELECT count(*)=4 FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('profiles','matches','messages','notifications')"
check_obj "Hunter trigger on profiles exists" \
  "SELECT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='hunter_matchmaking_trigger')"
check_obj "Hunter uses FOR UPDATE SKIP LOCKED" \
  "SELECT pg_get_functiondef('public.hunter_try_match(uuid)'::regprocedure) ILIKE '%FOR UPDATE SKIP LOCKED%'"
check_obj "RLS enabled on all 4 tables" \
  "SELECT bool_and(relrowsecurity) FROM pg_class WHERE relname IN ('profiles','matches','messages','notifications')"
check_obj "all SECURITY DEFINER fns pin search_path" \
  "SELECT bool_and(p.proconfig::text ILIKE '%search_path%') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosecdef"

echo "== Hunter behavioural scenario =="
"${PSQL[@]}" -f "$HERE/10_hunter_scenario.sql" >/tmp/hunter.out 2>&1 \
  && ok "hunter scenario assertions" || { bad "hunter scenario"; tail -5 /tmp/hunter.out; }

echo "== RLS positive assertions =="
"${PSQL[@]}" -f "$HERE/20_rls_positive.sql" >/tmp/rls_pos.out 2>&1 \
  && ok "rls positive assertions" || { bad "rls positive"; tail -5 /tmp/rls_pos.out; }

echo "== Analysis-webhook trigger firing (fires on questionnaire completion) =="
"${PSQL[@]}" -f "$HERE/30_webhook_trigger.sql" >/tmp/webhook_trig.out 2>&1 \
  && ok "analysis trigger firing" || { bad "analysis trigger firing"; tail -8 /tmp/webhook_trig.out; }

echo "== Realtime publication membership (messages/matches/notifications) =="
"${PSQL[@]}" -f "$HERE/40_realtime.sql" >/tmp/realtime.out 2>&1 \
  && ok "realtime publication membership" || { bad "realtime publication membership"; tail -6 /tmp/realtime.out; }

echo "== Phone identity (allow-list wall, auth sync, legacy exclusion) =="
"${PSQL[@]}" -f "$HERE/50_phone_identity.sql" >/tmp/phone.out 2>&1 \
  && ok "phone identity" || { bad "phone identity"; tail -10 /tmp/phone.out; }

echo "== Match consent (pending room, mutual-accept, reject, IDOR) =="
"${PSQL[@]}" -f "$HERE/60_match_consent.sql" >/tmp/match_consent.out 2>&1 \
  && ok "match consent" || { bad "match consent"; tail -12 /tmp/match_consent.out; }

echo "== Right to erasure (deleter purged, partner keeps closed room) =="
"${PSQL[@]}" -f "$HERE/70_erasure.sql" >/tmp/erasure.out 2>&1 \
  && ok "right to erasure" || { bad "right to erasure"; tail -12 /tmp/erasure.out; }

echo "== Safety (block/report/unmatch, admin-only reports, IDOR) =="
"${PSQL[@]}" -f "$HERE/80_safety.sql" >/tmp/safety.out 2>&1 \
  && ok "safety block/report/unmatch" || { bad "safety block/report/unmatch"; tail -12 /tmp/safety.out; }

echo "== RLS negative checks (each MUST be rejected) =="
A="00000000-0000-0000-0000-00000000000a"
B="00000000-0000-0000-0000-00000000000b"
E="00000000-0000-0000-0000-00000000000e"
MID="$("${PSQL[@]}" -tAc "SELECT id FROM public.matches WHERE (user1_id='$A' AND user2_id='$B') OR (user1_id='$B' AND user2_id='$A') LIMIT 1" | tr -d '[:space:]')"

deny() { # label  sql  jwt_sub  [role]
    local label="$1" sql="$2" sub="$3" role="${4:-authenticated}"
    if "${PSQL[@]}" -c "SET request.jwt.claim.sub='$sub'; SET ROLE $role; $sql" >/dev/null 2>&1; then
        bad "NOT rejected: $label"
    else
        ok "rejected: $label"
    fi
}

allow() { # label  sql  jwt_sub  [role]   (runs in a rolled-back txn)
    local label="$1" sql="$2" sub="$3" role="${4:-authenticated}"
    if "${PSQL[@]}" -c "BEGIN; SET LOCAL request.jwt.claim.sub='$sub'; SET LOCAL ROLE $role; $sql; ROLLBACK;" >/dev/null 2>&1; then
        ok "allowed: $label"
    else
        bad "WRONGLY rejected: $label"
    fi
}

# The message-send authz contract (client bug was NOT here — RLS is correct):
allow "participant self-insert message"  "INSERT INTO public.messages(match_id,sender_id,content) VALUES ('$MID','$A','hi from A')" "$A"
deny  "anon message insert (lost session)" "INSERT INTO public.messages(match_id,sender_id,content) VALUES ('$MID','$A','from anon')" "" "anon"
deny "spoof sender_id"               "INSERT INTO public.messages(match_id,sender_id,content) VALUES ('$MID','$B','spoof')" "$A"
deny "non-participant message insert" "INSERT INTO public.messages(match_id,sender_id,content) VALUES ('$MID','$E','intruder')" "$E"
deny "tamper is_admin"               "UPDATE public.profiles SET is_admin=true WHERE id='$A'" "$A"
deny "tamper account_status"         "UPDATE public.profiles SET account_status='active' WHERE id='$A'" "$A"
deny "create someone else's profile"  "INSERT INTO public.profiles(id,first_name) VALUES ('$B','x')" "$A"
deny "direct client match insert"    "INSERT INTO public.matches(user1_id,user2_id) VALUES ('$A','$E')" "$A"
deny "anon read profiles"            "SELECT * FROM public.profiles" "$A" "anon"
deny "call run_hunter_sweep as client" "SELECT public.run_hunter_sweep()" "$A"

# partner RPC must NOT expose questionnaire_answers / is_admin / psychological_profile
check_obj "partner RPC exposes only safe columns (no sensitive leak)" \
  "SELECT pg_get_functiondef('public.get_partner_profile(uuid)'::regprocedure) NOT ILIKE '%questionnaire_answers%' AND pg_get_functiondef('public.get_partner_profile(uuid)'::regprocedure) NOT ILIKE '%is_admin%' AND pg_get_functiondef('public.get_partner_profile(uuid)'::regprocedure) NOT ILIKE '%psychological_profile%'"

# outsider E must get ZERO rows from the partner RPC for the real A/B match id
E_ROWS="$("${PSQL[@]}" -tAc "SET request.jwt.claim.sub='$E'; SET ROLE authenticated; SELECT count(*) FROM public.get_partner_profile('$MID')" 2>/dev/null | tr -d '[:space:]' || true)"
[ "$E_ROWS" = "0" ] && ok "partner RPC returns nothing to non-participant E" || bad "partner RPC leaked to E (rows=$E_ROWS)"

# expired-room insert must be rejected
if "${PSQL[@]}" -c "BEGIN; UPDATE public.matches SET expires_at=now()-interval '1 hour' WHERE id='$MID'; SET request.jwt.claim.sub='$A'; SET ROLE authenticated; INSERT INTO public.messages(match_id,sender_id,content) VALUES ('$MID','$A','late'); ROLLBACK;" >/dev/null 2>&1; then
    bad "NOT rejected: message into expired room"
else
    ok "rejected: message into expired room"
fi

echo ""
echo "==================== DB TEST SUMMARY ===================="
echo "  PASS=$pass  FAIL=$fail"
echo "========================================================"
[ "$fail" -eq 0 ]
