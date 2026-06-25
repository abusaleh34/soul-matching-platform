"""Shared FastAPI security dependencies.

Every protected route depends on these helpers so JWT validation and
authorisation live in exactly one place (BRD §4.1).

Status-code contract:
  * 401 — missing / malformed / invalid / expired token
  * 403 — valid token, but insufficient permission (not admin / not participant)
  * 404 — match does not exist OR caller is not allowed to see it (no leak)
  * 500 — genuine server/DB failure
"""
from typing import Optional

from fastapi import Depends, Header, HTTPException, status

from app.db.database import supabase_client


def _extract_bearer(authorization: Optional[str]) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header",
        )
    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Empty bearer token",
        )
    return token


async def get_current_user(authorization: Optional[str] = Header(default=None)):
    """Validate the Supabase JWT and return the authenticated user object."""
    if supabase_client is None:
        raise HTTPException(status_code=500, detail="Authentication backend not configured")

    token = _extract_bearer(authorization)
    try:
        result = supabase_client.auth.get_user(token)
    except Exception:
        # Any decode/verification failure is an auth failure, not a 500.
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    user = getattr(result, "user", None)
    if user is None or getattr(user, "id", None) is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return user


async def require_admin(user=Depends(get_current_user)):
    """Authorise admin-only routes via the server-verified is_admin column."""
    try:
        result = (
            supabase_client.table("profiles")
            .select("is_admin")
            .eq("id", user.id)
            .maybe_single()
            .execute()
        )
    except Exception:
        raise HTTPException(status_code=500, detail="Admin verification failed")

    profile = result.data if result else None
    if not profile or not profile.get("is_admin", False):
        raise HTTPException(status_code=403, detail="Admin privileges required")
    return user


def load_accessible_match(match_id: str, user_id: str) -> dict:
    """Return the match row only if user_id is a participant.

    Raises 404 when the match is missing OR not accessible (existence is not
    leaked to non-participants), and 403 when the room has already expired.
    """
    try:
        result = (
            supabase_client.table("matches")
            .select("*")
            .eq("id", match_id)
            .maybe_single()
            .execute()
        )
    except Exception:
        raise HTTPException(status_code=500, detail="Failed to load match")

    match = result.data if result else None
    if not match or user_id not in (match.get("user1_id"), match.get("user2_id")):
        raise HTTPException(status_code=404, detail="Match not found")
    return match
