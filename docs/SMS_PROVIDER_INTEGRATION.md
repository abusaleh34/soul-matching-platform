# SMS Provider Integration

The phone-OTP delivery path is provider-agnostic. Supabase generates the OTP and
calls our **Send SMS Hook** (`POST /hooks/send-sms` on the Render backend); the
hook validates and dispatches through an `SmsProvider`. The concrete Saudi
provider is not chosen yet (pending CST Sender-ID registration), so plugging it
in is **one class + env vars** and touches nothing else.

## Architecture (already built)

```
client → supabase.auth.signInWithOtp({phone})
         → Supabase generates OTP, POSTs Standard-Webhooks-signed payload →
           Render  POST /hooks/send-sms
             1. verify Standard Webhooks signature (SEND_SMS_HOOK_SECRET)
             2. normalize + allow-list guard (app/phone.py — Saudi only)
             3. per-phone rate limit (app/rate_limit.py)
             4. get_sms_provider().send(e164, message)   ← the swap point
```

- `backend/app/sms/provider.py` — `SmsProvider.send(to_e164, message)`, plus
  `LoggingSmsProvider` (logs the OTP, sends nothing), `NullSmsProvider` (fails
  loud when unconfigured), `SaudiSmsProvider` (**stub**).
- `backend/app/sms/factory.py` — `get_sms_provider()` selects by `SMS_PROVIDER`.

## To wire a real provider (Taqnyat / Unifonic / any)

1. **Implement the send call** in `SaudiSmsProvider.send()` (`app/sms/provider.py`).
   Replace the `raise NotImplementedError` with the provider's HTTP call. Shape
   (fill from the provider's API docs):
   ```python
   resp = httpx.post(
       f"{PROVIDER_BASE_URL}/api/v1/messages",
       headers={"Authorization": f"Bearer {self.api_key}"},
       json={"recipient": to_e164, "sender": self.sender_id, "body": message},
       timeout=10,
   )
   resp.raise_for_status()
   return DeliveryResult(success=True, provider="saudi", detail=resp.json().get("message_id"))
   ```
   Add `httpx` to `requirements.txt` (already present as a dep of supabase).
2. **Delivery reports (optional but recommended):** register the provider's
   delivery-report webhook to a new endpoint (e.g. `POST /hooks/sms-status`) and
   reconcile message status. Not required for OTP to function.
3. **Set env vars** on Render: `SMS_PROVIDER=saudi`, `SMS_API_KEY=<key>`,
   `SMS_SENDER_ID=<registered CST sender id>`.
4. **No other code changes.** The hook, allow-list, rate limit, and phone
   normalization are provider-independent.

## FOUNDER ACTIONS (dashboard / external — do these to go live)

These are also tracked in `DEPLOYMENT.md` → Dashboard Settings Checklist.

1. **Choose a Saudi SMS provider** (Taqnyat, Unifonic, …) and open an account.
2. **Register a Sender ID with CST** (regulatory; required for A2P SMS in KSA).
3. **Supabase → Authentication → Providers → Phone: enable.** (Do NOT pick a
   built-in provider — we use the hook.)
4. **Supabase → Authentication → Hooks → Send SMS Hook: enable**, set URI to
   `https://soul-matching-api.onrender.com/hooks/send-sms`, copy the generated
   **hook secret** (`v1,whsec_…`) and set it on Render as `SEND_SMS_HOOK_SECRET`.
5. **Render env:** `SMS_PROVIDER` (`logging` for soft-launch dry-run, `saudi`
   once wired), `SMS_API_KEY`, `SMS_SENDER_ID`, `SEND_SMS_HOOK_SECRET`.

## Soft-launch dry run (before a real provider exists)

Set `SMS_PROVIDER=logging`. The OTP is written to the Render log stream
(`SMS[logging] to=+9665… message=…`), so a full journey can be driven end-to-end
by reading the code from the logs. `NullSmsProvider` (the default) hard-fails, so
a misconfigured prod never silently drops OTPs.

## Rate limiting & IP

- **Per-phone** limiting is enforced at the hook (`5 / 15 min`, tune in
  `main.py`). Note: process-local — move to a shared store (Redis/Postgres) when
  the backend is horizontally scaled.
- **Per-IP** limiting is **not** possible at the hook (Supabase, not the client,
  calls it — the client IP isn't in the payload). It is enforced by **Supabase
  Auth's built-in rate limits** (Dashboard → Authentication → Rate Limits);
  set the "OTP / SMS" limits there. Documented in the checklist.
