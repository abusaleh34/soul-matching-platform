from fastapi import APIRouter, HTTPException
from app.db.database import supabase_client
from app.services.matchmaker_service import run_matchmaking_cycle

router = APIRouter()

@router.post("/trigger-matchmaking")
async def trigger_matchmaking():
    """
    Manually invokes crossing all active pool users across the system generating bounded matching 24h rooms organically.
    """
    if not supabase_client:
        raise HTTPException(status_code=500, detail="Database connectivity dropped internally")
        
    try:
        result = await run_matchmaking_cycle(supabase_client)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
