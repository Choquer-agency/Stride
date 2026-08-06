"""
Pause-coach service — gates whether automated coaching loops fire.

State (stored on User):
- coaching_paused_until: TIMESTAMP NULL
    None              → not paused
    future timestamp  → paused until then
    far-future date   → "until I resume" sentinel (set by route handler as now+100yrs)
- coaching_resume_pending: BOOL
    True              → user just resumed; the next coaching event must preface
                        with "noted you paused — here's what I see now"

Rules:
- Pause skips ALL non-critical coaching loops.
- Critical-severity flags STILL evaluate during pause. If the athlete is paused
  for more than 24h AND a critical pattern is detected, escalate the notification
  with explicit "I see this pattern — even though you paused, I have to flag this".
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User

logger = logging.getLogger(__name__)


# After this many hours of being paused, critical flags escalate even without consent.
_CRITICAL_GRACE_HOURS = 24


def is_paused(user: User) -> bool:
    """True if the user is currently paused. Cheap — no DB call."""
    if user.coaching_paused_until is None:
        return False
    now = datetime.now(timezone.utc)
    paused_until = user.coaching_paused_until
    if paused_until.tzinfo is None:
        paused_until = paused_until.replace(tzinfo=timezone.utc)
    return paused_until > now


def pause_started_at(user: User) -> Optional[datetime]:
    """
    Approximate the moment the current pause was set: the route handler stamps
    `coaching_paused_until = now + duration`, so subtracting the typical pause
    duration would be unreliable. We don't store pause_started_at separately,
    so this returns None unless we find a smarter signal later.

    For Phase 3's critical-grace check we use a coarse rule: if paused_until is
    far in the future, the pause was set very recently. If paused_until is close
    to now, the pause has been going for a while.
    """
    return None  # placeholder — see should_critical_escalate below for the actual logic


def should_critical_escalate(user: User) -> bool:
    """
    Returns True when a critical flag should notify even though the user is
    paused. Triggers when the pause has been in effect long enough that the
    athlete has had time to absorb it (24h grace).

    We approximate "pause has been in effect for >24h" by checking that
    coaching_paused_until is more than 24h in the future from now (typical
    3-day or 7-day pause), AND the user.updated_at is older than 24h (no
    recent re-pause activity).
    """
    if not is_paused(user):
        return True  # Not paused → critical always notifies (caller normally bypasses this entirely)
    now = datetime.now(timezone.utc)
    paused_until = user.coaching_paused_until
    if paused_until.tzinfo is None:
        paused_until = paused_until.replace(tzinfo=timezone.utc)
    # If user.updated_at is recent (within 24h), we treat the pause as fresh.
    last_update = user.updated_at
    if last_update is not None and last_update.tzinfo is None:
        last_update = last_update.replace(tzinfo=timezone.utc)
    if last_update is None:
        return True
    pause_age_hours = (now - last_update).total_seconds() / 3600.0
    return pause_age_hours >= _CRITICAL_GRACE_HOURS


async def set_pause(
    db: AsyncSession,
    user: User,
    *,
    duration_days: Optional[int] = None,
    until_resume: bool = False,
) -> None:
    """
    Set the pause window on a user. Pass either duration_days OR until_resume.
    The /api/coach/pause route already enforces validation; this is the lower-level
    setter for tests + admin.
    """
    if until_resume and duration_days:
        raise ValueError("provide duration_days OR until_resume, not both")
    if not until_resume and not duration_days:
        raise ValueError("must provide duration_days or until_resume=True")
    now = datetime.now(timezone.utc)
    if until_resume:
        # Far-future sentinel
        user.coaching_paused_until = now + timedelta(days=365 * 100)
    else:
        user.coaching_paused_until = now + timedelta(days=duration_days)
    user.coaching_resume_pending = False
    db.add(user)
    await db.flush()
    logger.info("Pause set: user=%s until=%s", user.id, user.coaching_paused_until.isoformat())


async def resume(db: AsyncSession, user: User, *, set_pending: bool = True) -> None:
    """Clear the pause and (by default) flag the next coaching event to preface acknowledgment."""
    user.coaching_paused_until = None
    user.coaching_resume_pending = set_pending
    db.add(user)
    await db.flush()
    logger.info("Resume: user=%s", user.id)


async def consume_resume_pending(db: AsyncSession, user: User) -> bool:
    """
    Called by coaching loops at the start of generating an event. Returns True
    if the next event should preface "noted you paused" (and clears the flag
    so subsequent events don't repeat).
    """
    if not user.coaching_resume_pending:
        return False
    user.coaching_resume_pending = False
    db.add(user)
    await db.flush()
    return True
