"""A4 regression (PDPL / PRD §6): the counselor prompt sent to Gemini must
contain NO profile name — the LLM receives psychological text and neutral role
labels only, never a real identity."""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

USER_TOK = "user-token"
USER_ID = "00000000-0000-0000-0000-0000000000u1"
PARTNER_ID = "00000000-0000-0000-0000-0000000000p1"
MATCH_ID = "00000000-0000-0000-0000-0000000000m1"

NAME1 = "آدم"
NAME2 = "حواء"


def _future():
    return (datetime.now(timezone.utc) + timedelta(hours=5)).isoformat()


def _store():
    return {
        "profiles": [
            {"id": USER_ID, "is_admin": False, "account_status": "matched",
             "psychological_profile": "شخصية هادئة تميل إلى التروي", "first_name": NAME1},
            {"id": PARTNER_ID, "is_admin": False, "account_status": "matched",
             "psychological_profile": "شخصية اجتماعية متعاونة", "first_name": NAME2},
        ],
        "matches": [
            {"id": MATCH_ID, "user1_id": USER_ID, "user2_id": PARTNER_ID,
             "room_status": "active", "expires_at": _future(), "match_percentage": 97},
        ],
    }


def _tokens():
    return {USER_TOK: USER_ID}


def test_counselor_prompt_contains_no_profile_name(make_client, monkeypatch):
    captured = {}

    class _FakeModels:
        def generate_content_stream(self, model, contents):
            captured["contents"] = contents
            return iter([SimpleNamespace(text="نصيحة")])

    class _FakeClient:
        models = _FakeModels()

    from app.api import match_endpoints
    monkeypatch.setattr(match_endpoints, "get_client", lambda: _FakeClient())

    client, _ = make_client(store=_store(), tokens=_tokens())
    r = client.post(
        f"/api/post-marriage-counselor/{MATCH_ID}",
        headers={"Authorization": f"Bearer {USER_TOK}"},
    )
    assert r.status_code == 200

    prompt = captured["contents"]
    assert NAME1 not in prompt, "profile name leaked into the LLM prompt"
    assert NAME2 not in prompt, "profile name leaked into the LLM prompt"
    # neutral role labels are used instead of names
    assert "الطرف الأول" in prompt and "الطرف الثاني" in prompt
    # the psychological text is still present (advice remains personalised)
    assert "التروي" in prompt and "اجتماعية" in prompt
