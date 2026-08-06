"""
Plan adjustment service — propose / accept / reject / expire.

The actual plan structure lives in iOS SwiftData (TrainingPlan/Week/Workout) and
isn't mirrored to the backend in v2. So:
- propose() creates the PlanAdjustment row with structured_diff
- iOS fetches pending adjustments + renders AdjustmentReviewSheet
- On accept: iOS applies the diff client-side to its local plan, then calls
  /api/plan/accept-adjustment (which marks the row accepted server-side)
- On reject: iOS calls /api/plan/reject-adjustment with optional reason; we
  set per-flag-type cool-downs based on the trigger event's flags

Expiry rules (enforced by the hourly cron + the expire() helper):
- workout-level (single dated workout in affected_workout_dates): expires at
  workout start_time + 1h, so the proposal can't outlive its target
- block-level (multiple dates): 7 days from proposed_at
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.coaching_event import CoachingEvent, CoachingEventTriggerSource, CoachingEventType
from app.models.plan_adjustment import PlanAdjustment, PlanAdjustmentStatus
from app.models.user import User
from app.services import cooldown_service

logger = logging.getLogger(__name__)


# Default expiry windows
_WORKOUT_LEVEL_GRACE_HOURS = 1   # past workout start
_BLOCK_LEVEL_DAYS = 7


# ── Public API ─────────────────────────────────────────────────────────────

async def propose(
    db: AsyncSession,
    user: User,
    *,
    trigger_event_id: UUID,
    summary: str,
    structured_diff: dict,
    affected_workout_dates: Optional[list[str]] = None,
) -> PlanAdjustment:
    """
    Persist a new PROPOSED adjustment from a coaching event's <adjustment> JSON tag.
    Computes expires_at based on whether the diff is workout-level or block-level.
    """
    expires_at = _compute_expiry(affected_workout_dates)
    row = PlanAdjustment(
        user_id=user.id,
        training_plan_id=None,  # iOS-side plan, not on backend
        proposed_at=datetime.now(timezone.utc),
        expires_at=expires_at,
        status=PlanAdjustmentStatus.PROPOSED.value,
        trigger_event_id=trigger_event_id,
        summary_text=summary[:500] if summary else "",
        structured_diff=structured_diff or {},
        affected_workout_ids=None,  # iOS-resolved
    )
    db.add(row)
    await db.flush()

    # Audit row in coaching_events for the proposal itself
    audit = CoachingEvent(
        user_id=user.id,
        event_type=CoachingEventType.PLAN_ADJUSTMENT_PROPOSED.value,
        trigger_source=CoachingEventTriggerSource.MANUAL.value,
        flags_that_fired=[],
        notification_delivered=False,
        shadow_mode=True,
        context={
            "adjustment_id": str(row.id),
            "trigger_event_id": str(trigger_event_id),
            "summary": summary,
            "affected_dates": affected_workout_dates or [],
            "expires_at": expires_at.isoformat(),
        },
        idempotency_key=f"adj_proposed:{row.id}",
    )
    db.add(audit)
    await db.flush()

    logger.info(
        "Plan adjustment proposed: id=%s user=%s expires=%s summary=%r",
        row.id, user.id, expires_at.isoformat(), summary[:60],
    )
    return row


async def accept(
    db: AsyncSession,
    user: User,
    adjustment_id: UUID,
    *,
    applied_diff_actual: Optional[dict] = None,
) -> PlanAdjustment:
    """
    Mark an adjustment accepted. iOS has already applied the diff to its local
    TrainingPlan; we just persist the state and write an audit event.

    Pass `applied_diff_actual` when the iOS-applied diff differs from the proposal
    (e.g., the plan shifted between proposal and accept), so the audit trail
    reflects what was actually applied.
    """
    row = await _load_adjustment(db, user, adjustment_id)
    if row.status != PlanAdjustmentStatus.PROPOSED.value:
        raise ValueError(f"Cannot accept adjustment in status {row.status}")

    row.status = PlanAdjustmentStatus.ACCEPTED.value
    row.applied_at = datetime.now(timezone.utc)
    row.applied_diff_actual = applied_diff_actual or row.structured_diff
    db.add(row)

    audit = CoachingEvent(
        user_id=user.id,
        event_type=CoachingEventType.PLAN_ADJUSTMENT_ACCEPTED.value,
        trigger_source=CoachingEventTriggerSource.USER_ACTION.value,
        flags_that_fired=[],
        notification_delivered=False,
        shadow_mode=True,
        context={"adjustment_id": str(row.id), "trigger_event_id": str(row.trigger_event_id) if row.trigger_event_id else None},
        idempotency_key=f"adj_accepted:{row.id}",
    )
    db.add(audit)
    await db.flush()

    logger.info("Plan adjustment accepted: id=%s user=%s", row.id, user.id)
    return row


async def reject(
    db: AsyncSession,
    user: User,
    adjustment_id: UUID,
    *,
    reason: Optional[str] = None,
) -> PlanAdjustment:
    """
    Mark rejected, set per-flag cool-downs based on the trigger event's flags so
    the coach won't propose the same kind of change for 72 hours.
    """
    row = await _load_adjustment(db, user, adjustment_id)
    if row.status != PlanAdjustmentStatus.PROPOSED.value:
        raise ValueError(f"Cannot reject adjustment in status {row.status}")

    row.status = PlanAdjustmentStatus.REJECTED.value
    row.rejection_reason = reason
    db.add(row)

    audit = CoachingEvent(
        user_id=user.id,
        event_type=CoachingEventType.PLAN_ADJUSTMENT_REJECTED.value,
        trigger_source=CoachingEventTriggerSource.USER_ACTION.value,
        flags_that_fired=[],
        notification_delivered=False,
        shadow_mode=True,
        context={"adjustment_id": str(row.id), "reason": reason or "", "trigger_event_id": str(row.trigger_event_id) if row.trigger_event_id else None},
        idempotency_key=f"adj_rejected:{row.id}",
    )
    db.add(audit)

    # Apply 72h cool-down to each flag type that triggered the rejected adjustment
    await _apply_cooldowns_for_trigger(db, user, row, audit_id=audit.id if audit.id else None)
    await db.flush()

    logger.info("Plan adjustment rejected: id=%s user=%s reason=%r", row.id, user.id, reason)
    return row


async def expire_pending(db: AsyncSession) -> dict:
    """
    Sweep PROPOSED rows whose expires_at has passed → EXPIRED.
    Apply the same per-flag cool-downs as a rejection (athlete didn't act =
    they don't want it).
    Returns counts for the cron audit log.
    """
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(PlanAdjustment).where(
            PlanAdjustment.status == PlanAdjustmentStatus.PROPOSED.value,
            PlanAdjustment.expires_at <= now,
        )
    )
    expired = list(result.scalars().all())
    for row in expired:
        row.status = PlanAdjustmentStatus.EXPIRED.value
        db.add(row)
        # Cool-down also fires on expiry
        # We need user object for cooldown_service — load it
        user = await db.get(User, row.user_id)
        if user is not None:
            await _apply_cooldowns_for_trigger(db, user, row, audit_id=None)

        audit = CoachingEvent(
            user_id=row.user_id,
            event_type=CoachingEventType.PLAN_ADJUSTMENT_EXPIRED.value,
            trigger_source=CoachingEventTriggerSource.CRON.value,
            flags_that_fired=[],
            notification_delivered=False,
            shadow_mode=True,
            context={"adjustment_id": str(row.id), "trigger_event_id": str(row.trigger_event_id) if row.trigger_event_id else None},
            idempotency_key=f"adj_expired:{row.id}",
        )
        db.add(audit)

    if expired:
        await db.flush()
    return {"expired_count": len(expired)}


async def list_pending(db: AsyncSession, user: User) -> list[PlanAdjustment]:
    """Pending proposals for a user, sorted by expires_at ascending."""
    result = await db.execute(
        select(PlanAdjustment)
        .where(
            PlanAdjustment.user_id == user.id,
            PlanAdjustment.status == PlanAdjustmentStatus.PROPOSED.value,
        )
        .order_by(PlanAdjustment.expires_at)
    )
    return list(result.scalars().all())


# ── Internals ──────────────────────────────────────────────────────────────

async def _load_adjustment(db: AsyncSession, user: User, adjustment_id: UUID) -> PlanAdjustment:
    row = await db.get(PlanAdjustment, adjustment_id)
    if row is None or row.user_id != user.id:
        raise LookupError(f"PlanAdjustment {adjustment_id} not found for user {user.id}")
    return row


def _compute_expiry(affected_workout_dates: Optional[list[str]]) -> datetime:
    """
    Workout-level: expires at the EARLIEST affected workout's start + 1h.
    Block-level (multiple dates or no dates): proposed_at + 7 days.
    """
    now = datetime.now(timezone.utc)
    if not affected_workout_dates:
        return now + timedelta(days=_BLOCK_LEVEL_DAYS)
    if len(affected_workout_dates) == 1:
        try:
            d = datetime.fromisoformat(affected_workout_dates[0])
            if d.tzinfo is None:
                d = d.replace(tzinfo=timezone.utc)
            # Treat the workout as starting at 23:59 of its date if no time given,
            # giving the athlete the full day to review. Add the 1h grace.
            return d.replace(hour=23, minute=59, second=0) + timedelta(hours=_WORKOUT_LEVEL_GRACE_HOURS)
        except ValueError:
            return now + timedelta(days=_BLOCK_LEVEL_DAYS)
    return now + timedelta(days=_BLOCK_LEVEL_DAYS)


async def _apply_cooldowns_for_trigger(
    db: AsyncSession,
    user: User,
    adjustment: PlanAdjustment,
    *,
    audit_id: Optional[UUID],
) -> None:
    """
    Look up the trigger event's flags_that_fired and set a 72h cool-down per type.
    Defensive — silently skip if trigger event missing or has no flags.
    """
    if adjustment.trigger_event_id is None:
        return
    trigger = await db.get(CoachingEvent, adjustment.trigger_event_id)
    if trigger is None or not trigger.flags_that_fired:
        return
    for flag_type in trigger.flags_that_fired:
        await cooldown_service.set_cooldown(
            db, user.id, flag_type,
            hours=72,
            set_by_event_id=audit_id,
        )
