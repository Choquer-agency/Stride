"""
Device registration for push notifications.

iOS app calls /api/devices/register after didRegisterForRemoteNotificationsWithDeviceToken,
storing the hex APNs token on User.apns_device_token.
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.services.auth_service import get_current_user

router = APIRouter(prefix="/api/devices", tags=["devices"])


class DeviceRegisterRequest(BaseModel):
    token: str = Field(..., min_length=8, max_length=64)
    platform: str = Field(default="ios", pattern="^(ios|android)$")


class DeviceRegisterResponse(BaseModel):
    ok: bool
    token_changed: bool


@router.post("/register", response_model=DeviceRegisterResponse)
async def register_device(
    body: DeviceRegisterRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> DeviceRegisterResponse:
    if body.platform != "ios":
        raise HTTPException(status_code=400, detail="Only iOS push tokens supported in v2.")

    changed = current_user.apns_device_token != body.token
    if changed:
        current_user.apns_device_token = body.token
        db.add(current_user)
        await db.flush()

    return DeviceRegisterResponse(ok=True, token_changed=changed)


@router.post("/unregister")
async def unregister_device(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    if current_user.apns_device_token:
        current_user.apns_device_token = None
        db.add(current_user)
        await db.flush()
    return {"ok": True}
