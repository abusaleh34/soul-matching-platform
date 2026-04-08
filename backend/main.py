import os
from fastapi import FastAPI, HTTPException
from dotenv import load_dotenv
from supabase import create_client, Client
import google.generativeai as genai

from models import WebhookPayload
from ai_service import analyze_profile
from app.db.database import supabase_client
from app.api.match_endpoints import router as match_router

load_dotenv()

# Initialize FastAPI app
app = FastAPI(title="AI Matchmaker Backend")

# Mount Routers Cleanly
app.include_router(match_router, prefix="/api", tags=["Matchmaking Cycle"])

# Initialize Google Gemini Configuration
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)
else:
    print("Warning: Gemini API Key is not set in the environment.")

@app.get("/")
def health_check():
    return {"status": "AI Matchmaker Backend is running"}

@app.post("/webhook/analyze-profile")
async def analyze_profile_webhook(payload: WebhookPayload):
    if not supabase_client:
        raise HTTPException(status_code=500, detail="Supabase not configured internally")
        
    # a. Check if account_status == 'pending'
    account_status = payload.record.get("account_status")
    if account_status != 'pending':
        return {"message": "Ignored: Status is not pending"}
        
    # b. Extract id, questionnaire answers, and strict city constraints
    profile_id = payload.record.get("id")
    if not profile_id:
        raise HTTPException(status_code=400, detail="Profile ID missing in payload record")
        
    city = payload.record.get("city")
    if not city or city.strip() == "":
        return {"message": "Ignored: Strict spatial constraints require a validated City field to trigger AI Analysis (بصيرة النظام)."}
        
    # We fallback to the entire record if questionnaire_answers aren't nested natively yet.
    questionnaire_answers = payload.record.get("questionnaire_answers") or payload.record
        
    # c. Await analyze_profile
    try:
        psychological_profile = await analyze_profile(questionnaire_answers)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"AI generation failed: {str(e)}")
        
    # d. Update profiles table where id == record['id']
    try:
        response = supabase_client.table('profiles').update({
            "psychological_profile": psychological_profile,
            "account_status": "active"
        }).eq("id", profile_id).execute()
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update profile to active: {str(e)}")
        
    # e. Return success message
    return {"message": "Profile successfully analyzed and activated", "id": profile_id}
