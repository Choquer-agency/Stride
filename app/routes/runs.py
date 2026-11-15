from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func, or_, update
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
from app.services.run_webhook import queue_run_webhook

router = APIRouter(prefix="/api/runs", tags=["runs"])


@router.post("/sync", response_model=RunBatchSyncResponse)
async def sync_runs(
    request: RunBatchSyncRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Batch upload runs, preserving new metrics on older-client retries."""
    if not request.runs:
        return RunBatchSyncResponse(synced_count=0, already_existed=0, newly_unlocked=[])

    now = datetime.now(timezone.utc)
    synced_count = 0
    all_newly_unlocked = []

    for run_payload in request.runs:
        is_eligible = run_payload.data_source == "bluetooth_ftms"

        values = run_payload.model_dump(exclude_unset=True)
        values.pop("metrics_backfill_only", None)
        values.update(user_id=current_user.id, is_leaderboard_eligible=is_eligible, synced_at=now)
        inserted = (await db.execute(
            pg_insert(Run).values(**values).on_conflict_do_nothing(index_elements=["id"]).returning(Run.id)
        )).scalar_one_or_none() is not None
        if inserted:
            queue_run_webhook(db, run_payload.id, current_user.id, "run.completed")
        else:
            changes = {key: value for key, value in values.items()
                       if key not in {"id", "user_id", "synced_at"}}
            if run_payload.metrics_backfill_only:
                changes = {key: value for key, value in changes.items()
                           if key in {"metrics_json", "elevation_gain_m", "elevation_loss_m",
                                      "hr_samples_json", "km_splits_json"}}
            updated = None
            if changes:
                changed = or_(*(getattr(Run, key).is_distinct_from(value)
                                for key, value in changes.items()))
                updated = (await db.execute(update(Run).where(
                    Run.id == run_payload.id, Run.user_id == current_user.id, changed,
                ).values(**changes, synced_at=now).returning(Run.id))).scalar_one_or_none()
            if updated is not None:
                queue_run_webhook(db, run_payload.id, current_user.id, "run.updated")
            else:
                owner = await db.scalar(select(Run.user_id).where(Run.id == run_payload.id))
                if owner is not None and owner != current_user.id:
                    raise HTTPException(status_code=409, detail="Run ID belongs to another athlete")

        if inserted:
            synced_count += 1
            # Coach replies to athlete notes on fresh runs (chat thread + push)
            if (run_payload.notes or "").strip():
                import asyncio as _asyncio
                from app.services.run_note_reply_service import send_note_reply
                _asyncio.create_task(send_note_reply(current_user.id, run_payload.id))
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
