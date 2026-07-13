"""Standard Webhooks signature verification — Supabase signs Send-SMS-Hook
calls this way. An unauthenticated hook would let anyone trigger SMS sends."""
import base64
import hashlib
import hmac

from app.hook_signature import verify_standard_webhook

SECRET = "whsec_" + base64.b64encode(b"my-super-secret-key-0123456789ab").decode()


def _sign(secret: str, msg_id: str, ts: str, body: str) -> str:
    key = base64.b64decode(secret.split("_", 1)[1])
    signed = f"{msg_id}.{ts}.{body}".encode()
    sig = base64.b64encode(hmac.new(key, signed, hashlib.sha256).digest()).decode()
    return f"v1,{sig}"


BODY = '{"user":{"phone":"966500000001"},"sms":{"otp":"123456"}}'


def test_valid_signature_accepted():
    hdrs = {
        "webhook-id": "msg_1",
        "webhook-timestamp": "1700000000",
        "webhook-signature": _sign(SECRET, "msg_1", "1700000000", BODY),
    }
    assert verify_standard_webhook(SECRET, hdrs, BODY) is True


def test_tampered_body_rejected():
    hdrs = {
        "webhook-id": "msg_1",
        "webhook-timestamp": "1700000000",
        "webhook-signature": _sign(SECRET, "msg_1", "1700000000", BODY),
    }
    tampered = BODY.replace("123456", "000000")
    assert verify_standard_webhook(SECRET, hdrs, tampered) is False


def test_wrong_secret_rejected():
    hdrs = {
        "webhook-id": "m",
        "webhook-timestamp": "1",
        "webhook-signature": _sign(SECRET, "m", "1", BODY),
    }
    other = "whsec_" + base64.b64encode(b"different-key-different-key-01234").decode()
    assert verify_standard_webhook(other, hdrs, BODY) is False


def test_missing_headers_rejected():
    assert verify_standard_webhook(SECRET, {}, BODY) is False
