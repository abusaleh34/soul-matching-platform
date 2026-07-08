# SECURITY ROTATION RUNBOOK — FOUNDER ACTION REQUIRED

**Status:** BLOCKING for soft launch. Prepared by engineering; **executed by the founder** (needs Supabase/Render/Vercel dashboard access and a coordinated `git push --force`).

## Why

The Supabase project URL and **anon key** were:
1. Committed to git history in `frontend/.env` — added in commit `1661364`, deleted in `390ba5c`, **still recoverable** via `git log -p`.
2. Hardcoded as a fallback in `frontend/lib/main.dart` and shipped in every web bundle (removed in code commit `54c16e0`).

Removing the code fallback is done. **The key itself must still be rotated** (a leaked credential is compromised forever) and **purged from history** so a clone can't recover it.

> Anon keys are "public" by design (RLS is the real guard), but this one belongs to the old project `vhayahstcouubjryilvv`, which is being replaced anyway (see `DEPLOYMENT.md`). Rotate regardless — the `service_role` key, if it ever shared history, is catastrophic if leaked.

---

## Step 1 — Rotate keys in the (new) Supabase project

Do this in the **new** project you provision per `DEPLOYMENT.md` (the old `vhayahstcouubjryilvv` now returns NXDOMAIN and should be considered dead/compromised).

1. Supabase Dashboard → **Project Settings → API**.
2. Under **Project API keys**, click **Reveal** then **Roll** (regenerate) both the **`anon`** and **`service_role`** keys. Rolling invalidates the old values immediately.
3. Record the new `anon` key (client) and `service_role` key (server only — never shipped to a client).
4. If the JWT secret was ever exposed, also roll it under **Settings → API → JWT Settings → Generate new secret** (this invalidates all existing user sessions — acceptable pre-launch).

## Step 2 — Purge the leaked key from git history

**Only the leaked file `frontend/.env` needs purging.** Choose ONE tool. Neither is installed locally yet.

### Option A — `git filter-repo` (recommended)

```bash
# Install (macOS): brew install git-filter-repo
# Work on a fresh mirror clone so a mistake can't damage your working repo.
cd /tmp
git clone --mirror https://github.com/abusaleh34/soul-matching-platform.git purge.git
cd purge.git

# Remove the file from ALL history.
git filter-repo --path frontend/.env --invert-paths --force

# Belt-and-suspenders: also scrub the literal key string if it appears anywhere else.
printf '%s==>REDACTED\n' \
  '***REMOVED***' \
  > /tmp/replacements.txt
git filter-repo --replace-text /tmp/replacements.txt --force
```

### Option B — BFG

```bash
# brew install bfg
cd /tmp && git clone --mirror https://github.com/abusaleh34/soul-matching-platform.git purge.git
bfg --delete-files .env purge.git
cd purge.git && git reflog expire --expire=now --all && git gc --prune=now --aggressive
```

## Step 3 — Force-push policy & coordination (FORCE-PUSH = FOUNDER ONLY)

A history purge **rewrites every commit hash**, so it **must** be a coordinated force-push:

1. Announce a freeze. Ensure every collaborator has pushed; there are currently no open PRs/branches other than `main` and `remediation/brd-no-go-closure`.
2. From the purged mirror:
   ```bash
   cd /tmp/purge.git
   git push --force --mirror origin
   ```
3. **Every existing local clone is now poisoned.** Each collaborator must re-clone fresh (do NOT `git pull` — it will merge the old history back). Delete old clones.
4. After the rewrite, delete the stale remote branch if no longer needed:
   ```bash
   git push origin --delete remediation/brd-no-go-closure   # optional; already merged into main
   ```
5. GitHub caches unreachable commits for a while. Open a GitHub Support request to **purge cached views of the leaked commits** (`1661364`, `390ba5c`) if you need them gone from the API/cache immediately.

> Engineering has left the local merge commits UNPUSHED precisely so this rewrite happens first. Coordinate: **purge history → force-push → then push the WP-M0 commits on top of the clean history.**

## Step 4 — Update deploy environment variables

**Render (backend)** — Dashboard → service → **Environment**:
| Key | Value |
|---|---|
| `SUPABASE_URL` | new project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | new **service_role** key (server only) |
| `GEMINI_API_KEY` | (rotate if ever exposed) |
| `SUPABASE_WEBHOOK_SECRET` | new long random secret (`openssl rand -hex 32`) |
| `FRONTEND_ORIGINS` | `https://<your-vercel-domain>` (no localhost in prod) |

**Vercel (frontend)** — the Flutter web build must pass the new anon key at build time via `--dart-define` (Vercel build command / project env). See Step 5.

## Step 5 — Local & CI build command (`--dart-define`)

There is **no fallback** anymore — the build fails loud without these:

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL=https://<new-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<new-anon-key>

# Local run:
flutter run \
  --dart-define=SUPABASE_URL=https://<new-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<new-anon-key>
```

For Vercel, set these in the build command or as build-time env consumed by your Flutter web build script.

---

## Completion checklist (founder ticks each)

- [ ] `anon` + `service_role` keys rolled on the new project
- [ ] JWT secret rolled (if exposed)
- [ ] History purged with filter-repo/BFG on a mirror clone
- [ ] Coordinated `git push --force --mirror` done; team re-cloned
- [ ] GitHub Support asked to purge cached leaked commits (optional)
- [ ] Render env vars updated (incl. new `SUPABASE_WEBHOOK_SECRET`)
- [ ] Vercel `--dart-define` build wired with the new anon key
- [ ] Verified a fresh `flutter build web` fails loud when the defines are omitted
