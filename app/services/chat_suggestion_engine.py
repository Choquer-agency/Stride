"""
Dynamic suggested-prompt chips for the empty/paused chat state.

Returns 4-6 chips based on:
- Active anomaly flags (concern-shaped chip)
- Recent plan adjustment (explanation chip)
- Time of day (nutrition chip in evening, recovery chip in morning)
- Default "How am I doing?" always present

iOS calls /api/coach/chat/suggestions every minute or so when chat is idle.
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.anomaly_flag import AnomalyFlag, FlagSeverity, FlagType
from app.models.plan_adjustment import PlanAdjustment, PlanAdjustmentStatus
from app.models.user import User

logger = logging.getLogger(__name__)


_MAX_CHIPS = 6


async def get_suggestions(db: AsyncSession, user: User) -> list[str]:
    """
    Build a list of 4-6 chip strings ordered by priority. Chip text is what the
    athlete sees and what gets sent as the chat message on tap.
    """
    chips: list[str] = []

    # Always-on default
    chips.append("How am I doing?")

    # Concern-shaped chips from active flags
    chips.extend(await _flag_chips(db, user.id))

    # Adjustment explanation chip
    adj_chip = await _recent_adjustment_chip(db, user.id)
    if adj_chip:
        chips.append(adj_chip)

    # Time-of-day chip
    tod = _time_of_day_chip()
    if tod:
        chips.append(tod)

    # Always offer one open-ended chip
    chips.append("Anything I'm missing?")

    # Dedup while preserving order, cap at 6
    seen: set[str] = set()
    out: list[str] = []
    for c in chips:
        if c not in seen:
            seen.add(c)
            out.append(c)
        if len(out) >= _MAX_CHIPS:
            break
    return out


async def _flag_chips(db: AsyncSession, user_id: UUID) -> list[str]:
    result = await db.execute(
        select(AnomalyFlag)
        .where(AnomalyFlag.user_id == user_id, AnomalyFlag.resolved_at.is_(None))
        .order_by(desc(AnomalyFlag.raised_at))
        .limit(5)
    )
    flags = list(result.scalars().all())
    chips: list[str] = []
    for f in flags:
        chip = _chip_for_flag(f)
        if chip and chip not in chips:
            chips.append(chip)
    return chips


def _chip_for_flag(flag: AnomalyFlag) -> Optional[str]:
    t = flag.flag_type
    if t == FlagType.HRV_DROP.value:
        return "What does the HRV drop mean?"
    if t == FlagType.RHR_RISE.value:
        return "Why is my resting heart rate up?"
    if t == FlagType.SLEEP_DEFICIT.value:
        return "How much is the sleep affecting me?"
    if t == FlagType.MISSED_WORKOUTS.value:
        return "Should I worry about missed workouts?"
    if t == FlagType.PAIN_LOGGED.value:
        # Pull body part if available for a sharper chip
        areas = flag.context.get("matched_areas_recent") if flag.context else []
        if areas:
            return f"Should I be worried about my {areas[0]}?"
        return "Should I be worried about the soreness?"
    if t == FlagType.PACE_OFF_TARGET.value:
        ctx = flag.context or {}
        if ctx.get("run_kind") == "easy":
            return "Why was I told I ran too hot easy?"
        return "Why am I off pace on quality?"
    if t == FlagType.WORKOUT_INCOMPLETE.value:
        return "Was cutting that workout short the right call?"
    return None


async def _recent_adjustment_chip(db: AsyncSession, user_id: UUID) -> Optional[str]:
    """If there's been an accepted adjustment in the past 7 days, offer to explain it."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    result = await db.execute(
        select(PlanAdjustment)
        .where(
            PlanAdjustment.user_id == user_id,
            PlanAdjustment.applied_at.is_not(None),
            PlanAdjustment.applied_at >= cutoff,
            PlanAdjustment.status == PlanAdjustmentStatus.ACCEPTED.value,
        )
        .order_by(desc(PlanAdjustment.applied_at))
        .limit(1)
    )
    row = result.scalar_one_or_none()
    if row is None:
        return None
    return "Why did you change my plan?"


def _time_of_day_chip() -> Optional[str]:
    """Coarse Pacific-time-of-day chip; uses server local for v2 simplicity."""
    hour = datetime.now().hour
    if 5 <= hour < 11:
        return "Anything I should focus on today?"
    if 18 <= hour < 23:
        return "What should I eat tonight?"
    return None
