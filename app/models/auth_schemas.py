from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from datetime import datetime
from uuid import UUID


# ── Request Models ───────────────────────────────────────────────────────────


class EmailRegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8)
    name: Optional[str] = None


class EmailLoginRequest(BaseModel):
    email: EmailStr
    password: str


class GoogleAuthRequest(BaseModel):
    id_token: str


class AppleAuthRequest(BaseModel):
    identity_token: str
    user_identifier: str
    full_name: Optional[str] = None
    email: Optional[str] = None


class ProfileUpdateRequest(BaseModel):
    name: Optional[str] = None
    date_of_birth: Optional[str] = None  # ISO 8601 date "YYYY-MM-DD"
    gender: Optional[str] = None
    height_cm: Optional[float] = None
    profile_photo_base64: Optional[str] = None
    leaderboard_opt_in: Optional[bool] = None
    display_name: Optional[str] = None


# ── Response Models ──────────────────────────────────────────────────────────


class UserResponse(BaseModel):
    id: UUID
    email: str
    name: Optional[str] = None
    auth_provider: str
    profile_photo_base64: Optional[str] = None
    date_of_birth: Optional[str] = None
    gender: Optional[str] = None
    height_cm: Optional[float] = None
    has_completed_profile: bool = False
    leaderboard_opt_in: bool = False
    display_name: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse
