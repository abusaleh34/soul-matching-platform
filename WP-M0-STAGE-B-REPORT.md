# WP-M0 — STAGE B REPORT (Soul-Launch Trust Layer)

**Updated:** 2026-07-14 · **Verdict: 🔴 NO-GO** — but only because the phone/OTP
path is blocked on founder SMS wiring. **Every no-SMS trust gate is now built,
reachable, and PROVEN end-to-end on prod through the real UI.**

The last report understated the screens as "presentation." You were right: an
unreachable delete/report/reject button is compliance on paper. This run built
the screens and **drove a real journey on the deployed app** (Playwright, with
Flutter semantics forced on), quoting DB evidence at each hop. It also surfaced a
real prod bug that unit/API tests missed.

---

## Live prod journey (real UI, real DB) — evidence per hop

Driven on `https://soul-matching-app.vercel.app` as a real anonymous user
(`df3c97bb…`), partner seeded for compatibility.

| Hop | UI action | Evidence |
|---|---|---|
| **Match decision (B4)** | app routed a `pending` match to the decision screen | screen showed **safe projection only** — "ليلى", "29 سنة • رحلة-اختبار", 98% — no questionnaire/psychological data |
| **Accept** | tapped قبول | `decide_match` → driver decision `accepted`, room stayed `pending`; UI showed "بانتظار قبول الطرف الآخر" |
| **Mutual accept → room** | partner accepted (DB) | driver screen **auto-advanced to the room** via realtime; countdown **23:59:38** (clock started only on mutual accept) |
| **Message** | typed + sent in the room | DB: `from_driver=true, content="السلام عليكم، سعدت بالتوافق"` |
| **Safety menu (B5)** | opened "خيارات الأمان" | menu exposed **إبلاغ / حظر / إلغاء المطابقة** — all reachable |
| **Report** | إبلاغ → متابعة | DB: report `by_driver=true, against_partner=true, reason="إساءة/تحرش", status=open` |
| **Partner deletion → degradation** | partner erased (DB `erase_user`) | driver's open room **degraded gracefully in the UI**: countdown `00:00:00`, counselor disabled, composer → **"انتهى وقت غرفة التركيز. المحادثة مغلقة الآن."** (no crash/dead-end). Screenshot: `frontend/stageb-partner-deletion-degradation.png` |
| **Delete account (B3)** | Settings → حذف الحساب → متابعة → حذف نهائي (double confirm) | after the CORS fix: DB **profile=0, auth=0, messages=0**; app signed out to the welcome screen |
| **Privacy (Stage A)** | fresh analysis fired for a profile named "طارق" | Render log: `analyze_profile outbound payload keys: ['q1', 'q9']` — **no `first_name`/`طارق`** |

## 🐞 Real bug caught by driving the UI (not by tests)
`DELETE /me` worked via direct API (401 proven earlier) but **failed silently in
the browser**: CORS `allow_methods` was `GET/POST/OPTIONS`, so the preflight for
DELETE was blocked. The delete button did nothing. Fixed (`5b2e9a1`): added
`DELETE` + a **preflight regression test** (`test_cors.py`) — unit/API tests skip
the browser preflight, which is exactly why it slipped through. Re-drove the
delete after the fix → account fully erased. This is the concrete proof of your
point: server enforcement + no reachable/working UI = not real.

## Backend/DB trust gates (from prior runs, all prod-proven)
- **Step 0 pg_cron:** `expire_stale_rooms` **fires live** — seeded an expired room; the 03:15:00 cron tick flipped it (451 runs).
- **B4** match consent, **B3** erasure, **B5** block/report/unmatch + admin-only reports, **B2** consent (`record_consent`), **B1** phone identity + Send SMS Hook (401 live). RLS never loosened; IDOR tested. Local DB suite green through `90_consent`; backend 49 passed.

---

## Loose ends — now sealed (UI-driven on prod, no inference)
- **Consent (blocking) — UI-proven:** drove the **real profile form** (no seeding) to the consent gate. Before أوافق: DB `consent_version=0, consented_at=null` — the user is stopped with no path past the screen. Tapped **أوافق** → DB `consent_version=1, consented_at` set → UI advanced to the oath. So an unconsented user cannot proceed, and `record_consent` fires from the actual button.
- **Block — UI-proven:** room safety menu → حظر → متابعة → DB `block_row_written=true, room_status=closed, excluded=true`.
- **Unmatch — UI-proven:** on a known-active room, safety menu → إلغاء المطابقة → متابعة → **that exact match** `room_status=closed` (deterministic, not inferred).

## Not done / honest gaps
| Item | Status |
|---|---|
| **Phone/OTP screen + live OTP journey** | Blocked on FOUNDER ACTIONS (below). The only remaining item. |

## FOUNDER ACTIONS (the only remaining launch blocker)
1. Choose a Saudi SMS provider + register a **CST Sender ID**.
2. Supabase → Auth → Providers → **Phone: enable**.
3. Supabase → Auth → Hooks → **Send SMS Hook**: URI
   `https://soul-matching-api.onrender.com/hooks/send-sms`; secret → Render
   `SEND_SMS_HOOK_SECRET`; `SMS_PROVIDER=logging` for the dry run.
4. Supabase → Auth → **Rate Limits**: per-IP OTP/SMS.

## Launch risk (WP-M2, not fixed)
The live landing page still promises "بصمة رقمية من 1500 بُعد نفسي" (1500-dimension
fingerprint) while matching is demographic-only. Confirmed on the live UI this run.

---

## SOFT-LAUNCH GO/NO-GO — 🔴 NO-GO (phone OTP only)

| # | Gate | State |
|---|---|---|
| 1 | Phone-OTP end-to-end | 🔴 blocked on founder SMS wiring |
| 2 | Match requires mutual accept | 🟢 **UI-proven on prod** |
| 3 | Reject/accept reachable | 🟢 **UI-proven** |
| 4 | Delete account reachable + works | 🟢 **UI-proven on prod** (CORS bug fixed) |
| 5 | Report/block/unmatch reachable | 🟢 **all three UI-proven on prod** (report + block + unmatch each driven, DB-verified) |
| 6 | Partner graceful degradation | 🟢 **UI-proven** (screenshot) |
| 7 | Consent captured + versioned | 🟢 **UI-proven** (blocking gate at v=0; أوافق → v=1 → advances) |
| 8 | `expire_stale_rooms` firing | 🟢 **proven live** |
| 9 | Stage A privacy holds live | 🟢 **re-proven this run** (`keys=['q1','q9']`, no name) |

**Why still NO-GO:** the founder ruled soft launch requires phone OTP, and that
path needs the four founder actions. **The no-SMS trust layer is now SEALED —
every gate except phone-OTP is UI-proven on prod** (consent blocking, accept/
reject, message, report, block, unmatch, partner-degradation, delete, privacy).
Gate 1 is the only remaining item; once SMS is wired I'll build the phone/OTP
screen and run the live OTP journey.
