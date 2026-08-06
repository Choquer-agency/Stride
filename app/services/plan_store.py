"""
Server-side training plan store.

Every plan generation, edit, and iOS backfill lands here as a new versioned
row; the latest content per user is flagged is_active. Server-side edits
(made directly against the DB or via future admin tooling) create a
source="server_edit" row — the iOS app compares the active row's updated_at
against the last version it applied and offers to pull the change.
"""

import logging
from datetime import date
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session
from app.models.training_plan import TrainingPlanRecord

logger = logging.getLogger(__name__)


async def get_active(db: AsyncSession, user_id: UUID) -> Optional[TrainingPlanRecord]:
    result = await db.execute(
        select(TrainingPlanRecord)
        .where(TrainingPlanRecord.user_id == user_id, TrainingPlanRecord.is_active.is_(True))
        .order_by(desc(TrainingPlanRecord.updated_at))
        .limit(1)
    )
    return result.scalar_one_or_none()


async def save_plan(
    db: AsyncSession,
    user_id: UUID,
    raw_plan_content: str,
    *,
    source: str,
    race_type: Optional[str] = None,
    race_date: Optional[date] = None,
    race_name: Optional[str] = None,
    goal_time: Optional[str] = None,
    custom_distance_km: Optional[float] = None,
    start_date: Optional[date] = None,
    fitness_level: Optional[str] = None,
    client_plan_id: Optional[UUID] = None,
    change_note: Optional[str] = None,
    athlete_profile: Optional[dict] = None,
) -> TrainingPlanRecord:
    """Insert a new active plan row, deactivating any prior active plan."""
    await db.execute(
        update(TrainingPlanRecord)
        .where(TrainingPlanRecord.user_id == user_id, TrainingPlanRecord.is_active.is_(True))
        .values(is_active=False)
    )
    record = TrainingPlanRecord(
        user_id=user_id,
        raw_plan_content=raw_plan_content,
        source=source,
        race_type=race_type,
        race_date=race_date,
        race_name=race_name,
        goal_time=goal_time,
        custom_distance_km=custom_distance_km,
        start_date=start_date,
        fitness_level=fitness_level,
        client_plan_id=client_plan_id,
        change_note=change_note,
        athlete_profile=athlete_profile,
    )
    db.add(record)
    await db.flush()
    return record


async def save_plan_own_session(user_id: UUID, raw_plan_content: str, **kwargs) -> None:
    """
    Fire-and-forget variant for SSE generators (which have no request-scoped
    session by the time streaming finishes). Failures are logged, never raised —
    plan persistence must not break the stream the athlete already received.
    """
    try:
        if not raw_plan_content.strip():
            return
        async with async_session() as db:
            await save_plan(db, user_id, raw_plan_content, **kwargs)
            await db.commit()
        logger.info("plan_store: saved %s plan for user=%s (%d chars)",
                    kwargs.get("source"), user_id, len(raw_plan_content))
    except Exception:
        logger.exception("plan_store: failed to save plan for user=%s", user_id)
