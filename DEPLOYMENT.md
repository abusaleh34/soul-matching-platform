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

## Dashboard Settings Checklist (settings that live OUTSIDE the migrations)

**Why this exists:** re-provisioning to Frankfurt lost three settings that are
not in any migration — Anonymous sign-ins (disabled), the analysis trigger
column (a code bug, now fixed), and the `supabase_realtime` publication (empty).
Everything below is either now encoded in a migration, or is a dashboard-only
setting that MUST be re-applied by hand on every re-provision (including the
eventual migration to a KSA-resident / self-hosted Supabase). Verify every row.

Legend: **Encoded** = reproduced by `supabase db push` (migrations). **Manual** =
dashboard / Management API only; no migration can set it.

### Now encoded in migrations (verify they applied, no manual step)
| Setting | Migration | verify |
|---|---|---|
| Extensions: `pg_net`, `pg_cron`, `supabase_vault` | `0010` (+ `0007`) | `select extname from pg_extension` |
| Realtime publication: `messages`, `matches`, `notifications` | `0009` | `select tablename from pg_publication_tables where pubname='supabase_realtime'` |
| Cron: `expire-stale-rooms` every 15 min | `0007` | `select jobname from cron.job` |
| Analysis webhook trigger (fires on `questionnaire_answers`) | `0008` | `40_realtime.sql` / `30_webhook_trigger.sql` in the DB suite |
| RLS + column grants + partner RPC | `0005`/`0006` | `./supabase/verify_rls.sh` (must exit 0) |

> Caveat: on a **self-hosted** Postgres, `supabase_vault`/`pg_net`/`pg_cron` must
> be *available* before `db push` (migration `0007` reads `vault.decrypted_secrets`
> at function-create time). Hosted Supabase pre-enables them. `0010` enables them
> if available and no-ops otherwise.

### Manual — Auth (Dashboard → Authentication) — re-apply every re-provision
| # | Setting | Required value | Current prod state |
|---|---|---|---|
| 1 | **Anonymous sign-ins** (Providers → Anonymous) | **Enabled** (the app signs in anonymously) | ✅ Enabled |
| 2 | **Site URL** (URL Configuration) | `https://soul-matching-app.vercel.app` | ✅ Fixed (was `http://localhost:3000`) |
| 3 | **Redirect URLs** (allow list) | Vercel domain + `http://localhost:3000` (+ `:8080`) for dev | ✅ Fixed (was empty) |
| 4 | **Custom SMTP** (Auth → Emails) | A real SMTP provider before any email flow ships | ⚠️ **Not set** — Supabase default mailer is rate-limited, not production-grade. Not hit today (anonymous auth sends no email); required for Stage B email/magic-link/recovery |
| 5 | **Phone provider** (Providers → Phone) | **Enable** (do NOT pick a built-in provider — we use the Send SMS Hook) | ⚠️ **Disabled** — required for Stage B phone OTP |
| 5a | **Send SMS Hook** (Authentication → Hooks) | Enable; URI `https://soul-matching-api.onrender.com/hooks/send-sms`; copy generated secret → Render `SEND_SMS_HOOK_SECRET`. See `docs/SMS_PROVIDER_INTEGRATION.md` | ⚠️ Not set — required for OTP delivery |
| 5b | **SMS provider choice + CST Sender ID** | Choose Taqnyat/Unifonic; register Sender ID with CST; wire `SaudiSmsProvider` + `SMS_PROVIDER=saudi`,`SMS_API_KEY`,`SMS_SENDER_ID` | ⚠️ Not chosen — soft-launch uses `SMS_PROVIDER=logging` (OTP from logs) |
| 5c | **Auth Rate Limits** (Authentication → Rate Limits) | Set per-IP OTP/SMS limits (the hook can't see client IP — per-phone is enforced in-app) | Default |
| 6 | Email confirmations / OTP expiry / password policy | Per product decision (defaults: confirm on, `password_min_length=6`, sms OTP 60s) | Defaults; revisit for Stage B |
| 7 | Arabic email/SMS templates | Localised Arabic copy | Default English; cosmetic until email/SMS flows go live |

### Manual — Data-plane secrets & other (Management API / Dashboard)
| # | Setting | Action | Current prod state |
|---|---|---|---|
| 8 | **Vault secret `webhook_secret`** | `select vault.create_secret('<value>', 'webhook_secret');` — MUST match Render `SUPABASE_WEBHOOK_SECRET` byte-for-byte | ✅ Set (matches Render) |
| 9 | **Realtime toggle** (Dashboard → Database → Replication) | Encoded in `0009`; if a re-provision predates that migration, also toggle here | ✅ via `0009` |
| 10 | **Storage buckets** | None yet. When photos ship (WP-M1), create the bucket(s) + RLS — will be encoded then | N/A (no media yet) |
| 11 | **API exposed schemas / max rows** | `public,graphql_public`, max_rows 1000 (defaults are correct) | ✅ Default |
| 12 | **SSL enforcement** (DB connections) | Optional hardening; enable if using direct psql from outside | ⚠️ Off (app uses HTTPS API; low priority) |
| 13 | **PITR / backups**, **compute size** | Per ops decision | nano (free) — revisit for launch scale |

### Founder must also re-apply on the app side (see other sections)
- **Render** env: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_WEBHOOK_SECRET` (== Vault #8), `GEMINI_API_KEY` (valid!), `FRONTEND_ORIGINS`; service `rootDir=backend`, `startCommand=uvicorn main:app`, branch `main`.
- **Vercel** env: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (build-time `--dart-define`).

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
