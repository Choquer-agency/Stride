"""
Wellness check-in routes — submit, today, trends, history.
Submit fires the wellness_concern_check pipeline as a background task.
"""

import asyncio
from datetime import date as date_t, datetime
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.models.wellness_checkin import (
    ENTRY_MANUAL, ENTRY_MORNING, ENTRY_POST_RUN, ENTRY_PRE_RUN,
)
from app.services import wellness_service
from app.services.auth_service import get_current_user
from app.services.wellness_concern_check import run_wellness_concern_check

router = APIRouter(prefix="/api/wellness", tags=["wellness"])


_VALID_ENTRY_METHODS = {ENTRY_MORNING, ENTRY_PRE_RUN, ENTRY_POST_RUN, ENTRY_MANUAL}


# ── Submit ─────────────────────────────────────────────────────────────────

class WellnessCheckinRequest(BaseModel):
    entry_method: str = Field(..., description="morning | pre_run | post_run | manual")
    sleep_quality: Optional[int] = Field(None, ge=1, le=5)
    soreness: Optional[int] = Field(None, ge=1, le=5)
    motivation: Optional[int] = Field(None, ge=1, le=5)
    stress: Optional[int] = Field(None, ge=1, le=5)
    energy: Optional[int] = Field(None, ge=1, le=5)
    soreness_areas: Optional[list[str]] = None
    notes: Optional[str] = Field(None, max_length=2000)


class WellnessCheckinResponse(BaseModel):
    id: UUID
    entry_method: str
    date: date_t
    is_concerning: bool
    is_serious: bool


@router.post("/checkin", response_model=WellnessCheckinResponse)
async def submit_checkin(
    body: WellnessCheckinRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WellnessCheckinResponse:
    if body.entry_method not in _VALID_ENTRY_METHODS:
        raise HTTPException(status_code=400, detail=f"entry_method must be one of {sorted(_VALID_ENTRY_METHODS)}")

    row = await wellness_service.submit_checkin(
        db, current_user,
        entry_method=body.entry_method,
        sleep_quality=body.sleep_quality,
        soreness=body.soreness,
        motivation=body.motivation,
        stress=body.stress,
        energy=body.energy,
        soreness_areas=body.soreness_areas,
        notes=body.notes,
    )
    is_concerning = wellness_service.is_concerning(row)
    is_serious = wellness_service.is_serious_concern(row) if is_concerning else False

    # Commit the checkin row before kicking off the concern check (it opens its own session)
    await db.commit()

    if is_concerning:
        asyncio.create_task(run_wellness_concern_check(current_user.id, row.id))

    return WellnessCheckinResponse(
        id=row.id,
        entry_method=row.entry_method,
        date=row.date,
        is_concerning=is_concerning,
        is_serious=is_serious,
    )


# ── Today ──────────────────────────────────────────────────────────────────

class WellnessTodayCheckinDTO(BaseModel):
    id: UUID
    entry_method: str
    sleep_quality: Optional[int] = None
    soreness: Optional[int] = None
    motivation: Optional[int] = None
    stress: Optional[int] = None
    energy: Optional[int] = None
    soreness_areas: list[str] = Field(default_factory=list)
    notes: Optional[str] = None
    submitted_at: datetime


class WellnessTodayResponse(BaseModel):
    morning: Optional[WellnessTodayCheckinDTO] = None
    pre_run: list[WellnessTodayCheckinDTO] = Field(default_factory=list)
    post_run: list[WellnessTodayCheckinDTO] = Field(default_factory=list)
    needs_morning: bool
    needs_pre_run: bool


def _to_dto(row) -> WellnessTodayCheckinDTO:
    return WellnessTodayCheckinDTO(
        id=row.id,
        entry_method=row.entry_method,
        sleep_quality=row.sleep_quality,
        soreness=row.soreness,
        motivation=row.motivation,
        stress=row.stress,
        energy=row.energy,
        soreness_areas=row.soreness_areas or [],
        notes=row.notes,
        submitted_at=row.submitted_at,
    )


@router.get("/today", response_model=WellnessTodayResponse)
async def get_today(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WellnessTodayResponse:
    today = await wellness_service.get_today(db, current_user.id)
    has_recent_pre_run = await wellness_service.has_recent_pre_run_entry(db, current_user.id, hours=4)
    return WellnessTodayResponse(
        morning=_to_dto(today["morning"]) if today["morning"] else None,
        pre_run=[_to_dto(r) for r in today["pre_run"]],
        post_run=[_to_dto(r) for r in today["post_run"]],
        needs_morning=today["morning"] is None,
        needs_pre_run=(today["morning"] is None and not has_recent_pre_run),
    )


# ── Trends ─────────────────────────────────────────────────────────────────

class WellnessTrendsResponse(BaseModel):
    window_days: int
    current: dict
    prior: dict
    deltas: dict
    frequent_soreness_areas: list[dict]
    any_pain_keyword_days: int


@router.get("/trends", response_model=WellnessTrendsResponse)
async def get_trends(
    window: int = 7,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WellnessTrendsResponse:
    if window not in (7, 28, 90):
        raise HTTPException(status_code=400, detail="window must be 7, 28, or 90")
    trends = await wellness_service.compute_trends(db, current_user.id, window_days=window)
    return WellnessTrendsResponse(**trends)


# ── History ────────────────────────────────────────────────────────────────

class WellnessHistoryResponse(BaseModel):
    items: list[WellnessTodayCheckinDTO]


@router.get("/history", response_model=WellnessHistoryResponse)
async def get_history(
    limit: int = 30,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WellnessHistoryResponse:
    if limit > 100:
        limit = 100
    rows = await wellness_service.get_history(db, current_user.id, limit=limit)
    return WellnessHistoryResponse(items=[_to_dto(r) for r in rows])
