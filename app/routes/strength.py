"""
Strength logging routes.

Library is read-only (seeded from app/data/strength_exercises.json on startup).
Sessions are append-only — there's no edit endpoint in v2; relog if needed.
"""

from datetime import date as date_t, datetime
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.strength_exercise import StrengthExercise
from app.models.strength_session import StrengthSession
from app.models.strength_set import StrengthSet
from app.models.user import User
from app.services import strength_service
from app.services.auth_service import get_current_user

router = APIRouter(prefix="/api/strength", tags=["strength"])


# ── Library ────────────────────────────────────────────────────────────────

class ExerciseDTO(BaseModel):
    id: UUID
    name: str
    category: str
    equipment: str
    youtube_demo_url: Optional[str] = None
    default_set_count: int
    default_rep_range: str


@router.get("/library")
async def get_library(
    category: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    rows = await strength_service.list_library(db, category=category)
    items = [
        ExerciseDTO(
            id=r.id,
            name=r.name,
            category=r.category,
            equipment=r.equipment,
            youtube_demo_url=r.youtube_demo_url,
            default_set_count=r.default_set_count,
            default_rep_range=r.default_rep_range,
        ).model_dump()
        for r in rows
    ]
    return {"items": items}


# ── Logging ────────────────────────────────────────────────────────────────

class QuickLogRequest(BaseModel):
    date: Optional[date_t] = None
    planned_workout_id: Optional[UUID] = None
    perceived_effort: Optional[int] = Field(default=None, ge=1, le=10)
    notes: Optional[str] = Field(default=None, max_length=2000)


class SessionResponse(BaseModel):
    id: UUID
    date: date_t
    quick_logged: bool


@router.post("/log-quick", response_model=SessionResponse)
async def log_quick(
    body: QuickLogRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> SessionResponse:
    today = body.date or datetime.utcnow().date()
    row = await strength_service.log_quick_session(
        db, current_user,
        date=today,
        planned_workout_id=body.planned_workout_id,
        perceived_effort=body.perceived_effort,
        notes=body.notes,
    )
    return SessionResponse(id=row.id, date=row.date, quick_logged=row.quick_logged)


class SetInputDTO(BaseModel):
    exercise_id: UUID
    set_number: int = Field(..., ge=1, le=20)
    reps: int = Field(..., ge=1, le=100)
    weight_kg: Optional[float] = Field(default=None, ge=0, le=500)
    rpe: Optional[int] = Field(default=None, ge=1, le=10)


class DetailedLogRequest(BaseModel):
    date: Optional[date_t] = None
    planned_workout_id: Optional[UUID] = None
    duration_minutes: Optional[int] = Field(default=None, ge=1, le=300)
    notes: Optional[str] = Field(default=None, max_length=500)
    sets: list[SetInputDTO]


@router.post("/log-detailed", response_model=SessionResponse)
async def log_detailed(
    body: DetailedLogRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> SessionResponse:
    today = body.date or datetime.utcnow().date()
    sets = [
        {
            "exercise_id": s.exercise_id,
            "set_number": s.set_number,
            "reps": s.reps,
            "weight_kg": s.weight_kg,
            "rpe": s.rpe,
        }
        for s in body.sets
    ]
    row = await strength_service.log_detailed_session(
        db, current_user,
        date=today,
        sets=sets,
        duration_minutes=body.duration_minutes,
        notes=body.notes,
        planned_workout_id=body.planned_workout_id,
    )
    return SessionResponse(id=row.id, date=row.date, quick_logged=row.quick_logged)


# ── Progression + history ──────────────────────────────────────────────────

@router.get("/progression")
async def progression(
    exercise_id: UUID,
    limit: int = 10,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    if limit > 30:
        limit = 30
    items = await strength_service.compute_progression(
        db, current_user.id, exercise_id, limit=limit,
    )
    return {"items": items}


@router.get("/sessions")
async def list_sessions(
    days: int = 30,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    if days > 180:
        days = 180
    from datetime import timedelta
    cutoff = datetime.utcnow().date() - timedelta(days=days)
    result = await db.execute(
        select(StrengthSession).where(
            StrengthSession.user_id == current_user.id,
            StrengthSession.date >= cutoff,
        ).order_by(desc(StrengthSession.date))
    )
    rows = list(result.scalars().all())
    return {
        "items": [
            {
                "id": str(r.id),
                "date": r.date.isoformat(),
                "quick_logged": r.quick_logged,
                "perceived_effort": r.perceived_effort,
                "duration_minutes": r.duration_minutes,
                "notes": r.notes,
            }
            for r in rows
        ]
    }


class LastSetDTO(BaseModel):
    reps: int
    weight_kg: Optional[float] = None
    rpe: Optional[int] = None


@router.get("/last-set", response_model=Optional[LastSetDTO])
async def last_set(
    exercise_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Optional[LastSetDTO]:
    row = await strength_service.get_last_set_for_exercise(db, current_user.id, exercise_id)
    if row is None:
        return None
    return LastSetDTO(
        reps=row.reps,
        weight_kg=float(row.weight_kg) if row.weight_kg is not None else None,
        rpe=row.rpe,
    )
