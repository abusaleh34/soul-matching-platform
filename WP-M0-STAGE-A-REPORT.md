# WP-M0 — STAGE A REPORT (Security Closure)

**Branch:** `main` (WP-M0 commits are **local and UNPUSHED** — see Founder Action 2).
**Status:** Stage A complete. **MANDATORY HOLD — awaiting `PROCEED STAGE B`.**

All Stage A work landed as gated, atomic commits with a failing-test-first
discipline for every behavior change. Nothing below is asserted without quoted
command output.

## Commits (this stage)

```
951018b fix(frontend): stop logging PII and surfacing raw provider errors
79c039f fix(frontend): replace geolocation+BigDataCloud with a city picker
a5731e6 fix(backend): strip profile names from the Gemini counselor prompt
170879b ci: add CI pipeline + RLS deploy gate + deployment runbook
976bf65 docs: add SECURITY_ROTATION.md founder runbook
e1b9ac5 chore: add root .gitignore; untrack committed junk
54c16e0 fix(frontend): remove hardcoded Supabase fallback; fail loud on missing config
053932b Merge remediation/brd-no-go-closure into main (WP-M0 A1)
```

Aggregate test state after Stage A: **backend 15 passed**, **frontend 28 passed**,
**flutter analyze: No issues found**, **DB suite PASS=24 FAIL=0**.

---

## A1 — Branch unification

- **Merge type: `--no-ff` merge commit** (`053932b`), not fast-forward. `main`
  was a strict ancestor of the remediation branch (ff was possible), but for a
  security-closure gate an explicit, auditable integration commit is worth more
  than linear history — it records when the remediation became `main`.
- **Legacy dead backend removed by the merge** (all 7 files from audit §9 were
  already deleted on the remediation branch and are now gone from `main`):
  `app/main.py`, `app/api/users.py`, `app/api/match.py`,
  `app/services/matchmaker_service.py`, `app/db/supabase_client.py`,
  `app/db/models.py`, `app/schemas/match.py`. Post-merge check: `gone: …` for
  each.
- **Verification (all green):**
  - `backend $ python -m pytest tests -q` → `14 passed in 0.69s`
  - `frontend $ flutter analyze` → `No issues found!`
  - `frontend $ flutter test` → `All tests passed!` (17 at that point)

## A2 — Secret hygiene (code side)

- **Removed the hardcoded Supabase URL + anon-key fallback** from
  `frontend/lib/main.dart` (`54c16e0`). Config now comes from
  `--dart-define` via a pure resolver `resolveSupabaseConfig()` that throws
  `MissingConfigError` (no fallback); `main()` renders an Arabic
  `ConfigErrorApp` instead of booting against a default/leaked project. Dropped
  the now-unused `flutter_dotenv` dependency.
  - **TDD evidence** (`frontend/test/app_config_test.dart`, 7 cases): RED first
    (`Undefined name 'resolveSupabaseConfig'`), then GREEN. Key cases:
    `throws MissingConfigError when url is empty (no fallback)`,
    `does NOT fall back to the leaked demo project ref` — all pass.
  - Working-tree source confirmed free of the leaked key/ref: `clean: no leaked
    project ref/key in application source`.
- **Root `.gitignore` added + junk untracked** (`e1b9ac5`): `.DS_Store`,
  `backend/.DS_Store`, `frontend/build_log.txt` removed from tracking (kept on
  disk). `git check-ignore` confirms `.env`, `.DS_Store`, `build_log.txt` now
  match. `git ls-files | grep -E 'DS_Store|build_log'` → `no junk tracked`.
- **`SECURITY_ROTATION.md` written** (`976bf65`): exact founder steps to rotate
  keys, purge `frontend/.env` from history (filter-repo **and** BFG commands),
  coordinate the force-push, and update Render/Vercel/`--dart-define`.

## A3 — Migration & RLS deploy gate

- **CI pipeline** `.github/workflows/ci.yml` (`170879b`): on push/PR to `main`,
  four jobs — backend `pytest`, frontend `flutter analyze` + `flutter test`,
  and a `database` job that runs the RLS/Hunter behavioural suite **and**
  `verify_rls` against a freshly migrated Postgres. YAML validated
  (`ci.yml: valid YAML`).
  - **Caveat (honest):** the *green run in GitHub Actions* is **UNVERIFIED** —
    it cannot be executed locally. Every underlying command it runs, however,
    is proven green locally (below).
- **`supabase/verify_rls.sql` + `verify_rls.sh`**: asserts RLS enabled on all
  four tables, the 0005 column grants (privileged columns not client-writable;
  an allowed column is), messages `UPDATE` limited to `is_read`, and
  `get_partner_profile`'s safe projection. **Proof of effect** on an ephemeral
  Postgres:
  - Healthy DB → `>>> verify_rls: ALL INVARIANTS HOLD` / `exit=0`
  - Tampered DB (RLS disabled on `messages`) → `ERROR: RLS DISABLED on: messages` / `exit=3`
- **DB suite wired into CI and proven locally:**
  `bash supabase/tests/run_local_db_tests.sh` → `PASS=24 FAIL=0` (full
  migrations + Hunter scenario + RLS positive + 11 negative/IDOR checks).
- **`DEPLOYMENT.md`**: mandatory order **migrations → verify_rls → app**,
  `main`-only branch policy, interim data-residency ruling + PDPL placeholder.

## A4 — LLM & third-party data minimisation

- **Names stripped from the Gemini prompt** (`a5731e6`): the counselor endpoint
  no longer selects or injects `first_name`; it uses neutral labels
  `الطرف الأول / الطرف الثاني`.
  - **TDD evidence** (`backend/tests/test_counselor_privacy.py`): RED first
    (`'آدم' is contained here: يك الأول (آدم)`), then GREEN. The test captures
    the outbound prompt for a seeded pair and asserts neither name appears while
    the labels and psychological text do. `15 passed`.
- **BigDataCloud geocode removed → city picker** (`79c039f`): deleted
  `LocationService` and the client-side reverse-geocode HTTP call; the profile
  form now uses a deterministic Saudi-cities dropdown. Dropped the unused
  `geolocator`/`geocoding` deps. **This eliminates two PII egresses** (device
  lat/long to a third party, and the geolocation permission itself).
  **Justification for option (a):** a fixed picker is deterministic, needs no
  network and no location permission, keeps matching exact-string based, and
  removes a third-party processor from the DPIA — strictly less data exposure
  than a server-side geocode, for no MVP downside (KSA-only market, curated
  city list). TDD evidence: `saudi_cities_test.dart` RED
  (`Undefined name 'saudiCities'`) → GREEN (4 cases). Post-change grep:
  `clean: no geolocation/BigDataCloud references remain in lib`.
- **PII logging removed** (`951018b`): deleted the `debugPrint` that dumped the
  full questionnaire answers; replaced every user-facing SnackBar that
  interpolated a raw `$e` (profile setup, focus room, notifications, admin,
  welcome) with a generic Arabic message (raw detail → `debugPrint` only).
  Post-change grep: `none: all user-facing SnackBars sanitized`.
  - *Scope note:* the audit named one raw-error site; five more of the same
    class existed. All six were closed for consistency.

## A5 — Adversarial self-review (attempted the original attacks)

Every original attack was re-attempted against the sealed code; each is
rejected:

| Attack | Result | Evidence |
|---|---|---|
| Unauthenticated counselor / admin / trigger | **401** | `test_counselor_requires_token PASSED`, `test_admin_stats_requires_token PASSED`, `test_trigger_requires_token PASSED` |
| `match_id` iteration by a non-participant (IDOR) | **404 (existence not leaked)** | `test_counselor_404_for_non_participant PASSED` |
| Expired-room psych-data access | **403** | `test_counselor_403_when_expired PASSED` |
| Name leak to the LLM | **rejected** | `test_counselor_prompt_contains_no_profile_name PASSED` |
| `is_admin` mass-assignment (client) | **rejected at DB** | `✅ rejected: tamper is_admin` |
| `account_status` mass-assignment | **rejected at DB** | `✅ rejected: tamper account_status` |
| Spoof `sender_id` / non-participant message insert | **rejected** | `✅ rejected: spoof sender_id`, `✅ rejected: non-participant message insert` |
| Partner RPC sensitive-column leak / leak to outsider | **rejected** | `✅ partner RPC exposes only safe columns`, `✅ partner RPC returns nothing to non-participant E` |
| Missing-env silent fallback | **fails loud** | `resolveSupabaseConfig throws MissingConfigError when url is empty (no fallback)`, `does NOT fall back to the leaked demo project ref` |

**Residual (by design, needs a FOUNDER ACTION):** the leaked anon key is gone
from the working tree but **still recoverable from git history** — `occurrences
in history: 2` in `frontend/.env`. This is closed only by Step 2 of
`SECURITY_ROTATION.md` (history purge + force-push).

---

## FOUNDER ACTION CHECKLIST (blocking; engineering cannot do these)

> The WP-M0 commits are intentionally **UNPUSHED** so the history rewrite lands
> first. Sequence: **purge history → force-push → then push these commits on
> top of the clean history.**

1. **Re-provision the Supabase project — choose the region deliberately.** The
   old project `vhayahstcouubjryilvv` is dead (NXDOMAIN). Record the chosen
   region + rationale in `DEPLOYMENT.md` (interim ruling), with the PDPL
   residency migration tracked as WP-M1 if the interim region is outside
   KSA/GCC.
2. **Rotate keys + purge history** per `SECURITY_ROTATION.md`: roll `anon` +
   `service_role` (+ JWT secret if exposed); purge `frontend/.env` with
   filter-repo/BFG; coordinate the **force-push** (founder-only); team re-clones.
3. **Confirm Render deploy branch = `main`; un-suspend/upgrade Render.** The
   free tier is currently **suspended (503)**. Soft launch needs at least a paid
   instance or a keep-alive strategy — decide which. Set all Render env vars
   (incl. a fresh `SUPABASE_WEBHOOK_SECRET` and production-only
   `FRONTEND_ORIGINS`). Wire Vercel's build with the new `--dart-define` values.
4. **Apply migrations to the new project, then run the gate:**
   `./supabase/remote/apply.sh` → `SUPABASE_DB_URL=… ./supabase/verify_rls.sh`
   (must exit 0 before any app deploy).

**Do not begin Stage B build until the above are done and you write
`PROCEED STAGE B`.**
