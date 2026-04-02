import uuid
import random
import os
import json
from dotenv import load_dotenv
from google import genai

# Load environment variables manually for this context
load_dotenv()
from typing import List
from ..db.supabase_client import get_profile, get_potential_matches
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from ..db.models import User, Response, Match
from ..schemas.match import MatchResult
from google.genai import types 

# Configure Gemini
api_key = os.getenv("GEMINI_API_KEY")

async def generate_embeddings(responses: List[Response]) -> List[float]:
    """
    Mocks the vector generation from an LLM API.
    Averaging all responses could be one strategy, but here we just return a random 1536-d vector.
    """
    # In reality, you'd call OpenAI embeddings or sentence-transformers API here
    return [random.uniform(-1.0, 1.0) for _ in range(1536)]




async def generate_match_analysis(user1: User, user2: User, user1_responses: List[Response], user2_responses: List[Response]) -> MatchResult:
    """
    Uses Gemini API to evaluate compatibility based on actual questionnaire data.
    """
    
    # تحويل الإجابات إلى نصوص مقروءة للذكاء الاصطناعي
    user1_data_str = str(user1_responses)
    user2_data_str = str(user2_responses)

    prompt = f"""
    أنت مستشار أسري خبير في الثقافة العربية. قم بتحليل إجابات المستخدم الأول والمستخدم الثاني بدقة واحترافية.
    ركز على الفلسفة المالية، حل النزاعات، وأسلوب الحياة. 
    
    إليك إجابات المستخدم الأول (ID: {user1.id}):
    {user1_data_str}

    إليك إجابات المستخدم الثاني (ID: {user2.id}):
    {user2_data_str}

    **تعليمات صارمة للمخرجات:**
    - حقل (potential_frictions): يجب أن يكون دقيقاً جداً ومستخرجاً من الإجابات أعلاه. لا تستخدم أبداً عبارات عامة مثل "تحتاج إلى نقاش". اذكر نقطة الخلاف المحددة بالاسم (مثال: "تباين في الرغبة بمكان السكن" أو "اختلاف في أسلوب الإدارة المالية"). إذا كانت الإجابات متطابقة تماماً، اكتب: ["لا توجد تحديات جوهرية واضحة"].
    - حقل (poetic_summary): يجب أن يكون باللغة العربية البليغة ويلخص سبب توافقهما بشكل ملهم.

    Expected JSON Schema:
    {{
      "compatibility_score": 85,
      "strengths": ["string", "string"],
      "potential_frictions": ["string"],
      "poetic_summary": "string"
    }}
    """
    
    try:
        if not api_key:
            raise ValueError("GEMINI_API_KEY is not set.")
            
        client = genai.Client(api_key=api_key)
        
        # استخدام وضع JSON النقي لضمان عدم وجود نصوص زائدة (Markdown)
        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
            )
        )
        
        # لم نعد بحاجة لتنظيف النص، لأنه سيأتي JSON جاهز ومضمون
        parsed_json = json.loads(response.text)
        
        return MatchResult(
            compatibility_score=int(parsed_json.get("compatibility_score", 60)),
            strengths=list(parsed_json.get("strengths", [])),
            potential_frictions=list(parsed_json.get("potential_frictions", [])),
            poetic_summary=str(parsed_json.get("poetic_summary", "لم يتمكن المستشار من صياغة الخلاصة."))
        )
    except Exception as e:
        print(f"LLM API Error: {e}")
        # Fallback to mock result if LLM fails
        return MatchResult(
            compatibility_score=random.randint(60, 99),
            strengths=["التوافق في الأهداف العامة"],
            potential_frictions=["اختلاف بسيط في تفاصيل الاستبيان"],
            poetic_summary="حدث خطأ في قراءة أرواحكما، يرجى المحاولة لاحقاً."
        )

async def match_users(user_id: uuid.UUID, db: AsyncSession) -> MatchResult:
    # 1. Fetch current user
    user = await db.scalar(select(User).where(User.id == user_id))
    if not user or not user.profile_vector:
        # User not found or vector not generated
        raise ValueError("User not found or psychological profile vector not generated.")

    # 2. Fetch top 1 most compatible user using cosine distance (<=>)
    # Exclude the user themselves, and make sure to only get users with a vector
    stmt = select(User).where(User.id != user_id, User.profile_vector != None).order_by(User.profile_vector.cosine_distance(user.profile_vector)).limit(1)
    matched_user = await db.scalar(stmt)
    
    if not matched_user:
        raise ValueError("No matching users found in the database.")
    
    # 3. Load responses for both users
    user_responses = (await db.scalars(select(Response).where(Response.user_id == user_id))).all()
    matched_responses = (await db.scalars(select(Response).where(Response.user_id == matched_user.id))).all()
    
    # 4. Construct prompt and get LLM analysis Result
    match_result = await generate_match_analysis(user, matched_user, list(user_responses), list(matched_responses))
    
    # 5. Save match to DB
    new_match = Match(
        user1_id=user.id,
        user2_id=matched_user.id,
        compatibility_score=match_result.compatibility_score,
        strengths=match_result.strengths,
        potential_frictions=match_result.potential_frictions,
        poetic_summary=match_result.poetic_summary
    )
    db.add(new_match)
    await db.commit()
    await db.refresh(new_match)
    
    return match_result

async def calculate_match_score(user_id: str) -> dict:
    """
    Phase 17 Core Logic: Directly reads questionnaire JSONB sets from Supabase Cloud 
    and bridges them securely through Gemini-2.5-Flash RAG evaluations.
    """
    # 1. Fetch cloud profiles directly
    target_user = await get_profile(user_id)
    if not target_user:
        return {"error": "Target user not found in the Cloud Database."}

    matches = await get_potential_matches(user_id)
    if not matches:
        return {"error": "No potential matches found."}

    # Extract target answers safely bypassing empty dict defaults.
    target_answers = target_user.get('questionnaire_answers', {})
    
    # 2. Extract potential match. For simplicity right now, testing against first match natively.
    match_user = matches[0]
    match_answers = match_user.get('questionnaire_answers', {})

    prompt = f"""
    You are an Expert Family Counselor in Arab culture. 
    Analyze User A's questionnaire answers: {json.dumps(target_answers, ensure_ascii=False)}
    Analyze User B's questionnaire answers: {json.dumps(match_answers, ensure_ascii=False)}
    Focus on financial philosophy, conflict resolution, and lifestyle. Do not focus on superficial traits.
    
    For 'challenges', NEVER use vague or generalized phrases. You MUST explicitly state the exact point of disagreement based on their questionnaire answers (e.g., 'Difference in desire to have children', 'Conflicting views on financial management'). Be direct, precise, and concise in Arabic.
    
    Return your analysis STRICTLY in the following JSON schema. Do not include markdown formatting or backticks around the JSON.
    The `quote` must be in elegant Arabic explaining why their souls match.

    Expected JSON Schema:
    {{
      "score": 85,
      "strengths": ["string", "string"],
      "challenges": ["string", "string"],
      "quote": "string"
    }}
    """

    try:
        if not api_key:
            raise ValueError("GEMINI_API_KEY is not set.")
            
        client = genai.Client(api_key=api_key)
        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=prompt
        )
        response_text = response.text.strip()
        
        # Strip potential markdown formatting dynamically
        if response_text.startswith("```json"):
            response_text = response_text[7:]
        if response_text.startswith("```"):
            response_text = response_text[3:]
        if response_text.endswith("```"):
            response_text = response_text[:-3]

        return json.loads(response_text.strip())
        
    except Exception as e:
        print(f"GenAI Synthesis Error: {e}")
        return {
            "score": 75,
            "strengths": ["التوافق العام", "النجاح في الأساسيات"],
            "challenges": ["تحتاج بعض النقاط الجوهرية إلى نقاش"],
            "quote": "الرحلة المشتركة تتطلب حواراً هادئاً مستمراً."
        }
