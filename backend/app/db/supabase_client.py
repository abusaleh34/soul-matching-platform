import os
import asyncio
from dotenv import load_dotenv
from supabase import create_client, Client

# Load environment variables from backend/.env
load_dotenv()

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

# Initialize the robust Supabase Python Client
# Note: Using the service_role key gives this client admin privileges (bypassing RLS).
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

async def get_all_profiles():
    """
    Fetches all user profiles from the Supabase database.
    Since the standard python `supabase` package relies on synchronous HTTP requests,
    we wrap the execution in `asyncio.to_thread` to maintain FastAPI's asynchronous performance.
    """
    try:
        response = await asyncio.to_thread(
            lambda: supabase.table('profiles').select('*').execute()
        )
        return response.data
    except Exception as e:
        print(f"Failed to fetch profiles from Supabase: {e}")
        return []

async def get_profile(user_id: str):
    """Fetch a specific user profile by UUID."""
    try:
        response = await asyncio.to_thread(
            lambda: supabase.table('profiles').select('*').eq('id', user_id).execute()
        )
        return response.data[0] if response.data else None
    except Exception as e:
        print(f"Failed to fetch profile {user_id}: {e}")
        return None

async def get_potential_matches(user_id: str):
    """Fetch all profiles excluding the requesting user."""
    try:
        response = await asyncio.to_thread(
            lambda: supabase.table('profiles').select('*').neq('id', user_id).execute()
        )
        return response.data
    except Exception as e:
        print(f"Failed to fetch potential matches: {e}")
        return []
