from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from uuid import UUID


class ShoeCreateRequest(BaseModel):
    name: str
    is_default: bool = False


class ShoeUpdateRequest(BaseModel):
    name: Optional[str] = None
    is_default: Optional[bool] = None
    is_retired: Optional[bool] = None


class ShoeResponse(BaseModel):
    id: UUID
    name: str
    photo_url: Optional[str] = None
    is_default: bool
    total_distance_km: float
    is_retired: bool
    created_at: datetime

    model_config = {"from_attributes": True}
