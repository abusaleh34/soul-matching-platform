import os
from supabase import create_client, Client
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

if SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY:
    supabase_client: Client | None = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
else:
    # Safely degrade locally
    supabase_client = None
