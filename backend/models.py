from pydantic import BaseModel, Field
from typing import Optional, Dict, Any

class WebhookPayload(BaseModel):
    type: str
    table: str
    schema_name: Optional[str] = Field(default=None, alias='schema')
    record: Dict[str, Any]
    old_record: Optional[Dict[str, Any]] = None
