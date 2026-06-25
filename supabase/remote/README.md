# Applying migrations to the live Supabase database

The migrations under `supabase/migrations/` are **idempotent** and safe to run
against your existing project (`vhayahstcouubjryilvv`). Pick **one** path.

> Never paste your database password or `service_role` key into chat or commit
> them. Provide credentials only through your own shell environment.

---

## Path A — Supabase CLI (recommended, tracks history)

```bash
supabase login                                    # one-time, opens browser
supabase link --project-ref vhayahstcouubjryilvv  # prompts for the DB password
supabase db push                                  # applies pending migrations
```

`supabase db push` applies only migrations not yet recorded on the remote and
records them in `supabase_migrations.schema_migrations`.

---

## Path B — psql with a connection string (no login required)

1. Supabase Dashboard → **Project Settings → Database → Connection string → URI**.
   Use the **Session pooler** or **Direct connection** (port **5432**) —
   **not** the Transaction pooler (6543).
2. Export it (note `?sslmode=require`):

   ```bash
   export SUPABASE_DB_URL='postgresql://postgres.vhayahstcouubjryilvv:<DB_PASSWORD>@<host>:5432/postgres?sslmode=require'
   ```
3. Inspect first (read-only), then apply:

   ```bash
   ./supabase/remote/inspect.sh        # prints current schema/policies/triggers; mutates nothing
   DRY_RUN=1 ./supabase/remote/apply.sh  # lists what would run
   ./supabase/remote/apply.sh          # applies all migrations (each in its own transaction)
   ```

---

## After applying

- The Hunter trigger fires on **future** profile inserts/updates. To match users
  who were already `pending`/`active` before the migration:
  ```bash
  psql "$SUPABASE_DB_URL" -c 'select public.run_hunter_sweep();'
  ```
- Enable **Realtime** for `messages`, `matches`, `notifications`
  (Dashboard → Database → Replication → `supabase_realtime`) so the Flutter
  streams receive events.
- Backend env (Render): set `SUPABASE_WEBHOOK_SECRET` and `FRONTEND_ORIGINS`.

## What gets applied
| Migration | Effect |
|---|---|
| `0001_core_schema` | adds missing columns/defaults (`expires_at`, `room_status`, `is_read`, `type`, `match_id`); `account_status` CHECK is `NOT VALID` (won't break legacy rows) |
| `0002_security_helpers` | RLS helper functions |
| `0003_hunter` | the Hunter trigger + `run_hunter_sweep()` + `expire_stale_rooms()` |
| `0004_notifications` | corrected notification triggers (BRD payload) |
| `0005_rls` | RLS policies + column privileges (replaces the old notification policies) |
| `0006_partner_profile` | `get_partner_profile()` + drops the broad partner read policy |
