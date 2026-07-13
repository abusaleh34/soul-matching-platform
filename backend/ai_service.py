"""Gemini integration via the supported `google-genai` SDK.

Replaces the deprecated `google-generativeai` package. A single fixed,
known-good model is used; the client is created per call from the
GEMINI_API_KEY environment variable.
"""
import asyncio
import json
import logging
import os

from google import genai

logger = logging.getLogger(__name__)

GEMINI_MODEL = "gemini-2.5-flash"

# Identifying fields that must NEVER be sent to the LLM (PDPL / PRD §6). The
# questionnaire itself is q1..q12 and carries no identity, but callers may hand
# us a fuller record — strip defensively so the guarantee holds regardless.
_PII_KEYS = frozenset({
    "first_name", "name", "full_name", "last_name",
    "id", "user_id", "national_id", "iqama",
    "phone", "email", "city", "country",
})


def get_client() -> genai.Client:
    return genai.Client(api_key=os.getenv("GEMINI_API_KEY"))


def _strip_pii(answers: dict) -> dict:
    """Drop any identifying keys before the payload can reach the LLM."""
    return {k: v for k, v in (answers or {}).items() if k not in _PII_KEYS}


async def analyze_profile(answers: dict) -> str:
    """Generate a deep psychological fingerprint from questionnaire answers."""
    safe = _strip_pii(answers)
    # Log the KEYS only (never values) — prod evidence that no name is sent.
    logger.info("analyze_profile outbound payload keys: %s", sorted(safe.keys()))
    answers_str = json.dumps(safe, ensure_ascii=False, indent=2) if safe else "{}"
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
