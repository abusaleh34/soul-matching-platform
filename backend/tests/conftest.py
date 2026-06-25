"""Test fixtures: an in-memory fake Supabase client so the route security can
be tested without a live database or network."""
import os
import sys
from types import SimpleNamespace

import pytest

# Make the backend root importable (main.py, ai_service.py, app/ ...)
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class _Result:
    def __init__(self, data):
        self.data = data


class _Builder:
    def __init__(self, table, store):
        self._table = table
        self._store = store
        self._eq = {}
        self._single = False

    def select(self, *a, **k):
        return self

    def update(self, *a, **k):
        return self

    def insert(self, *a, **k):
        return self

    def eq(self, col, val):
        self._eq[col] = val
        return self

    def maybe_single(self):
        self._single = True
        return self

    def execute(self):
        rows = list(self._store.get(self._table, []))
        for col, val in self._eq.items():
            rows = [r for r in rows if r.get(col) == val]
        if self._single:
            return _Result(rows[0] if rows else None)
        return _Result(rows)


class _Auth:
    def __init__(self, tokens):
        self._tokens = tokens  # token -> user_id

    def get_user(self, token):
        uid = self._tokens.get(token)
        if not uid:
            raise Exception("invalid token")
        return SimpleNamespace(user=SimpleNamespace(id=uid))


class FakeSupabase:
    def __init__(self, store=None, tokens=None, rpc_result=0):
        self._store = store or {}
        self.auth = _Auth(tokens or {})
        self._rpc_result = rpc_result

    def table(self, name):
        return _Builder(name, self._store)

    def rpc(self, name, params=None):
        return SimpleNamespace(execute=lambda: _Result(self._rpc_result))


@pytest.fixture
def make_client():
    """Build a TestClient with the fake Supabase wired into every module."""
    from fastapi.testclient import TestClient

    import main
    from app.api import deps, match_endpoints

    def _factory(store=None, tokens=None, rpc_result=0, webhook_secret=None):
        fake = FakeSupabase(store=store, tokens=tokens, rpc_result=rpc_result)
        deps.supabase_client = fake
        match_endpoints.supabase_client = fake
        main.supabase_client = fake
        if webhook_secret is not None:
            os.environ["SUPABASE_WEBHOOK_SECRET"] = webhook_secret
        return TestClient(main.app), fake

    return _factory
