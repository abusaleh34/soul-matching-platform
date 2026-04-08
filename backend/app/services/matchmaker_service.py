import json
import logging
from datetime import datetime, timedelta
from supabase import Client
import google.generativeai as genai

# Import from the root package service wrapper securely
from ai_service import get_working_model

logger = logging.getLogger(__name__)

async def run_matchmaking_cycle(supabase: Client):
    # Fetch active pool natively ignoring 'matched' occupied users and raw 'pending' queues
    response = supabase.table('profiles').select(
        'id, gender, age, psychological_profile, account_status, city'
    ).eq('account_status', 'active').execute()
    
    users = response.data
    
    if not users or len(users) < 2:
        return {"message": "Not enough active users for matchmaking at this time."}

    males = [u for u in users if u.get('gender') == 'ذكر']
    females = [u for u in users if u.get('gender') == 'أنثى']
    
    matches_created = 0
    
    # Synchronous pairing loop executing across the opposing structures safely
    for male in males:
        for female in females:
            male_age = male.get('age')
            female_age = female.get('age')
            
            male_city = male.get('city')
            female_city = female.get('city')
            
            if male_age is None or female_age is None:
                continue
                
            # HARD FILTER 1: Strict Geo-Isolation
            if not male_city or not female_city or male_city != female_city:
                continue
                
            # HARD FILTER 2: Age difference <= 10 years strict isolation
            if abs(male_age - female_age) <= 10:
                is_match, reasoning, match_percentage = await evaluate_match(male, female)
                
                if is_match:
                    create_focus_room(supabase, male['id'], female['id'], match_percentage, reasoning)
                    matches_created += 1
                    
                    # Map their accounts to 'matched' locking out concurrency injections immediately
                    supabase.table('profiles').update({'account_status': 'matched'}).eq('id', male['id']).execute()
                    supabase.table('profiles').update({'account_status': 'matched'}).eq('id', female['id']).execute()
                    
                    females.remove(female)
                    break # Secure internal break
                    
    return {"message": "Matchmaking cycle completed successfully.", "focus_rooms_created": matches_created}

async def evaluate_match(user1, user2):
    model_name = get_working_model()
    model = genai.GenerativeModel(model_name)
    
    prompt = f"""
    You are an elite psychological relationship matchmaker working securely in a 24-hour focus room concept.
    Evaluate the raw compatibility of these two individuals strictly derived from their psychological profiles.
    
    User A (Male, Age {user1.get('age')}):
    {user1.get('psychological_profile')}
    
    User B (Female, Age {user2.get('age')}):
    {user2.get('psychological_profile')}
    
    Algorithmically assess a match percentage, and output a concise Arabic explanation detailing exactly why their personalities harmonize safely or friction potentially arises.
    Return EXACTLY in this parsed JSON object structure:
    {{"match_percentage": 85, "reasoning": "سبب التوافق هنا بوضوح..."}}
    """
    
    try:
        response = await model.generate_content_async(
            prompt,
            generation_config=genai.types.GenerationConfig(
                response_mime_type="application/json",
            ),
        )
        data = json.loads(response.text)
        match_perc = data.get("match_percentage", 0)
        reasoning = data.get("reasoning", "لم يتم توليد سبب.")
        
        # Determine internal matching threshold 
        return match_perc >= 80, reasoning, match_perc
    except Exception as e:
        logger.error(f"Failed to evaluate AI System Inference (بصيرة النظام) mapping: {e}")
        return False, f"Evaluation execution failed natively: {str(e)}", 0

def create_focus_room(supabase: Client, user1_id: str, user2_id: str, match_percentage: int, reasoning: str):
    match_data = {
        'user1_id': user1_id,
        'user2_id': user2_id,
        'match_percentage': match_percentage,
        'ai_reasoning': reasoning,
        'room_status': 'active',
        'user1_wants_extension': False,
        'user2_wants_extension': False,
        'extension_count': 0
    }
    supabase.table('matches').insert(match_data).execute()
