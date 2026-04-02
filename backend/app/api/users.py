import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from ..db.database import get_db
from ..db.models import User

router = APIRouter()

@router.get("/users/{user_id}/status")
async def get_user_status(user_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    """
    Returns the user's account status (pending, active, rejected).
    Crucial for Phase 9 Waiting Room logic enforcing friction before RAG Matching.
    """
    user = await db.scalar(select(User).where(User.id == user_id))
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    return {"status": user.account_status}
