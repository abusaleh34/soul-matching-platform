"""Standard Webhooks (svix-style) signature verification for Supabase auth hooks.

signed = "{id}.{timestamp}.{body}"; sig = base64(hmac_sha256(key, signed)),
where key = base64decode(secret without the 'whsec_' prefix). The
`webhook-signature` header is a space-separated list of `v1,<sig>` entries.
"""
import base64
import hashlib
import hmac


def verify_standard_webhook(secret: str | None, headers: dict, body: str) -> bool:
    if not secret:
        return False
    try:
        msg_id = headers.get("webhook-id")
        ts = headers.get("webhook-timestamp")
        sig_header = headers.get("webhook-signature")
        if not (msg_id and ts and sig_header):
            return False

        raw_secret = secret.split("_", 1)[1] if secret.startswith("whsec_") else secret
        key = base64.b64decode(raw_secret)
        signed = f"{msg_id}.{ts}.{body}".encode()
        expected = base64.b64encode(hmac.new(key, signed, hashlib.sha256).digest()).decode()

        for part in sig_header.split(" "):
            _, _, sig = part.partition(",")
            if sig and hmac.compare_digest(sig, expected):
                return True
        return False
    except Exception:
        return False
