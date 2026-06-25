"""Gemini integration via the supported `google-genai` SDK.

Replaces the deprecated `google-generativeai` package. A single fixed,
known-good model is used; the client is created per call from the
GEMINI_API_KEY environment variable.
"""
import asyncio
import json
import os

from google import genai

GEMINI_MODEL = "gemini-2.5-flash"


def get_client() -> genai.Client:
    return genai.Client(api_key=os.getenv("GEMINI_API_KEY"))


async def analyze_profile(answers: dict) -> str:
    """Generate a deep psychological fingerprint from questionnaire answers."""
    answers_str = json.dumps(answers, ensure_ascii=False, indent=2) if answers else "{}"
    prompt = (
        "أنت خبير نفسي في العلاقات. بناءً على هذه الإجابات من استبيان توافق، "
        "اكتب تحليلاً نفسياً عميقاً من فقرتين عن شخصية هذا الفرد وأسلوبه في العلاقات. "
        f"الإجابات:\n{answers_str}"
    )
    client = get_client()
    # The SDK call is synchronous; run it off the event loop.
    response = await asyncio.to_thread(
        lambda: client.models.generate_content(model=GEMINI_MODEL, contents=prompt)
    )
    return response.text
