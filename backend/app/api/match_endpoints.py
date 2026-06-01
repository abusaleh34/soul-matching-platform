from fastapi import APIRouter, HTTPException, Header
from app.db.database import supabase_client
from app.services.matchmaker_service import run_matchmaking_cycle
import google.generativeai as genai
from ai_service import get_working_model

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

@router.post("/post-marriage-counselor/{match_id}")
async def post_marriage_counselor(match_id: str):
    """
    Generates tailored post-marriage counseling advice for a matched pair based on their psychological profiles.
    """
    if not supabase_client:
        raise HTTPException(status_code=500, detail="Database connectivity dropped internally")
        
    try:
        # 1. Fetch match record
        match_res = supabase_client.table('matches').select('*').eq('id', match_id).maybeSingle().execute()
        match_data = match_res.data
        if not match_data:
            raise HTTPException(status_code=404, detail="Match room not found")
            
        user1_id = match_data.get('user1_id')
        user2_id = match_data.get('user2_id')
        
        # 2. Fetch profiles
        u1_res = supabase_client.table('profiles').select('psychological_profile, gender, first_name').eq('id', user1_id).maybeSingle().execute()
        u2_res = supabase_client.table('profiles').select('psychological_profile, gender, first_name').eq('id', user2_id).maybeSingle().execute()
        
        u1_data = u1_res.data
        u2_data = u2_res.data
        
        if not u1_data or not u2_data:
            raise HTTPException(status_code=404, detail="One or both psychological profiles are missing")
            
        # 3. Formulate Prompt
        u1_profile = u1_data.get('psychological_profile') or "الملف الشخصي النفسي لم يتم تحليله بعد."
        u2_profile = u2_data.get('psychological_profile') or "الملف الشخصي النفسي لم يتم تحليله بعد."
        
        u1_name = u1_data.get('first_name') or "الطرف الأول"
        u2_name = u2_data.get('first_name') or "الطرف الثاني"
        
        model_name = get_working_model()
        model = genai.GenerativeModel(model_name)
        
        prompt = f"""
        أنت مستشار علاقات زوجية خبير وذكي للغاية، متخصص في الإرشاد الأسري والتوفيق بين الشخصيات بناءً على سماتها النفسية.
        أمامك الملفان النفسيان لشريكين مقبلين على الزواج أو متزوجين حديثاً.
        
        الشريك الأول ({u1_name}):
        {u1_profile}
        
        الشريك الثاني ({u2_name}):
        {u2_profile}
        
        يرجى تقديم نصيحة ذهبية مخصصة وعميقة باللغة العربية الفصحى الدافئة والمشجعة، تركز على:
        1. كيف يمكنهما التواصل بفعالية بناءً على نقاط التوافق بين شخصيتيهما.
        2. حلول عملية لتجنب الفجوات أو سوء الفهم المحتمل بناءً على الفروقات النفسية الظاهرة في ملفيهما.
        3. إرشادات لتعزيز الروابط الروحية والعاطفية بينهما في الحياة اليومية.
        
        تجنب النصائح العامة والمكررة، واجعل الرد مخصصاً تماماً لصفاتهما النفسية المذكورة.
        نسق الرد بشكل ممتاز مع استخدام فقرات ونقاط مريحة بصرياً للقراءة.
        """
        
        response = await model.generate_content_async(prompt)
        return {"advice": response.text}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate counseling advice: {str(e)}")

@router.get("/admin/stats")
async def get_admin_stats(authorization: str = Header(None)):
    """
    Secure endpoint returning overall stats, protected by Supabase JWT and profiles.is_admin checks.
    """
    if not supabase_client:
        raise HTTPException(status_code=500, detail="Database connectivity dropped internally")
        
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authorization header missing or invalid")
        
    token = authorization.split(" ")[1]
    
    # 1. Verify user using Supabase JWT
    try:
        user_response = supabase_client.auth.get_user(token)
        user_id = user_response.user.id
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Unauthorized: Invalid token: {str(e)}")
        
    # 2. Check if the user is an admin
    try:
        profile_res = supabase_client.table('profiles').select('is_admin').eq('id', user_id).maybeSingle().execute()
        profile = profile_res.data
        if not profile or not profile.get('is_admin', False):
            raise HTTPException(status_code=403, detail="Forbidden: Admin privileges required")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error during admin check: {str(e)}")
        
    # 3. Retrieve stats
    try:
        # Get profiles status counts
        profiles_res = supabase_client.table('profiles').select('account_status').execute()
        profiles = profiles_res.data or []
        
        total_users = len(profiles)
        pending_users = sum(1 for p in profiles if p.get('account_status') == 'pending')
        active_users = sum(1 for p in profiles if p.get('account_status') == 'active')
        matched_users = sum(1 for p in profiles if p.get('account_status') == 'matched')
        
        # Get matches
        matches_res = supabase_client.table('matches').select('match_percentage').execute()
        matches = matches_res.data or []
        
        total_matches = len(matches)
        
        # Calculate average compatibility
        if total_matches > 0:
            avg_compat = sum(m.get('match_percentage', 0) for m in matches) / total_matches
        else:
            avg_compat = 0.0
            
        return {
            "total_users": total_users,
            "pending_users": pending_users,
            "active_users": active_users,
            "matched_users": matched_users,
            "total_matches": total_matches,
            "average_compatibility": round(avg_compat, 1)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error during stats query: {str(e)}")

