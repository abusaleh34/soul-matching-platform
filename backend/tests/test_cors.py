"""Regression: the browser must be able to preflight DELETE /me. A missing
method in CORS silently blocks the request in the browser (unit/API tests that
skip the preflight don't catch it — this one does)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def test_cors_preflight_allows_delete():
    from fastapi.testclient import TestClient
    import main

    client = TestClient(main.app)
    r = client.options(
        "/me",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "DELETE",
        },
    )
    assert r.status_code == 200
    allow = r.headers.get("access-control-allow-methods", "")
    assert "DELETE" in allow, f"DELETE not allowed by CORS (got: {allow})"
