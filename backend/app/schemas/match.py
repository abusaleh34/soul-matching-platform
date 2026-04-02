from pydantic import BaseModel
from typing import List

class MatchResult(BaseModel):
    compatibility_score: int
    strengths: List[str]
    potential_frictions: List[str]
    poetic_summary: str
