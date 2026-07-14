"""DELETE /me — authenticated right-to-erasure endpoint."""
USER_TOK = "user-token"
USER_ID = "00000000-0000-0000-0000-0000000000u1"


def _store():
    return {"profiles": [{"id": USER_ID, "is_admin": False, "account_status": "active"}]}


def test_delete_me_requires_token(make_client):
    client, _ = make_client(store=_store(), tokens={USER_TOK: USER_ID})
    assert client.delete("/me").status_code == 401


def test_delete_me_erases_authenticated_user(make_client):
    client, _ = make_client(store=_store(), tokens={USER_TOK: USER_ID}, rpc_result=None)
    r = client.delete("/me", headers={"Authorization": f"Bearer {USER_TOK}"})
    assert r.status_code == 200
    assert r.json()["id"] == USER_ID
