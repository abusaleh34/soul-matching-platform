import google.generativeai as genai
import json
from fastapi import HTTPException

def get_working_model():
    # Iterate through available models for this specific API key
    for m in genai.list_models():
        if 'generateContent' in m.supported_generation_methods:
            return m.name
    # Fallback if the list is somehow empty
    return "gemini-1.5-pro"

async def analyze_profile(answers: dict) -> str:
    """
    Analyzes user questionnaire answers and generates a deep psychological fingerprint.
    """
    model_name = get_working_model()
    model = genai.GenerativeModel(model_name)
    
    # Properly encode the dictionary into a JSON string to preserve Arabic characters
    answers_str = json.dumps(answers, ensure_ascii=False, indent=2) if answers else "{}"
    
    prompt = (
        "أنت خبير نفسي في العلاقات. بناءً على هذه الإجابات من استبيان توافق، "
        "اكتب تحليلاً نفسياً عميقاً من فقرتين عن شخصية هذا الفرد وأسلوبه في العلاقات. "
        f"الإجابات:\n{answers_str}"
    )
    
    try:
        # Generate the sophisticated psychological profile asynchronously
        response = await model.generate_content_async(prompt)
        return response.text
    except Exception as e:
        print(f"Gemini API Error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Gemini AI generation failed: {str(e)}")
