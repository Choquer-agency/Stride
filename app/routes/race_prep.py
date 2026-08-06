"""
Race-prep routes — logistics checklist + A/B/C goals.

The race-prep coaching review (run via cron) lives in /api/coach/run-race-prep-review
under the coaching router. This file handles the structured logistics checklist
+ goal endpoints.
"""

from datetime import datetime
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.race_logistics_checklist import RaceLogisticsChecklist
from app.models.user import User
from app.services import race_logistics_service
from app.services.auth_service import get_current_user

router = APIRouter(prefix="/api/race-prep", tags=["race_prep"])


class ChecklistDTO(BaseModel):
    id: UUID
    event_id: UUID
    generated_at: datetime
    items: list
    weather_forecast: Optional[dict] = None
    course_intel: Optional[dict] = None
    a_goal_seconds: Optional[int] = None
    b_goal_seconds: Optional[int] = None
    c_goal_seconds: Optional[int] = None


def _to_dto(row: RaceLogisticsChecklist) -> ChecklistDTO:
    return ChecklistDTO(
        id=row.id,
        event_id=row.event_id,
        generated_at=row.generated_at,
        items=row.items or [],
        weather_forecast=row.weather_forecast,
        course_intel=row.course_intel,
        a_goal_seconds=row.a_goal_seconds,
        b_goal_seconds=row.b_goal_seconds,
        c_goal_seconds=row.c_goal_seconds,
    )


@router.get("/checklist/{event_id}", response_model=ChecklistDTO)
async def get_checklist(
    event_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ChecklistDTO:
    result = await db.execute(
        select(RaceLogisticsChecklist).where(
            RaceLogisticsChecklist.user_id == current_user.id,
            RaceLogisticsChecklist.event_id == event_id,
        ).limit(1)
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="Logistics checklist not found")
    return _to_dto(row)


@router.post("/checklist/{event_id}/regenerate", response_model=ChecklistDTO)
async def regenerate_checklist(
    event_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ChecklistDTO:
    new_id = await race_logistics_service.generate_checklist(current_user.id, event_id)
    if new_id is None:
        raise HTTPException(status_code=500, detail="Failed to generate checklist")
    row = await db.get(RaceLogisticsChecklist, new_id)
    if row is None:
        raise HTTPException(status_code=500, detail="Checklist generated but not found")
    return _to_dto(row)


class ToggleItemRequest(BaseModel):
    completed: bool
    athlete_note: Optional[str] = Field(default=None, max_length=300)


@router.patch("/checklist/{event_id}/item/{item_index}", response_model=ChecklistDTO)
async def toggle_item(
    event_id: UUID,
    item_index: int,
    body: ToggleItemRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ChecklistDTO:
    result = await db.execute(
        select(RaceLogisticsChecklist).where(
            RaceLogisticsChecklist.user_id == current_user.id,
            RaceLogisticsChecklist.event_id == event_id,
        ).limit(1)
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="Checklist not found")
    items = list(row.items or [])
    if item_index < 0 or item_index >= len(items):
        raise HTTPException(status_code=400, detail="item_index out of range")
    item = dict(items[item_index] if isinstance(items[item_index], dict) else {})
    item["completed"] = body.completed
    if body.athlete_note is not None:
        item["athlete_note"] = body.athlete_note
    items[item_index] = item
    row.items = items
    db.add(row)
    await db.flush()
    return _to_dto(row)


class GoalsRequest(BaseModel):
    a_goal_seconds: Optional[int] = Field(default=None, ge=600, le=86400)
    b_goal_seconds: Optional[int] = Field(default=None, ge=600, le=86400)
    c_goal_seconds: Optional[int] = Field(default=None, ge=600, le=86400)


@router.post("/goals/{event_id}", response_model=ChecklistDTO)
async def update_goals(
    event_id: UUID,
    body: GoalsRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ChecklistDTO:
    result = await db.execute(
        select(RaceLogisticsChecklist).where(
            RaceLogisticsChecklist.user_id == current_user.id,
            RaceLogisticsChecklist.event_id == event_id,
        ).limit(1)
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="Checklist not found")
    if body.a_goal_seconds is not None:
        row.a_goal_seconds = body.a_goal_seconds
    if body.b_goal_seconds is not None:
        row.b_goal_seconds = body.b_goal_seconds
    if body.c_goal_seconds is not None:
        row.c_goal_seconds = body.c_goal_seconds
    db.add(row)
    await db.flush()
    return _to_dto(row)
