from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select, func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.models.run import Run
from app.models.community_schemas import (
    RunBatchSyncRequest,
    RunBatchSyncResponse,
    RunResponse,
)
from app.services.auth_service import get_current_user
from app.services.leaderboard_service import compute_personal_bests
from app.services.achievement_service import check_achievements_after_sync
from app.services.challenge_service import check_challenge_participation
from app.services.event_service import check_event_participation
from app.services import analytics
from app.services.social_service import log_activity
from app.services.shoe_service import add_mileage as shoe_add_mileage

router = APIRouter(prefix="/api/runs", tags=["runs"])


@router.post("/sync", response_model=RunBatchSyncResponse)
async def sync_runs(
    request: RunBatchSyncRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Batch upload runs. Uses ON CONFLICT DO NOTHING for dedup on run id."""
    if not request.runs:
        return RunBatchSyncResponse(synced_count=0, already_existed=0, newly_unlocked=[])

    now = datetime.now(timezone.utc)
    synced_count = 0
    all_newly_unlocked = []

    for run_payload in request.runs:
        is_eligible = run_payload.data_source == "bluetooth_ftms"

        stmt = pg_insert(Run).values(
            id=run_payload.id,
            user_id=current_user.id,
            completed_at=run_payload.completed_at,
            distance_km=run_payload.distance_km,
            duration_seconds=run_payload.duration_seconds,
            avg_pace_sec_per_km=run_payload.avg_pace_sec_per_km,
            km_splits_json=run_payload.km_splits_json,
            feedback_rating=run_payload.feedback_rating,
            notes=run_payload.notes,
            planned_workout_title=run_payload.planned_workout_title,
            planned_workout_type=run_payload.planned_workout_type,
            planned_distance_km=run_payload.planned_distance_km,
            completion_score=run_payload.completion_score,
            plan_name=run_payload.plan_name,
            week_number=run_payload.week_number,
            data_source=run_payload.data_source,
            treadmill_brand=run_payload.treadmill_brand,
            shoe_id=run_payload.shoe_id,
            is_leaderboard_eligible=is_eligible,
            synced_at=now,
        ).on_conflict_do_nothing(index_elements=["id"])

        result = await db.execute(stmt)
        if result.rowcount > 0:
            synced_count += 1
            # Compute personal bests for newly synced eligible runs
            await compute_personal_bests(
                db=db,
                user_id=current_user.id,
                run_id=run_payload.id,
                km_splits_json=run_payload.km_splits_json,
                completed_at=run_payload.completed_at,
                is_eligible=is_eligible,
            )
            # Check challenge participations
            await check_challenge_participation(
                db=db,
                user_id=current_user.id,
                run_id=run_payload.id,
                distance_km=run_payload.distance_km,
                km_splits_json=run_payload.km_splits_json,
                completed_at=run_payload.completed_at,
                is_eligible=is_eligible,
            )
            # Check event participations
            await check_event_participation(
                db=db,
                user_id=current_user.id,
                run_id=run_payload.id,
                distance_km=run_payload.distance_km,
                km_splits_json=run_payload.km_splits_json,
                completed_at=run_payload.completed_at,
                is_eligible=is_eligible,
            )
            # Increment shoe mileage
            if run_payload.shoe_id:
                await shoe_add_mileage(db, run_payload.shoe_id, current_user.id, run_payload.distance_km)
            # Log activity for feed
            await log_activity(
                db, current_user.id, "run", run_payload.id,
                {"distance_km": run_payload.distance_km, "duration_seconds": run_payload.duration_seconds},
            )
            # Check for newly unlocked achievements
            unlocked = await check_achievements_after_sync(
                db=db,
                user_id=current_user.id,
                run_id=run_payload.id,
                distance_km=run_payload.distance_km,
                completed_at=run_payload.completed_at,
            )
            all_newly_unlocked.extend(unlocked)

    already_existed = len(request.runs) - synced_count

    analytics.capture(
        str(current_user.id),
        "runs_synced",
        {"synced_count": synced_count, "already_existed": already_existed, "achievements_unlocked": len(all_newly_unlocked)},
    )

    return RunBatchSyncResponse(
        synced_count=synced_count,
        already_existed=already_existed,
        newly_unlocked=all_newly_unlocked,
    )


@router.get("", response_model=list[RunResponse])
async def get_runs(
    since: datetime | None = Query(None, description="Only return runs completed after this timestamp"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get the current user's synced runs, ordered by completed_at descending."""
    query = select(Run).where(Run.user_id == current_user.id)

    if since is not None:
        query = query.where(Run.completed_at > since)

    query = query.order_by(Run.completed_at.desc()).limit(limit).offset(offset)

    result = await db.execute(query)
    runs = result.scalars().all()
    return [RunResponse.model_validate(r) for r in runs]
