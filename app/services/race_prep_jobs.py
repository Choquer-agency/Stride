"""
Race-prep cron jobs:
  - race_prep_entry_check_job (daily 6 AM PT) — fires run_taper_entry for users
    whose race is exactly 28 days out.
  - race_prep_weekly_job      (Sun 8 PM PT)   — runs run_race_prep_review for
    users currently in the 28-day window. Fires INSTEAD of weekly_review_job
    (the latter skips users in race-prep window).
  - race_week_morning_check   (daily 8 AM PT) — race week only — wellness reminder.
  - race_week_evening_check   (daily 8 PM PT) — race week only — wellness reminder.
"""

import logging
from datetime import datetime, timedelta, timezone

from apscheduler.triggers.cron import CronTrigger
from sqlalchemy import select

from app.database import async_session
from app.models.event import Event, EventRegistration
from app.models.user import User
from app.scheduler import PACIFIC, scheduler
from app.services import push_service
from app.services.race_prep_service import (
    is_in_race_prep_window,
    run_race_prep_review,
    run_taper_entry,
)

logger = logging.getLogger(__name__)


_RACE_PREP_DAYS = 28
_RACE_WEEK_DAYS = 7


async def race_prep_entry_check_job() -> dict:
    """
    Iterate registrations whose Event.starts_at == today + 28d. Fire taper-entry
    once per (user, event) — idempotency in race_prep_service.run_taper_entry
    prevents double-firing.
    """
    fired = 0
    skipped = 0
    today = datetime.now(timezone.utc).date()
    target_date = today + timedelta(days=_RACE_PREP_DAYS)
    target_start = datetime.combine(target_date, datetime.min.time(), tzinfo=timezone.utc)
    target_end = datetime.combine(target_date, datetime.max.time(), tzinfo=timezone.utc)

    async with async_session() as db:
        regs_q = await db.execute(
            select(EventRegistration, Event)
            .join(Event, Event.id == EventRegistration.event_id)
            .where(
                Event.starts_at >= target_start,
                Event.starts_at <= target_end,
                Event.is_active.is_(True),
            )
        )
        rows = list(regs_q.all())

    for reg, event in rows:
        try:
            event_id = await run_taper_entry(reg.user_id, event.id)
            if event_id is None:
                skipped += 1
            else:
                fired += 1
        except Exception:
            logger.exception("taper_entry failed user=%s event=%s", reg.user_id, event.id)

    logger.info("race_prep_entry_check_job: fired=%d skipped=%d candidates=%d", fired, skipped, len(rows))
    return {"fired": fired, "skipped": skipped, "candidates": len(rows)}


async def race_prep_weekly_job() -> dict:
    """Sunday 8 PM PT — runs the race-prep review for users currently in the window."""
    fired = 0
    skipped = 0

    async with async_session() as db:
        users_q = await db.execute(select(User.id).where(User.auth_provider.is_not(None)))
        user_ids = [r[0] for r in users_q.all()]

    for user_id in user_ids:
        try:
            event_id = await run_race_prep_review(user_id)
            if event_id is None:
                skipped += 1
            else:
                fired += 1
        except Exception:
            logger.exception("race_prep_weekly_job failed user=%s", user_id)

    logger.info("race_prep_weekly_job: fired=%d skipped=%d total=%d", fired, skipped, len(user_ids))
    return {"fired": fired, "skipped": skipped, "total": len(user_ids)}


async def race_week_morning_check_job() -> dict:
    """Daily 8 AM PT during race week — push a wellness check-in reminder."""
    return await _race_week_push("morning")


async def race_week_evening_check_job() -> dict:
    """Daily 8 PM PT during race week — push a wellness check-in reminder."""
    return await _race_week_push("evening")


async def _race_week_push(slot: str) -> dict:
    pushed = 0
    skipped = 0
    async with async_session() as db:
        users_q = await db.execute(select(User).where(User.auth_provider.is_not(None)))
        users = list(users_q.scalars().all())

        for user in users:
            event = await is_in_race_prep_window(db, user.id)
            if event is None:
                skipped += 1
                continue
            days = (event.starts_at.date() - datetime.now(timezone.utc).date()).days
            if days > _RACE_WEEK_DAYS:
                skipped += 1
                continue

            title = f"Race day in {days} — quick check"
            body = "How's the body? 30 seconds keeps coach in the loop." if slot == "morning" else "Day's done — log how you're feeling for tomorrow."
            delivered, _ = await push_service.send_push(
                db, user,
                title=title,
                body=body,
                deep_link="stride://wellness/checkin",
                notification_type=f"race_week_{slot}",
                loop_name="wellness",
            )
            if delivered:
                pushed += 1
        await db.commit()

    return {"pushed": pushed, "skipped": skipped, "total": len(users)}


def register_jobs() -> None:
    if not scheduler.get_job("race_prep_entry_check"):
        scheduler.add_job(
            race_prep_entry_check_job,
            trigger=CronTrigger(hour=6, minute=0, timezone=PACIFIC),
            id="race_prep_entry_check",
            replace_existing=True,
            max_instances=1,
            misfire_grace_time=3600,
        )
    if not scheduler.get_job("race_prep_weekly"):
        scheduler.add_job(
            race_prep_weekly_job,
            trigger=CronTrigger(day_of_week="sun", hour=20, minute=0, timezone=PACIFIC),
            id="race_prep_weekly",
            replace_existing=True,
            max_instances=1,
            misfire_grace_time=3600,
        )
    if not scheduler.get_job("race_week_morning_check"):
        scheduler.add_job(
            race_week_morning_check_job,
            trigger=CronTrigger(hour=8, minute=0, timezone=PACIFIC),
            id="race_week_morning_check",
            replace_existing=True,
            max_instances=1,
            misfire_grace_time=1800,
        )
    if not scheduler.get_job("race_week_evening_check"):
        scheduler.add_job(
            race_week_evening_check_job,
            trigger=CronTrigger(hour=20, minute=0, timezone=PACIFIC),
            id="race_week_evening_check",
            replace_existing=True,
            max_instances=1,
            misfire_grace_time=1800,
        )
    logger.info("Registered race-prep jobs: entry-check 6am, weekly Sun 8pm, race-week morning + evening")
