"""
Per-user, per-flag-type cool-downs after a plan adjustment is rejected or expires.

The anomaly engine still raises flags into anomaly_flags for the audit trail,
but post_run_check filters cooled-down flag types out of the LLM input — preventing
nag. Cool-downs auto-clear early when severity escalates (e.g. a 10% HRV drop
gets cooled, then the next day shows 16% drop → cool-down clears, fires).
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import delete, desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.anomaly_flag import AnomalyFlag, FlagSeverity
from app.models.coaching_cooldown import CoachingCooldown

logger = logging.getLogger(__name__)


# ── Severity ranking for escalation checks ──────────────────────────────────
_SEVERITY_RANK = {
    FlagSeverity.INFO.value: 0,
    FlagSeverity.WARNING.value: 1,
    FlagSeverity.WARNING_PLUS.value: 2,
    FlagSeverity.CRITICAL.value: 3,
}


# ── Public API ──────────────────────────────────────────────────────────────

async def set_cooldown(
    db: AsyncSession,
    user_id: UUID,
    flag_type: str,
    *,
    hours: int = 72,
    set_by_event_id: Optional[UUID] = None,
) -> CoachingCooldown:
    """Set (or refresh) a cool-down for one flag type. Idempotent — replaces existing."""
    # Drop any existing cool-down for this user+flag_type
    await db.execute(
        delete(CoachingCooldown).where(
            CoachingCooldown.user_id == user_id,
            CoachingCooldown.flag_type == flag_type,
        )
    )
    until = datetime.now(timezone.utc) + timedelta(hours=hours)
    row = CoachingCooldown(
        user_id=user_id,
        flag_type=flag_type,
        cooldown_until=until,
        set_by_event_id=set_by_event_id,
    )
    db.add(row)
    await db.flush()
    logger.info("Cool-down set: user=%s flag=%s until=%s", user_id, flag_type, until.isoformat())
    return row


async def is_in_cooldown(db: AsyncSession, user_id: UUID, flag_type: str) -> bool:
    """True if this flag type is currently cooled-down for this user."""
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(CoachingCooldown.id).where(
            CoachingCooldown.user_id == user_id,
            CoachingCooldown.flag_type == flag_type,
            CoachingCooldown.cooldown_until > now,
        ).limit(1)
    )
    return result.scalar_one_or_none() is not None


async def filter_active_flags(
    db: AsyncSession,
    user_id: UUID,
    flags: list[AnomalyFlag],
) -> list[AnomalyFlag]:
    """
    Remove any flag whose type is currently cooled-down, UNLESS the new flag's
    severity has escalated past the severity that originally triggered the
    cool-down — in which case clear the cool-down and keep the flag.

    Returns the filtered list of flags suitable for inclusion in the LLM prompt.
    """
    if not flags:
        return []

    # Pull all current cool-downs for this user in one query
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(CoachingCooldown).where(
            CoachingCooldown.user_id == user_id,
            CoachingCooldown.cooldown_until > now,
        )
    )
    active_cooldowns = {c.flag_type: c for c in result.scalars().all()}

    kept: list[AnomalyFlag] = []
    for flag in flags:
        if flag.flag_type not in active_cooldowns:
            kept.append(flag)
            continue
        # Cool-down active. Check escalation.
        prior_severity = await _severity_when_cooldown_set(db, active_cooldowns[flag.flag_type])
        if prior_severity is None or _SEVERITY_RANK.get(flag.severity, 0) > _SEVERITY_RANK.get(prior_severity, 0):
            await _clear_cooldown(db, active_cooldowns[flag.flag_type])
            logger.info(
                "Cool-down cleared on escalation: user=%s flag=%s prior_sev=%s new_sev=%s",
                user_id, flag.flag_type, prior_severity, flag.severity,
            )
            kept.append(flag)
        # else: stays cooled — drop the flag silently
    return kept


# ── Internals ──────────────────────────────────────────────────────────────

async def _severity_when_cooldown_set(db: AsyncSession, cooldown: CoachingCooldown) -> Optional[str]:
    """
    Look up the severity of the most recent active flag of this type at the time
    the cool-down was set. We approximate by reading the latest active flag's
    severity from before the cool-down's created_at.
    """
    if cooldown.created_at is None:
        return None
    result = await db.execute(
        select(AnomalyFlag.severity)
        .where(
            AnomalyFlag.user_id == cooldown.user_id,
            AnomalyFlag.flag_type == cooldown.flag_type,
            AnomalyFlag.raised_at <= cooldown.created_at,
        )
        .order_by(desc(AnomalyFlag.raised_at))
        .limit(1)
    )
    return result.scalar_one_or_none()


async def _clear_cooldown(db: AsyncSession, cooldown: CoachingCooldown) -> None:
    await db.execute(
        delete(CoachingCooldown).where(CoachingCooldown.id == cooldown.id)
    )
    await db.flush()
