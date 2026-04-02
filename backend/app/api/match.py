import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from ..db.database import get_db
from ..schemas.match import MatchResult
from ..services.ai_service import match_users

router = APIRouter()

@router.post("/match/{user_id}", response_model=MatchResult)
async def create_match(user_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    """
    Triggers the matchmaking pipeline:
    1. Finds the most semantically similar user using pgvector.
    2. Uses an Expert LLM to evaluate compatibility based on responses.
    3. Saves the Match to the database.
    """
    try:
        match_result = await match_users(user_id, db)
        return match_result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail="Internal Matchmaking Error")
