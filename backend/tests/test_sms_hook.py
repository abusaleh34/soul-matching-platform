"""Send SMS Hook endpoint: signature, server allow-list guard, rate limit."""
import base64
import hashlib
import hmac
import json

import pytest
from fastapi.testclient import TestClient

SECRET = "whsec_" + base64.b64encode(b"hook-secret-hook-secret-01234567").decode()


def _signed(body: str, msg_id: str = "m1", ts: str = "1700000000") -> dict:
    key = base64.b64decode(SECRET.split("_", 1)[1])
    sig = base64.b64encode(
        hmac.new(key, f"{msg_id}.{ts}.{body}".encode(), hashlib.sha256).digest()
    ).decode()
    return {
        "webhook-id": msg_id,
        "webhook-timestamp": ts,
        "webhook-signature": f"v1,{sig}",
    }


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("SEND_SMS_HOOK_SECRET", SECRET)
    monkeypatch.setenv("SMS_PROVIDER", "logging")
    import main
    return TestClient(main.app)


def _body(phone: str, otp: str = "123456") -> str:
    return json.dumps({"user": {"phone": phone}, "sms": {"otp": otp}})


def test_saudi_number_delivered(client, caplog):
    body = _body("966512340000")
    import logging
    with caplog.at_level(logging.INFO):
        r = client.post("/hooks/send-sms", content=body, headers=_signed(body))
    assert r.status_code == 200
    assert any("123456" in rec.message for rec in caplog.records)  # logged by provider


def test_non_saudi_rejected_by_server_guard(client):
    body = _body("15551234567")
    r = client.post("/hooks/send-sms", content=body, headers=_signed(body))
    assert r.status_code == 422


def test_bad_signature_rejected(client):
    body = _body("966512340001")
    r = client.post("/hooks/send-sms", content=body,
                    headers={"webhook-id": "m", "webhook-timestamp": "1", "webhook-signature": "v1,deadbeef"})
    assert r.status_code == 401


def test_per_phone_rate_limit(client):
    phone = "966512349000"
    body = _body(phone)
    codes = [client.post("/hooks/send-sms", content=body, headers=_signed(body)).status_code
             for _ in range(6)]
    assert codes[:5] == [200, 200, 200, 200, 200]
    assert codes[5] == 429  # 6th within the window is rejected
