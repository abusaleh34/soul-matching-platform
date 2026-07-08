"""Matchmaking, counselor and admin routes.

Security model (BRD §4.1):
  * /trigger-matchmaking         -> admin only; delegates to the DB Hunter sweep.
  * /post-marriage-counselor/... -> participant of that match only; blocked once
                                    the room has expired (no psych-data leak).
  * /admin/stats                 -> admin only.
The DB-side "Hunter" trigger is the authoritative matchmaker; this module never
runs matching in Python.
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse

from ai_service import GEMINI_MODEL, get_client
from app.api.deps import get_current_user, load_accessible_match, require_admin
from app.db.database import supabase_client

router = APIRouter()


def _require_db():
    if supabase_client is None:
        raise HTTPException(status_code=500, detail="Database connectivity is not configured")


@router.post("/trigger-matchmaking")
async def trigger_matchmaking(_admin=Depends(require_admin)):
    """Admin-only manual run of the database Hunter sweep (BRD §3.6)."""
    _require_db()
    try:
        result = supabase_client.rpc("run_hunter_sweep").execute()
        return {"focus_rooms_created": result.data if result else 0}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Matchmaking sweep failed: {exc}")


@router.post("/post-marriage-counselor/{match_id}")
async def post_marriage_counselor(match_id: str, user=Depends(get_current_user)):
    """Stream counseling advice — only for a participant of an active match.

    Returns a `text/plain` stream so the frontend can render the advice
    incrementally as Gemini produces it (BRD §3.5).
    """
    _require_db()

    # 404 if the match is missing or the caller is not a participant.
    match = load_accessible_match(match_id, user.id)

    # Block once the room has expired (BRD remediation §1.4).
    if match.get("room_status") != "active" or _is_expired(match.get("expires_at")):
        raise HTTPException(status_code=403, detail="This focus room has expired")

    try:
        u1 = (
            supabase_client.table("profiles")
            .select("psychological_profile, first_name")
            .eq("id", match.get("user1_id"))
            .maybe_single()
            .execute()
        )
        u2 = (
            supabase_client.table("profiles")
            .select("psychological_profile, first_name")
            .eq("id", match.get("user2_id"))
            .maybe_single()
            .execute()
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to load profiles: {exc}")

    u1_data = u1.data if u1 else None
    u2_data = u2.data if u2 else None
    if not u1_data or not u2_data:
        raise HTTPException(status_code=404, detail="One or both profiles are missing")

    u1_profile = u1_data.get("psychological_profile") or "الملف الشخصي النفسي لم يتم تحليله بعد."
    u2_profile = u2_data.get("psychological_profile") or "الملف الشخصي النفسي لم يتم تحليله بعد."
    u1_name = u1_data.get("first_name") or "الطرف الأول"
    u2_name = u2_data.get("first_name") or "الطرف الثاني"

    prompt = f"""
    أنت مستشار علاقات زوجية خبير وذكي للغاية، متخصص في الإرشاد الأسري والتوفيق بين الشخصيات بناءً على سماتها النفسية.
    أمامك الملفان النفسيان لشريكين مقبلين على الزواج أو متزوجين حديثاً.

    الشريك الأول ({u1_name}):
    {u1_profile}

    الشريك الثاني ({u2_name}):
    {u2_profile}

    يرجى تقديم نصيحة ذهبية مخصصة وعميقة باللغة العربية الفصحى الدافئة والمشجعة، تركز على:
    1. كيف يمكنهما التواصل بفعالية بناءً على نقاط التوافق بين شخصيتيهما.
    2. حلول عملية لتجنب الفجوات أو سوء الفهم المحتمل بناءً على الفروقات النفسية الظاهرة في ملفيهما.
    3. إرشادات لتعزيز الروابط الروحية والعاطفية بينهما في الحياة اليومية.

    تجنب النصائح العامة والمكررة، واجعل الرد مخصصاً تماماً لصفاتهما النفسية المذكورة.
    نسق الرد بشكل ممتاز مع استخدام فقرات ونقاط مريحة بصرياً للقراءة.
    """

    def generate():
        client = get_client()
        try:
            for chunk in client.models.generate_content_stream(model=GEMINI_MODEL, contents=prompt):
                text = getattr(chunk, "text", None)
                if text:
                    yield text
        except Exception as exc:  # surface generation errors inside the stream
            yield f"\n[تعذّر إكمال توليد النصيحة: {exc}]"

    return StreamingResponse(generate(), media_type="text/plain; charset=utf-8")


@router.get("/admin/stats")
async def get_admin_stats(_admin=Depends(require_admin)):
    """Admin-only platform metrics (BRD §3.6)."""
    _require_db()
    try:
        profiles = (supabase_client.table("profiles").select("account_status").execute().data) or []
        matches = (
            supabase_client.table("matches")
            .select("match_percentage, room_status, expires_at")
            .execute()
            .data
        ) or []
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Database error during stats query: {exc}")

    total_users = len(profiles)
    pending_users = sum(1 for p in profiles if p.get("account_status") == "pending")
    active_users = sum(1 for p in profiles if p.get("account_status") == "active")
    matched_users = sum(1 for p in profiles if p.get("account_status") == "matched")

    total_matches = len(matches)
    active_rooms = sum(
        1
        for m in matches
        if m.get("room_status") == "active" and not _is_expired(m.get("expires_at"))
    )
    avg_compat = (
        round(sum(m.get("match_percentage", 0) for m in matches) / total_matches, 1)
        if total_matches
        else 0.0
    )

    return {
        "total_users": total_users,
        "pending_users": pending_users,
        "active_users": active_users,
        "matched_users": matched_users,
        "total_matches": total_matches,
        "active_rooms": active_rooms,
        "average_compatibility": avg_compat,
    }


def _is_expired(expires_at) -> bool:
    """True when an ISO timestamp is in the past (treats missing as expired)."""
    if not expires_at:
        return True
    try:
        dt = datetime.fromisoformat(str(expires_at).replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt <= datetime.now(timezone.utc)
    except (ValueError, TypeError):
        return True
