# WP-M0 — STAGE B REPORT (Soft-Launch Trust Layer)

**Date:** 2026-07-14 · **Verdict: 🔴 NO-GO for soft launch.**

Two of the six sub-packages are delivered and **proven on prod** (B1 phone-OTP
foundation; B4 match accept/reject — the DB core). The rest (B2 consent, B3
erasure, B5 safety, plus the Flutter screens for B1/B4 and the live OTP journey)
are **not built**. This report does not soften that. Evidence is quoted; nothing
is asserted without it.

I prioritised the two highest-value items — the provider-agnostic OTP foundation
("build this first") and killing the **forced match** ("unacceptable for real
users") — and did them to the required standard (TDD + prod proof) rather than
spreading thin and faking completion across all six.

---

## Delivered & proven

### B1 — Phone OTP, provider-agnostic ✅ (code + prod schema + live hook)
- **Provider abstraction** (`backend/app/sms/`): `SmsProvider.send()`,
  `LoggingSmsProvider` (logs OTP, sends nothing), `NullSmsProvider` (fail loud),
  `SaudiSmsProvider` (documented stub). `get_sms_provider()` selects by
  `SMS_PROVIDER`. Wiring the real provider = one class + env vars.
  `docs/SMS_PROVIDER_INTEGRATION.md` written. TDD: 5 cases.
- **Phone allow-list** (`app/phone.py`) — single source of truth, allow-list as
  DATA (`+9665`); GCC = one-line change. TDD: 12 cases.
- **Send SMS Hook** `POST /hooks/send-sms`: Standard Webhooks signature +
  server-side allow-list guard + per-phone rate limit (5/15m) → provider.
  **Live on prod:** unsigned call → **HTTP 401** (deploy `6358366`). TDD: hook
  + rate-limit + signature = 11 cases.
- **Schema (migration 0011, applied to prod):** `profiles.phone` (E.164, UNIQUE,
  server-controlled), `verification_level` (`otp`|`nafath` — Nafath upgrades in
  place), allow-list config table + trigger (DB last wall), legacy anonymous rows
  → `legacy_unverified` (excluded from matching).
  **Proven on prod:** columns present, `+9665` seeded, احمد/منى →
  `legacy_unverified`, and a `+1` US number rejected with `23514 ... not on the
  allowed prefix list`.
- Backend suite **46 passed**; DB suite **PASS=36**.
- **Blocked for live use** → FOUNDER ACTIONS (below): SMS provider choice, enable
  Phone provider, wire Send SMS Hook + secret.

### B4 — Match accept/reject (DB core) ✅ (prod-proven)
- Migration 0012: Hunter now creates `room_status='pending'` **with no clock**;
  `decide_match()` (SECURITY DEFINER — client cannot flip status/decisions) is the
  only decision path; mutual `accepted` → `active` + 24h clock; any `rejected` →
  `closed`, both return to the pool, pair added to `match_exclusions` (never
  re-matched). Exclusion is inserted **before** reactivation (a bug I caught in
  test: otherwise the re-fired Hunter re-matches the pair).
- TDD (`60_match_consent.sql`): accept/accept, reject, **IDOR (non-participant
  cannot decide)**, idempotency. Updated the hunter scenario to the new
  lifecycle. DB suite **PASS=36**, CI green (`87779fc`).
- **Proven on prod:** `created=pending`, `clock=null`, **IDOR blocked
  (no_data_found)**, one-sided accept stays `pending`, **mutual accept →
  `active` + clock set**.
- **Remaining:** the Flutter accept/reject **screen** (safe projection via the
  existing `get_partner_profile` RPC) is **not built** — the DB enforcement is,
  so the client cannot bypass it, but there is no UI yet.

---

## Not built (honest status)

| Sub-package | Status | What's missing |
|---|---|---|
| **B2 — Versioned consent** | ❌ NOT STARTED | `consent_version`/`consented_at` columns, `legal/consent_v1_ar.md`, blocking consent screen + re-consent routing |
| **B3 — Right to erasure** | ❌ NOT STARTED | `DELETE /me` (cascade + purge deleter's messages from the partner's copy), Flutter delete flow, the graceful-degradation test |
| **B4 — Flutter accept/reject UI** | ❌ NOT STARTED | screen calling `decide_match`; DB core is done & enforced |
| **B5 — Safety minimum** | ❌ NOT STARTED | `blocks`/`reports` tables + RLS, unmatch, hunter block-exclusion, admin SECURITY DEFINER report view; **verify `expire_stale_rooms` actually fires on pg_cron in prod** |
| **B6 — Live journey** | ❌ BLOCKED | end-to-end prod journey (register→…→delete) — blocked on the B1 founder actions (no Phone provider / hook wired) |
| **B1 — Phone OTP client UI** | ❌ NOT STARTED | Flutter phone-entry/OTP screen with the `05../5..` normalization + Arabic non-Saudi error |

## Updated feature-status (Stage B slice)

| Feature | Status | Evidence |
|---|---|---|
| Provider-agnostic SMS + allow-list + hook | DONE (code/prod) | 401 live; 46 backend tests |
| Phone identity schema + legacy migration | DONE (prod) | 0011; `23514` wall proven |
| Phone OTP client flow | NOT STARTED | — |
| Match pending + accept/reject (DB) | DONE (prod) | 0012; prod proof above |
| Match accept/reject UI | NOT STARTED | — |
| Consent (versioned) | NOT STARTED | — |
| Right to erasure | NOT STARTED | — |
| Blocks/reports/unmatch/admin | NOT STARTED | — |

---

## FOUNDER ACTIONS (blocking the live OTP journey; in DEPLOYMENT.md checklist)
1. **Choose a Saudi SMS provider** (Taqnyat/Unifonic) + register a **CST Sender ID**.
2. **Supabase → Auth → Providers → Phone: enable** (no built-in provider — we use the hook).
3. **Supabase → Auth → Hooks → Send SMS Hook: enable**, URI
   `https://soul-matching-api.onrender.com/hooks/send-sms`, copy the secret →
   Render `SEND_SMS_HOOK_SECRET`. Set `SMS_PROVIDER=logging` for the dry run.
4. **Supabase → Auth → Rate Limits:** set per-IP OTP/SMS limits.

Once (2)+(3) are done I can drive the live journey with `LoggingSmsProvider`
(OTP from Render logs), per your B6 instruction.

## Privacy re-verify
The Stage A guarantee (**`first_name` never reaches Gemini**) is **unchanged** —
`analyze_profile` still strips PII and logs only payload keys; last session's prod
log showed `outbound payload keys: ['q1'..'q12']`. Not re-driven this session (the
code path was not touched); it will be re-confirmed in the live B6 journey.

## Launch risk to flag (not fixed — WP-M2 per your instruction)
The landing page promises a **"1500-dimension psychological fingerprint"**, but
matching is demographic-only (same city, opposite gender, ±10y; score
`99 - ageDiff`). This promise-vs-product gap is a **launch/reputational risk** and
a WP-M2 decision. Surfaced, not touched.

---

## SOFT-LAUNCH GO/NO-GO — 🔴 NO-GO

| # | Gate | State |
|---|---|---|
| 1 | Phone-OTP auth works end-to-end on prod | 🔴 RED — code done; Phone provider + Send SMS Hook not wired (founder) |
| 2 | Saudi-only enforced (client/server/DB) | 🟡 server + DB done & proven; **client UI not built** |
| 3 | Match requires mutual accept (no forced rooms) | 🟡 DB enforced & prod-proven; **accept/reject UI not built** |
| 4 | Consent captured + versioned | 🔴 RED — not built |
| 5 | Right to erasure (DELETE /me + partner purge) | 🔴 RED — not built |
| 6 | Safety: block/report/unmatch + admin review | 🔴 RED — not built |
| 7 | `expire_stale_rooms` proven firing on pg_cron | 🔴 RED — scheduled (0007) but firing not yet verified on prod |
| 8 | Full live prod journey (register→delete) | 🔴 RED — blocked on #1 |
| 9 | Stage A privacy holds live | 🟢 GREEN (unchanged; re-confirm in journey) |

**Blockers to GO:** B2, B3, B5 unbuilt; B1/B4 client UIs unbuilt; live OTP path
needs the four founder actions; pg_cron firing unverified. **Do not launch.**

## Recommended next order (each fully testable/prod-provable except the live journey)
1. B3 erasure (PDPL, self-contained, prod-provable). 2. B5 safety + **verify
pg_cron**. 3. B2 consent. 4. The Flutter screens (phone/OTP, accept/reject,
delete, consent). 5. Founder actions → B6 live journey → re-verify privacy.
