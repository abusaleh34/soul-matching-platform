# WP-M0-FA — Founder Actions Executor · GATE-CLOSURE REPORT

**Date:** 2026-07-09
**Outcome:** Both Stage A caveats closed. Stage B is unblocked.
**No secret values appear in this report** (keys/passwords live only in Vault / Render env / Vercel env / the founder's dashboard).

---

## Result at a glance

| # | Step | Status | Proof |
|---|------|--------|-------|
| 0 | Preflight + mirror backup | ✅ | creds present; `git-filter-repo 2.47.0`; backup at `../soul-backup-20260709-072224.git` |
| 1 | History purge (local) | ✅ | `frontend/.env` gone from all history; key/JWT count **0**; WP-M0 commits intact (only the 2 key-bearing ones redacted) |
| 2 | 🔒 Force-push + branch delete | ✅ (APPROVED) | remote `main` `6d8a4af→82c873e`; `frontend/.env` → **404** on remote; remediation branch deleted |
| 3 | 🔒 Provision + rotate/pause old | ✅ (APPROVED "nano rotate old") | new project `zdfzngxjttoiyspeewrz` (eu-central-1, nano, ACTIVE_HEALTHY); old legacy keys **disabled**; old project **PAUSED** |
| 4 | Migrations + verify_rls + webhook | ✅ | 6 migrations HTTP 201; **verify_rls PASS on live DB**; `0007` webhook (pg_net+Vault+pg_cron) applied; committed `4e6c2e4` |
| 5 | Render backend | ✅ | config fixed + repo re-synced; new backend **LIVE**; `GET / → 200`, all protected routes `→ 401` |
| 6 | Vercel frontend | ✅ | prod **READY** (200); served bundle has new ref ×1, **old ref ×0, leaked key ×0** |
| 7 | CI on GitHub Actions | ✅ | run 29011336475 **green** (Backend 22s · DB gate 18s · Frontend 1m41s) |

Final git state: local `main` == remote `main` == `4e6c2e4`; working tree clean.

---

## Caveat closure (the two Stage A caveats)

### Caveat 1 — CI unverified → **CLOSED**
CI is green on GitHub's hosted runners for the current `main` HEAD (`4e6c2e4`, which includes every Stage A change **plus** the new `0007` webhook migration):
- Run: <https://github.com/abusaleh34/soul-matching-platform/actions/runs/29011336475> — **success**
- Jobs: `Backend (pytest)` 22s ✓ · `Database security gate (RLS + Hunter)` 18s ✓ · `Frontend (analyze + test)` 1m41s ✓
- The first attempt failed with *"job was not acquired by Runner of type hosted"* (a transient GitHub runner-capacity error, not a code failure); a re-run passed. An earlier commit (`82c873e`) had also gone green independently.

### Caveat 2 — leaked key in history → **CLOSED (twice over)**
1. **Removed from git history.** `git filter-repo` expunged `frontend/.env` and redacted the key literal across all history.
   - `git log --all --full-history -- frontend/.env` → empty
   - full-history grep for the key signature and the anon-JWT payload → **0**
   - GitHub API `contents/frontend/.env?ref=main` → **404 Not Found**
   - The WP-M0 commit set is intact: 8 commits byte-identical by patch-id; only the 2 commits that actually contained the key (`SECURITY_ROTATION.md` runbook, hardcoded-fallback removal) changed, and only by the `***REMOVED***` redaction.
2. **The key itself is dead.** The old project was found **alive** (`ACTIVE_HEALTHY`, not NXDOMAIN as previously believed), so the leaked anon key was a *live* credential. It is now neutralized: legacy API keys **disabled** on the old project (`enabled:false`, verified) and the project **PAUSED**. Purging history alone would not have been enough — this closes the live exposure.

---

## Step detail & evidence

### Step 0 — Preflight
- Credentials verified present (existence only, never printed): `SUPABASE_ACCESS_TOKEN`, `RENDER_API_KEY`, `VERCEL_TOKEN`.
- Installed `git-filter-repo 2.47.0`. Confirmed clean tree at seal `ce1daca`, 11 unpushed commits, remote `main` still at `6d8a4af`.
- **Mirror backup:** `../soul-backup-20260709-072224.git` (24 commits on `main`) — rollback path for the rewrite.

### Step 1 — History purge (local)
- Purge scope decision (founder ruling: **key-only**): remove `frontend/.env`; redact the KEY everywhere; **leave the public project ref** where it legitimately names the dead project (config.toml / docs / test). The ref is not a secret (it appears in every client URL).
- New local HEAD `82c873e`; `origin` re-added (no push at this step). Rewritten tree green: backend 15 · analyze clean · flutter 28 · DB suite PASS.

### Step 2 — 🔒 Force-push (APPROVED)
- `git push --force origin main` → `6d8a4af...82c873e` (forced).
- `git push origin --delete remediation/brd-no-go-closure` → deleted (that remote branch still held the old key-bearing `main.dart`; it was already merged into `main`).
- Verified: `ls-remote` shows only `main`; remote `main` == local; `frontend/.env` 404 on remote; no remote tags.

### Step 3 — 🔒 Provision + rotate/pause (APPROVED: nano, rotate old, pause if test-only)
- **New project:** `zdfzngxjttoiyspeewrz` "soul-matching-prod", **eu-central-1**, **nano** (free), `ACTIVE_HEALTHY` (db/rest/auth all healthy). URL `https://zdfzngxjttoiyspeewrz.supabase.co`.
- **DB password:** generated with `openssl rand`, used only in the create call, never printed/committed. *(Founder to-do: reset it in the dashboard if you ever need direct psql access — it's not needed for normal operation, which uses the API keys.)*
- **Key scheme:** new project exposes both legacy (`anon`/`service_role` JWT) and modern (`publishable`/`secret`) keys. **Chose legacy JWTs** for guaranteed compatibility with the pinned `supabase_flutter 2.12.2` / `supabase-py 2.28.3`. These are fresh keys, not the leaked ones. *(Follow-up: migrate to publishable/secret keys later, then disable legacy on the new project too.)*
- **Old project data assessment:** 43 `auth.users`, 22 named profiles, **no `notifications` table** (pre-remediation schema), created in an ~11-day April window; anonymous-only auth; never publicly launched → **development/QA test data, nothing to migrate.**
- **Rotated:** legacy keys **disabled** on the old project (`PUT /api-keys/legacy?enabled=false` → `{enabled:false}`), killing the leaked anon key. **Paused** the old project (reversible; all data retained). Untouched: unrelated "Realestate Matching" (active) and "abusaleh34's Project" (inactive).

### Step 4 — Migrations + RLS gate + webhook
- 6 migrations applied to the new project via Management API (HTTP 201 each).
- **`verify_rls` PASS against the live project** (HTTP 201, no invariant raised): RLS on all 4 tables, 0005 column grants, `get_partner_profile` safe projection.
- **`0007_webhook.sql`** (new migration, committed): AFTER-trigger on `profiles` → `pg_net` POST to `…onrender.com/webhook/analyze-profile`; **X-Webhook-Secret read from Supabase Vault** (`webhook_secret`), never hardcoded; `pg_cron` schedule `expire-stale-rooms` every 15 min. Verified on Supabase: `trg_profile_analysis` present, `pg_net`+`pg_cron` enabled, cron job scheduled. All extension-dependent blocks are guarded, so it **no-ops on stock Postgres** — local suite PASS=25, CI green.
- Committed `4e6c2e4`, pushed to the (now clean) history.

### Step 5 — Render backend
- Service already on paid **starter** plan, **not suspended** (founder had upgraded it) — no payment to-do. `GEMINI_API_KEY` already present.
- **Root cause of an initial failed deploy (found & fixed):** the service had stale dashboard config — `startCommand=uvicorn app.main:app` (the *old, deleted* SQLAlchemy entrypoint) and `rootDir=null`, and Render's git mirror was stuck on an old commit (`48578d1`, not in GitHub history) so it kept deploying the old backend, which crashed connecting to the now-paused old DB. Fixed: `rootDir=backend`, `startCommand=uvicorn main:app …`, and re-set the repo link to force a git re-sync so Render could fetch `4e6c2e4`.
- Env updated to the new project: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (new legacy service key), `SUPABASE_WEBHOOK_SECRET` (== Vault value), `FRONTEND_ORIGINS=https://soul-matching-app.vercel.app`.
- **New backend LIVE** (deploy of `4e6c2e4`). Proof:
  - `GET /` → **200** `{"status":"Soul Matching Platform API is running"}` (the *new* app identity)
  - `POST /api/trigger-matchmaking` (no auth) → **401**
  - `POST /api/post-marriage-counselor/<id>` (no auth) → **401**
  - `GET /api/admin/stats` (no auth) → **401**
  - `POST /webhook/analyze-profile` (no secret) → **401**

### Step 6 — Vercel frontend
- Build pipeline already wired for `--dart-define` (`flutter build web … --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY`, rootDir `frontend`).
- Updated `SUPABASE_URL` + `SUPABASE_ANON_KEY` (new project's legacy anon; public-by-design) and redeployed production from `main`.
- **Prod READY, site 200.** Served `main.dart.js` (3.24 MB): new ref `zdfzngxjttoiyspeewrz` ×**1**, old ref `vhayahstcouubjryilvv` ×**0**, leaked key signature ×**0**.

### Step 7 — CI
See Caveat 1 above. Green on `4e6c2e4`.

---

## End-to-end path: proven-live vs reasoned

**Request path:** Flutter (Vercel) → Supabase (new, eu-central-1) for auth/data/realtime; profile-insert → `pg_net` trigger → Render `/webhook/analyze-profile` → Gemini → writes `psychological_profile` + activates; Hunter trigger matches; counselor endpoint streams Gemini advice.

- **Proven live:** Supabase project health; all migrations + `verify_rls` on the live DB; webhook trigger + `pg_net` + Vault secret + `pg_cron` present; Render backend health 200 + 401 on every protected route; Vercel prod 200 with a correctly-pointed bundle; CI green; old key dead + old project paused; `.env` 404 on remote.
- **Reasoned, not exercised end-to-end:** the *async webhook round-trip* (real profile insert → pg_net → Render → Gemini → profile update) was not driven with a live insert — its parts are individually verified and the shared secret matches on both ends (Vault == Render `SUPABASE_WEBHOOK_SECRET`). The Flutter app's *runtime* sign-in against the new project was not click-tested; it's inferred from the bundle contents + a healthy project. The legacy-key choice is proven for backend boot + 401s, but a full authenticated DB query through the stack wasn't exercised.

---

## Remaining founder to-dos (none block soft launch)

1. **(Optional) GitHub Support:** ask them to purge cached unreachable commits `1661364` / `390ba5c`. The key is already dead, so this is hygiene, not a live risk.
2. **New-project DB password:** reset it in the Supabase dashboard for your password manager if you'll use direct psql (not needed for the app).
3. **Old project:** currently PAUSED with legacy keys disabled and data retained. Once you're satisfied nothing is needed from it, you may **delete** it.
4. **Key-scheme migration (later):** move frontend/backend to Supabase publishable/secret keys, then disable legacy keys on the new project too.
5. **Minor CI hygiene:** bump `actions/checkout@v4` / `actions/setup-python@v5` to silence the Node 20 deprecation warning.
6. **Render stale env:** an unused `DATABASE_URL` (old-project DSN) remains on the service — harmless (current backend doesn't read it); remove when convenient.
7. **(Recommended) One real smoke test:** create a throwaway profile on prod to exercise the webhook→Gemini chain once, end-to-end.

---

## GATE CLOSED — READY FOR: PROCEED STAGE B
