"""FastAPI entrypoint for the Soul Matching Platform backend (Render).

Run with:  uvicorn main:app  (working directory: backend/)
See Procfile / render.yaml. This is the single authoritative backend app;
the former SQLAlchemy app under app/main.py has been removed.
"""
import os

from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from ai_service import analyze_profile
from app.api.match_endpoints import router as match_router
from app.db.database import supabase_client
from models import WebhookPayload

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
