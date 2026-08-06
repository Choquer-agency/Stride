"""
Monday-morning weekly review fallback cron.

The interactive check-in (weekly_checkin_jobs, rest-day invite) is now the
primary path: when the athlete submits answers, the review fires immediately
with those answers as input. This cron is the safety net — Monday 09:00
Pacific it expires unanswered invites and runs the data-only review exactly as
the old Sunday-evening cron did. Weeks whose check-in already produced a
review are skipped.

Registered with the scheduler in `register_jobs()` — called from app.main
before `start_scheduler()`.
"""

import asyncio
import logging
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import desc, select
from apscheduler.triggers.cron import CronTrigger

from app.database import async_session
from app.models.coaching_event import (
    CoachingEvent,
    CoachingEventTriggerSource,
    CoachingEventType,
)
from app.models.user import User
from app.scheduler import PACIFIC, scheduler
from app.services.weekly_review_service import run_weekly_review

logger = logging.getLogger(__name__)


async def weekly_review_job() -> dict:
    """
    Iterate all signed-in users and fire `run_weekly_review` for each.
    Each call opens its own DB session so failures are isolated per user.

    Returns a summary dict with counts (used by tests / admin).
    """
    fired = 0
    skipped = 0
    failed = 0

    async with async_session() as db:
        result = await db.execute(
            select(User.id).where(
                # Crude "active" filter — has any sign-in via auth_provider
                User.auth_provider.is_not(None),
            )
        )
        user_ids = [row[0] for row in result.all()]

    for user_id in user_ids:
        try:
            # Phase 7: skip user if a block review fired in the past 6 days —
            # the block review supersedes this week's weekly check-in.
            if await _block_review_recently_fired(user_id):
                skipped += 1
                continue
            # Phase 8: skip user if they're in the race-prep window — race_prep_weekly
            # cron fires the race-prep variant instead.
            if await _user_in_race_prep_window(user_id):
                skipped += 1
                continue
            # Interactive check-in: if last week's check-in was submitted, the
            # review already ran on submit — skip. If it was never answered,
            # mark it expired and fall through to the data-only review.
            if await _expire_or_skip_checkin(user_id):
                skipped += 1
                continue
            event_id = await run_weekly_review(
                user_id,
                source=CoachingEventTriggerSource.CRON.value,
                # Monday-morning fallback reviews the week that ended yesterday.
                anchor_date=datetime.now(timezone.utc).date() - timedelta(days=1),
            )
            if event_id is None:
                skipped += 1
            else:
                fired += 1
        except Exception:
            logger.exception("weekly_review_job: run_weekly_review failed for user=%s", user_id)
            failed += 1

    summary = {"fired": fired, "skipped": skipped, "failed": failed, "total_users": len(user_ids)}
    logger.info("weekly_review_job complete: %s", summary)
    return summary


async def _block_review_recently_fired(user_id: UUID) -> bool:
    """True if a block_review event landed in the past 6 days for this user."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=6)
    async with async_session() as db:
        result = await db.execute(
            select(CoachingEvent.id).where(
                CoachingEvent.user_id == user_id,
                CoachingEvent.event_type == CoachingEventType.BLOCK_REVIEW.value,
                CoachingEvent.triggered_at >= cutoff,
                CoachingEvent.llm_output.is_not(None),
            ).limit(1)
        )
        return result.scalar_one_or_none() is not None


async def _user_in_race_prep_window(user_id: UUID) -> bool:
    """True if athlete has a registered race within the next 28 days."""
    from app.services.race_prep_service import is_in_race_prep_window
    async with async_session() as db:
        return (await is_in_race_prep_window(db, user_id)) is not None


async def _expire_or_skip_checkin(user_id: UUID) -> bool:
    """
    Reconcile last week's interactive check-in before the fallback review.

    Returns True (skip this user) when the check-in was submitted — the review
    already ran on submit. Otherwise marks any still-open invite as expired and
    returns False so the data-only review proceeds.
    """
    from app.models.weekly_checkin import WeeklyCheckin, WeeklyCheckinStatus
    from app.services.weekly_checkin_service import week_ending_for

    last_week_ending = week_ending_for(datetime.now(timezone.utc).date() - timedelta(days=7))
    async with async_session() as db:
        result = await db.execute(
            select(WeeklyCheckin).where(
                WeeklyCheckin.user_id == user_id,
                WeeklyCheckin.week_ending == last_week_ending,
            ).limit(1)
        )
        checkin = result.scalar_one_or_none()
        if checkin is None:
            return False
        if checkin.status == WeeklyCheckinStatus.SUBMITTED.value:
            return True
        if checkin.status in (WeeklyCheckinStatus.INVITED.value, WeeklyCheckinStatus.IN_PROGRESS.value):
            checkin.status = WeeklyCheckinStatus.EXPIRED.value
            await db.commit()
        return False


def register_jobs() -> None:
    """Wire the Monday 9 AM Pacific weekly-review fallback cron."""
    if scheduler.get_job("weekly_review"):
        return
    scheduler.add_job(
        weekly_review_job,
        trigger=CronTrigger(day_of_week="mon", hour=9, minute=0, timezone=PACIFIC),
        id="weekly_review",
        replace_existing=True,
        max_instances=1,
        misfire_grace_time=3600,  # 1h grace if backend was restarting at 9 AM
    )
    logger.info("Registered weekly_review job (fallback): Monday 9 AM Pacific")
