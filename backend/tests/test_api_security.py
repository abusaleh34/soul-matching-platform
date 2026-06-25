"""Route security tests (BRD §4.1). Verifies the 401/403/404 contract for the
admin, matchmaking and counselor routes, plus webhook protection and route
registration."""
from datetime import datetime, timedelta, timezone

ADMIN_TOK = "admin-token"
USER_TOK = "user-token"
OUTSIDER_TOK = "outsider-token"

ADMIN_ID = "00000000-0000-0000-0000-0000000000a1"
USER_ID = "00000000-0000-0000-0000-0000000000u1"
PARTNER_ID = "00000000-0000-0000-0000-0000000000p1"
OUTSIDER_ID = "00000000-0000-0000-0000-0000000000o1"
MATCH_ID = "00000000-0000-0000-0000-0000000000m1"


def _future():
    return (datetime.now(timezone.utc) + timedelta(hours=5)).isoformat()


def _past():
    return (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()


def _store(expires_at):
    return {
        "profiles": [
            {"id": ADMIN_ID, "is_admin": True, "account_status": "active"},
            {"id": USER_ID, "is_admin": False, "account_status": "matched",
             "psychological_profile": "هادئ", "first_name": "آدم"},
            {"id": PARTNER_ID, "is_admin": False, "account_status": "matched",
             "psychological_profile": "متعاون", "first_name": "حواء"},
        ],
        "matches": [
            {"id": MATCH_ID, "user1_id": USER_ID, "user2_id": PARTNER_ID,
             "room_status": "active", "expires_at": expires_at, "match_percentage": 97},
        ],
    }


def _tokens():
    return {ADMIN_TOK: ADMIN_ID, USER_TOK: USER_ID, OUTSIDER_TOK: OUTSIDER_ID}


# ---------------------------------------------------------------- admin stats
def test_admin_stats_requires_token(make_client):
    client, _ = make_client(store=_store(_future()), tokens=_tokens())
    assert client.get("/api/admin/stats").status_code == 401


def test_admin_stats_forbidden_for_non_admin(make_client):
    client, _ = make_client(store=_store(_future()), tokens=_tokens())
    r = client.get("/api/admin/stats", headers={"Authorization": f"Bearer {USER_TOK}"})
    assert r.status_code == 403


def test_admin_stats_ok_for_admin(make_client):
    client, _ = make_client(store=_store(_future()), tokens=_tokens())
    r = client.get("/api/admin/stats", headers={"Authorization": f"Bearer {ADMIN_TOK}"})
    assert r.status_code == 200
    body = r.json()
    assert body["total_users"] == 3
    assert body["active_rooms"] == 1            # active + not expired
    assert body["average_compatibility"] == 97.0


def test_admin_stats_active_rooms_excludes_expired(make_client):
    client, _ = make_client(store=_store(_past()), tokens=_tokens())
    r = client.get("/api/admin/stats", headers={"Authorization": f"Bearer {ADMIN_TOK}"})
    assert r.json()["active_rooms"] == 0        # expired room not counted


# ----------------------------------------------------------- trigger matchmaking
def test_trigger_requires_token(make_client):
    client, _ = make_client(store=_store(_future()), tokens=_tokens())
    assert client.post("/api/trigger-matchmaking").status_code == 401


def test_trigger_forbidden_for_non_admin(make_client):
    client, _ = make_client(store=_store(_future()), tokens=_tokens())
    r = client.post("/api/trigger-matchmaking", headers={"Authorization": f"Bearer {USER_TOK}"})
    assert r.status_code == 403


def test_trigger_ok_for_admin_calls_sweep(make_client):
    client, _ = make_client(store=_store(_future()), tokens=_tokens(), rpc_result=2)
    r = client.post("/api/trigger-matchmaking", headers={"Authorization": f"Bearer {ADMIN_TOK}"})
    assert r.status_code == 200
    assert r.json()["focus_rooms_created"] == 2


# ----------------------------------------------------------------- counselor
def test_counselor_requires_token(make_client):
    client, _ = make_client(store=_store(_future()), tokens=_tokens())
    assert client.post(f"/api/post-marriage-counselor/{MATCH_ID}").status_code == 401


def test_counselor_404_for_non_participant(make_client):
    client, _ = make_client(store=_store(_future()), tokens=_tokens())
    r = client.post(f"/api/post-marriage-counselor/{MATCH_ID}",
                    headers={"Authorization": f"Bearer {OUTSIDER_TOK}"})
    assert r.status_code == 404               # existence not leaked


def test_counselor_403_when_expired(make_client):
    client, _ = make_client(store=_store(_past()), tokens=_tokens())
    r = client.post(f"/api/post-marriage-counselor/{MATCH_ID}",
                    headers={"Authorization": f"Bearer {USER_TOK}"})
    assert r.status_code == 403


def test_counselor_participant_active_streams(make_client, monkeypatch):
    client, _ = make_client(store=_store(_future()), tokens=_tokens())

    from types import SimpleNamespace

    class _FakeModels:
        def generate_content_stream(self, model, contents):
            return iter([SimpleNamespace(text="نصيحة "), SimpleNamespace(text="ذهبية")])

    class _FakeClient:
        models = _FakeModels()

    from app.api import match_endpoints
    monkeypatch.setattr(match_endpoints, "get_client", lambda: _FakeClient())

    r = client.post(f"/api/post-marriage-counselor/{MATCH_ID}",
                    headers={"Authorization": f"Bearer {USER_TOK}"})
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/plain")
    assert "نصيحة" in r.text and "ذهبية" in r.text  # streamed chunks concatenated


# ------------------------------------------------------------------- webhook
def test_webhook_rejected_without_secret(make_client):
    client, _ = make_client(store=_store(_future()), tokens=_tokens(), webhook_secret="s3cret")
    r = client.post("/webhook/analyze-profile",
                    json={"type": "INSERT", "table": "profiles", "record": {"id": USER_ID}})
    assert r.status_code == 401


def test_webhook_rejected_with_wrong_secret(make_client):
    client, _ = make_client(store=_store(_future()), tokens=_tokens(), webhook_secret="s3cret")
    r = client.post("/webhook/analyze-profile",
                    headers={"X-Webhook-Secret": "wrong"},
                    json={"type": "INSERT", "table": "profiles", "record": {"id": USER_ID}})
    assert r.status_code == 401


# --------------------------------------------------------------- route boot
def test_expected_routes_registered(make_client):
    client, _ = make_client(store=_store(_future()), tokens=_tokens())
    paths = {r.path for r in client.app.routes}
    assert {"/", "/webhook/analyze-profile", "/api/admin/stats",
            "/api/trigger-matchmaking", "/api/post-marriage-counselor/{match_id}"} <= paths
