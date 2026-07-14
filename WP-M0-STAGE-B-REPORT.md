# WP-M0 — STAGE B REPORT (Soft-Launch Trust Layer)

**Updated:** 2026-07-14 · **Verdict: 🔴 NO-GO** (every backend/DB trust gate is
built and **prod-proven**; the **Flutter UI layer** and the **live OTP journey**
remain — the latter blocked on founder actions).

Every claim below is backed by quoted prod evidence. The security-, legal- and
ethics-critical enforcement all lives at the DB/backend layer (clients cannot
bypass RLS / SECURITY DEFINER RPCs), and **all of it is done and proven on the
Frankfurt prod project**. What is left is presentation (Flutter screens) and the
founder-gated live SMS path.

---

## Step 0 — pg_cron actually fires (you flagged it; proven, not assumed)
`expire_stale_rooms` (jobid 2, `*/15`, active): **451 successful runs**, and I
seeded an expired active room and let the **03:15:00 cron tick flip it** — it was
`active` at 03:14:57 and `expired` at 03:15:23, with `job_run_details` showing
`succeeded / "1 row"`. I did not touch it between. ✅ **PROVEN.**

## Backend / DB trust gates — DONE & prod-proven

| Sub-pkg | What shipped (DB/backend) | Prod proof |
|---|---|---|
| **B1** Phone OTP | provider abstraction (`Logging`/`Null`/`Saudi`-stub), allow-list (data), Send SMS Hook (sig + guard + rate limit), schema 0011 (phone UNIQUE, `verification_level`, DB allow-list wall, legacy migration) | hook **401** unsigned; `+1` rejected `23514`; احمد/منى → `legacy_unverified` |
| **B2** Consent | 0015: `consent_version`/`consented_at` + `record_consent` RPC (server-stamped, caller-only); `legal/consent_v1_ar.md` (DRAFT) | `record_consent(1)` → version=1, `consented_at` set |
| **B3** Erasure | 0013: `DELETE /me` + `erase_user` (matches→SET NULL so partner keeps a `closed` room; deleter's messages purged) | deleter profile/auth/messages=0, partner msg kept=1, room=closed, deleter dereferenced |
| **B4** Match consent | 0012: Hunter creates `pending` (no clock); `decide_match` SECURITY DEFINER; mutual-accept→active+clock; reject→closed+pool+exclusion | pending/no-clock; **IDOR blocked**; one-sided stays pending; mutual→active+clock |
| **B5** Safety | 0014: `blocks`/`reports` + RLS; `block_user`/`report_user`/`unmatch` RPCs; admin-only report view (not broadened RLS); hunter block-exclusion | block closes+excludes (no re-match); report **admin-only** (non-admin BLOCKED); **unmatch IDOR BLOCKED** |

Local DB suite **PASS≈41** (10→90 scenario files); backend **48 passed**; CI green
through the stack. Client-layer helpers TDD'd: `phone.dart` (8), `consent.dart`
(4), `message_send.dart` (4).

**Never loosened RLS.** Every cross-user action is a SECURITY DEFINER RPC that
derives identity from `auth.uid()`; admin report access is a function, not a
policy. IDOR is explicitly tested and prod-proven on `decide_match` and `unmatch`.

---

## Remaining (honest)

| Item | Status | Note |
|---|---|---|
| Flutter **phone/OTP** screen | ❌ not built | helper `phone.dart` done; screen wiring + `signInWithOtp`/`verifyOTP` remain |
| Flutter **accept/reject** screen | ❌ not built | `decide_match` + `get_partner_profile` exist; UI remains |
| Flutter **delete-account** flow | ❌ not built | `DELETE /me` live; UI (double-confirm) remains |
| Flutter **consent** screen + routing | ❌ not built | `needsConsent` gate done; screen remains |
| Flutter **block/report/unmatch** buttons | ❌ not built | RPCs live; UI remains |
| **Live OTP journey** (B6) | ❌ blocked | needs the founder actions below |
| Partner "انتهت المحادثة" on erasure/close | ⚠️ relies on existing closed-room banner | verify in the journey |

## FOUNDER ACTIONS (blocking the live journey; in DEPLOYMENT.md checklist)
1. Choose a Saudi SMS provider + register a **CST Sender ID**.
2. Supabase → Auth → Providers → **Phone: enable** (no built-in provider).
3. Supabase → Auth → Hooks → **Send SMS Hook**: enable, URI
   `https://soul-matching-api.onrender.com/hooks/send-sms`, copy secret → Render
   `SEND_SMS_HOOK_SECRET`. `SMS_PROVIDER=logging` for the dry run.
4. Supabase → Auth → **Rate Limits**: set per-IP OTP/SMS.

Once (2)+(3) are set I can drive the full live journey (OTP from Render logs) and
re-verify the Stage A privacy guarantee live.

## Privacy
Stage A guarantee (**`first_name` never reaches Gemini**) unchanged — `analyze_profile`
still strips PII, logs only payload keys. To be re-confirmed live in B6.

## Launch risk to flag (WP-M2, not fixed)
Landing page promises a **"1500-dimension psychological fingerprint"**; matching
is demographic-only (`99 - ageDiff`). Promise-vs-product gap — surfaced, not touched.

---

## SOFT-LAUNCH GO/NO-GO — 🔴 NO-GO

| # | Gate | State |
|---|---|---|
| 1 | Phone-OTP end-to-end on prod | 🟡 backend done & hook live; **client screen + founder wiring** missing |
| 2 | Saudi-only (client/server/DB) | 🟢 server+DB proven; client helper done (screen wiring pending) |
| 3 | Match requires mutual accept | 🟢 DB proven; accept/reject **UI** missing |
| 4 | Consent captured + versioned | 🟢 DB proven; consent **screen** missing |
| 5 | Right to erasure | 🟢 **proven on prod**; delete **UI** missing |
| 6 | Block / report / unmatch + admin review | 🟢 **proven on prod**; **UI buttons** missing |
| 7 | `expire_stale_rooms` firing on pg_cron | 🟢 **proven live** |
| 8 | Full live prod journey (register→delete) | 🔴 blocked on founder SMS/hook wiring |
| 9 | Stage A privacy holds live | 🟢 unchanged (re-confirm in journey) |

**Why still NO-GO:** no user can complete a journey without the Flutter screens,
and the live OTP path needs the four founder actions. **The legal/ethical gates
(erasure, block/report) that you required before any user enters now EXIST and
are prod-proven** — the remaining work is UI + the founder's SMS wiring.

## Next order
1. Founder actions (1–4) to unblock SMS. 2. Flutter screens (phone/OTP → consent
→ accept/reject → room block/report/unmatch → settings delete). 3. B6 live
journey + privacy re-verify. 4. Flip gates 1/3/4 to GREEN with journey evidence.
