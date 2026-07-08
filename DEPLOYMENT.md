# DEPLOYMENT

Authoritative deploy process for the Soul Matching Platform. **Read this before
any production change.** Secrets handling is in `SECURITY_ROTATION.md`.

## Branch & environment policy

- **`main` is the only deployable branch.** Render (backend) and Vercel
  (frontend) must both track `main` and nothing else. Feature work happens on
  branches and merges to `main` only after CI is green.
- CI (`.github/workflows/ci.yml`) gates every push/PR to `main` with four jobs:
  backend `pytest`, frontend `flutter analyze` + `flutter test`, and the
  database security gate (RLS/Hunter behavioural suite + `verify_rls`). A red
  job blocks the merge; a merge does not imply a deploy.

## Deploy order (MANDATORY)

Never deploy the app ahead of the database. The order is:

1. **Apply migrations** to the target Supabase project:
   ```bash
   export SUPABASE_DB_URL='postgresql://postgres.<ref>:<pw>@<host>:5432/postgres?sslmode=require'
   ./supabase/remote/apply.sh          # idempotent; each file in its own txn
   ```
2. **Run the RLS deploy gate** against the same database. Deploy proceeds only
   if this exits 0:
   ```bash
   ./supabase/verify_rls.sh            # asserts RLS on, column grants, safe partner projection
   ```
3. **Deploy the app** (backend on Render, frontend on Vercel) — only after
   steps 1–2 pass.

If `verify_rls` fails, STOP: the client would be exposed because RLS/grants are
the only wall in front of a public anon key. Fix migrations, re-run, then deploy.

## Backend (Render)

- Service defined in `render.yaml` (`rootDir: backend`, `uvicorn main:app`).
- Required env (all `sync: false`, set in the dashboard): `SUPABASE_URL`,
  `SUPABASE_SERVICE_ROLE_KEY`, `GEMINI_API_KEY`, `SUPABASE_WEBHOOK_SECRET`,
  `FRONTEND_ORIGINS` (production origin only — no localhost).
- **Free tier is currently suspended.** Soft launch requires either a paid
  instance or a keep-alive strategy — see the founder checklist in
  `WP-M0-STAGE-A-REPORT.md`.

## Frontend (Vercel)

- Flutter web build. There is **no hardcoded config fallback** — the build
  fails loud without both defines:
  ```bash
  flutter build web --release \
    --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
    --dart-define=SUPABASE_ANON_KEY=<anon-key>
  ```
- Set these as build-time env in the Vercel project so the SPA is built with the
  correct project. SPA routing handled by `frontend/vercel.json`.

## Data residency (INTERIM RULING — FOUNDER TO CONFIRM)

> **Status: PLACEHOLDER pending founder decision.** The old project
> `vhayahstcouubjryilvv` is dead (NXDOMAIN) and must be re-provisioned.

- **Interim ruling:** provision the new Supabase project in the region the
  founder selects at re-provisioning time and record it here (e.g.
  `REGION = <to be filled: e.g. eu-central-1 / me-central / ...>`), along with
  the date and who decided.
- **PDPL migration placeholder:** Saudi PDPL favours in-Kingdom / GCC data
  residency for personal data. If the interim region is outside KSA/GCC, this is
  a KNOWN GAP to close before official launch. Track it as a WP-M1 item:
  "migrate Supabase project + storage to a KSA/GCC region and re-point Render."
  Do not treat the interim choice as the compliance decision.
- Cross-border processors already in the data path (document for the DPIA):
  Google Gemini (psychological text; names are stripped as of Stage A). The
  client-side BigDataCloud geocode was removed in Stage A (city is now picked,
  not derived), eliminating that egress.
