"""Full profile-analysis webhook path (the hop that broke in prod).

Proves end-to-end at the backend boundary:
  * no PII (first_name) is ever placed in the Gemini prompt,
  * a payload without a completed questionnaire is IGNORED (never forwarded to
    Gemini, so the whole record — incl. first_name — cannot leak),
  * a payload WITH a questionnaire is analysed and the profile activated.
"""
from types import SimpleNamespace

WEBHOOK_SECRET = "s3cret-test"
PID = "65e4c3af-dedd-4643-a277-587e7162f369"
NAME = "احمد"


def _record(with_questionnaire: bool):
    r = {
        "id": PID,
        "account_status": "pending",
        "city": "الرياض",
        "first_name": NAME,
    }
    if with_questionnaire:
        r["questionnaire_answers"] = {
            "q1": "أقضي عطلة نهاية الأسبوع في القراءة",
            "q9": "الإخلاص هو الالتزام الكامل تجاه الشريك",
        }
    else:
        r["questionnaire_answers"] = None
    return r


def _install_capturing_gemini(monkeypatch):
    """Patch ai_service.get_client to capture the outbound prompt."""
    captured = {"calls": 0, "prompt": None}

    class _FakeModels:
        def generate_content(self, model, contents):
            captured["calls"] += 1
            captured["prompt"] = contents
            return SimpleNamespace(text="تحليل نفسي عميق من فقرتين.")

    class _FakeClient:
        models = _FakeModels()

    import ai_service
    monkeypatch.setattr(ai_service, "get_client", lambda: _FakeClient())
    return captured


def test_analyze_profile_strips_pii_before_gemini(monkeypatch):
    """Unit: analyze_profile must never place first_name in the prompt."""
    captured = _install_capturing_gemini(monkeypatch)
    import asyncio
    import ai_service

    asyncio.run(ai_service.analyze_profile({"first_name": NAME, "q1": "أحب القراءة"}))

    assert captured["calls"] == 1
    assert NAME not in captured["prompt"], "first_name leaked into the Gemini prompt"
    assert "first_name" not in captured["prompt"]
    assert "القراءة" in captured["prompt"], "questionnaire content should still be present"


def test_webhook_ignored_when_questionnaire_missing(make_client, monkeypatch):
    """No completed questionnaire => IGNORE. The whole record (incl. first_name)
    must NOT be forwarded to Gemini."""
    captured = _install_capturing_gemini(monkeypatch)
    store = {"profiles": [_record(with_questionnaire=False)]}
    client, _ = make_client(store=store, webhook_secret=WEBHOOK_SECRET)

    r = client.post(
        "/webhook/analyze-profile",
        headers={"X-Webhook-Secret": WEBHOOK_SECRET},
        json={"type": "UPDATE", "table": "profiles", "record": _record(False)},
    )

    assert r.status_code == 200
    assert captured["calls"] == 0, "Gemini was called with a record that has no questionnaire (PII leak risk)"
    assert "Ignored" in r.json().get("message", "")


def test_webhook_analyzes_and_activates_without_name(make_client, monkeypatch):
    """Completed questionnaire => analyse, activate, and no name in the prompt."""
    captured = _install_capturing_gemini(monkeypatch)
    store = {"profiles": [_record(with_questionnaire=True)]}
    client, _ = make_client(store=store, webhook_secret=WEBHOOK_SECRET)

    r = client.post(
        "/webhook/analyze-profile",
        headers={"X-Webhook-Secret": WEBHOOK_SECRET},
        json={"type": "UPDATE", "table": "profiles", "record": _record(True)},
    )

    assert r.status_code == 200
    assert captured["calls"] == 1
    assert NAME not in captured["prompt"], "first_name leaked into the Gemini prompt"
    assert "الإخلاص" in captured["prompt"], "questionnaire content should be sent"
    assert r.json().get("message") == "Profile analyzed and activated"
