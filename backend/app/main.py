from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .db.database import engine, Base
from .db import models # Register models with Base
from .api import match
from .api import users

app = FastAPI(title="Smart Matching Platform API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(match.router, prefix="/api")
app.include_router(users.router, prefix="/api")

@app.on_event("startup")
async def startup():
    # In production, alembic migrations should be used instead of create_all
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

@app.get("/")
def read_root():
    return {"message": "Welcome to the Smart Matching Platform API"}

from .db.supabase_client import get_all_profiles

@app.get("/test-fetch")
async def test_fetch_supabase():
    """Temporary endpoint to verify backend access to Supabase profiles."""
    data = await get_all_profiles()
    return {
        "status": "success",
        "count": len(data) if data else 0,
        "profiles": data
    }

from .services.ai_service import calculate_match_score

@app.get("/match/{user_id}")
async def get_match_score(user_id: str):
    """
    Execute AI psychological match synthesis bridging the explicit user Profile UUID 
    with iterative potential matching targets natively.
    """
    result = await calculate_match_score(user_id)
    return result

import os
import uvicorn

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("app.main:app", host="0.0.0.0", port=port)
