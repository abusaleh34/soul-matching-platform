"""FastAPI entrypoint for the Soul Matching Platform backend (Render).

Run with:  uvicorn main:app  (working directory: backend/)
See Procfile / render.yaml. This is the single authoritative backend app;
the former SQLAlchemy app under app/main.py has been removed.
"""
import json
import logging
import os
import time

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware

from ai_service import analyze_profile
from app.api.deps import get_current_user
from app.api.match_endpoints import router as match_router
from app.db.database import supabase_client
from app.hook_signature import verify_standard_webhook
from app.phone import is_allowed_phone, normalize_phone
from app.rate_limit import RateLimiter
from app.sms import get_sms_provider
from models import WebhookPayload

# Surface application INFO logs (e.g. the analyze_profile privacy audit line
# that records the outbound payload keys) in the Render log stream.
logging.basicConfig(level=logging.INFO, format="%(levelname)s:%(name)s:%(message)s", force=True)

load_dotenv()

app = FastAPI(title="Soul Matching Platform API")

# --- CORS: restricted to the Vercel frontend + local dev origins ---------
# Configure FRONTEND_ORIGINS as a comma-separated list in the environment.
_default_origins = "http://localhost:3000,http://localhost:8080,http://127.0.0.1:3000"
_origins = [o.strip() for o in os.getenv("FRONTEND_ORIGINS", _default_origins).split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Webhook-Secret"],
)

app.include_router(match_router, prefix="/api", tags=["Matchmaking"])


@app.get("/")
def health_check():
    return {"status": "Soul Matching Platform API is running"}


@app.delete("/me")
async def delete_me(user=Depends(get_current_user)):
    """PDPL right to erasure: hard-delete the caller's account. Cascades remove
    their profile/messages/notifications; their rooms are marked closed and the
    deleter's slot nulled so the partner sees an ended conversation."""
    if supabase_client is None:
        raise HTTPException(status_code=500, detail="Database not configured")
    try:
        supabase_client.rpc("erase_user", {"p_uid": user.id}).execute()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Erasure failed: {exc}")
    return {"message": "Account erased", "id": user.id}


# Per-phone OTP-send limiter (SMS cost + brute-force). Per-IP limiting is done
# by Supabase Auth (the hook does not see the client IP) — see DEPLOYMENT.md.
_otp_rate_limiter = RateLimiter(max_attempts=5, window_seconds=900)


@app.post("/hooks/send-sms")
async def send_sms_hook(request: Request):
    """Supabase Send SMS Hook: deliver an OTP via the configured provider.

    Three guards before any SMS leaves: Standard Webhooks signature, the
    server-side phone allow-list (Saudi only — the client check is cosmetic),
    and a per-phone rate limit.
    """
    secret = os.getenv("SEND_SMS_HOOK_SECRET")
    body = (await request.body()).decode("utf-8")
    headers = {k.lower(): v for k, v in request.headers.items()}
    if not verify_standard_webhook(secret, headers, body):
        raise HTTPException(status_code=401, detail="Invalid or missing hook signature")

    try:
        payload = json.loads(body)
        raw_phone = payload["user"]["phone"]
        otp = payload["sms"]["otp"]
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=400, detail="Malformed Send SMS Hook payload")

    e164 = normalize_phone(raw_phone)
    if not e164 or not is_allowed_phone(e164):
        # Server guard — reject before spending an SMS. Client check is cosmetic.
        raise HTTPException(status_code=422, detail="الخدمة متاحة حاليًا للأرقام السعودية فقط.")

    if not _otp_rate_limiter.allow(e164, now=time.time()):
        raise HTTPException(status_code=429, detail="Too many OTP requests; please wait.")

    provider = get_sms_provider()
    message = f"رمز التحقق الخاص بك في تطبيق سول: {otp}"
    result = provider.send(e164, message)  # NullSmsProvider raises -> 500, fail loud
    if not result.success:
        raise HTTPException(status_code=502, detail="SMS delivery failed")
    return {}


@app.post("/webhook/analyze-profile")
async def analyze_profile_webhook(
    payload: WebhookPayload,
    x_webhook_secret: str | None = Header(default=None),
):
    """Supabase DB webhook: enrich a pending profile with a psychological
    analysis. This route uses the service role, so it is protected by a shared
    secret that MUST be configured (SUPABASE_WEBHOOK_SECRET) — see render.yaml.
    """
    expected = os.getenv("SUPABASE_WEBHOOK_SECRET")
    if not expected or x_webhook_secret != expected:
        # Secure by default: reject unless the secret is configured and matches.
        raise HTTPException(status_code=401, detail="Unauthorized webhook call")

    if supabase_client is None:
        raise HTTPException(status_code=500, detail="Supabase not configured")

    record = payload.record or {}
    if record.get("account_status") != "pending":
        return {"message": "Ignored: status is not pending"}

    profile_id = record.get("id")
    if not profile_id:
        raise HTTPException(status_code=400, detail="Profile ID missing in payload record")

    city = record.get("city")
    if not city or not str(city).strip():
        return {"message": "Ignored: a validated City field is required for analysis"}

    # Require a completed questionnaire. Do NOT fall back to the whole record:
    # that would forward identifying fields (first_name, city, …) to the LLM,
    # and would run a premature analysis before the questionnaire exists.
    questionnaire_answers = record.get("questionnaire_answers")
    if not questionnaire_answers:
        return {"message": "Ignored: questionnaire not yet completed"}

    try:
        psychological_profile = await analyze_profile(questionnaire_answers)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"AI generation failed: {exc}")

    try:
        supabase_client.table("profiles").update(
            {"psychological_profile": psychological_profile, "account_status": "active"}
        ).eq("id", profile_id).execute()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to update profile: {exc}")

    return {"message": "Profile analyzed and activated", "id": profile_id}
