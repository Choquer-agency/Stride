"""
Wellness reminder cron jobs:
  - morning_reminder_job: 8 AM Pacific daily — push if no morning entry today
  - evening_nudge_job:    8 PM Pacific daily — push if no entries at all today
"""

import logging
from datetime import datetime, timezone

from apscheduler.triggers.cron import CronTrigger
from sqlalchemy import select

from app.database import async_session
from app.models.user import User
from app.scheduler import PACIFIC, scheduler
from app.services import push_service, wellness_service

logger = logging.getLogger(__name__)


async def morning_reminder_job() -> dict:
    """Push every user who hasn't logged a morning wellness check-in today yet."""
    pushed = 0
    skipped = 0

    async with async_session() as db:
        result = await db.execute(
            select(User).where(User.auth_provider.is_not(None))
        )
        users = list(result.scalars().all())

        for user in users:
            today = await wellness_service.get_today(db, user.id)
            if today["morning"] is not None:
                skipped += 1
                continue
            delivered, _ = await push_service.send_push(
                db, user,
                title="Morning check-in",
                body="30 seconds to log how you're feeling. Coach uses this.",
                deep_link="stride://wellness/checkin",
                notification_type="wellness_morning_reminder",
                loop_name="wellness",
            )
            if delivered:
                pushed += 1
        await db.commit()

    summary = {"pushed": pushed, "skipped": skipped, "total": len(users)}
    logger.info("morning_reminder_job: %s", summary)
    return summary


async def evening_nudge_job() -> dict:
    """Push users who haven't logged ANY wellness entry today."""
    pushed = 0
    skipped = 0

    async with async_session() as db:
        result = await db.execute(
            select(User).where(User.auth_provider.is_not(None))
        )
        users = list(result.scalars().all())

        for user in users:
            today = await wellness_service.get_today(db, user.id)
            has_any = today["morning"] is not None or today["pre_run"] or today["post_run"]
            if has_any:
                skipped += 1
                continue
            delivered, _ = await push_service.send_push(
                db, user,
                title="One check-in?",
                body="Quick wellness log — coach is watching the trend, not just any one day.",
                deep_link="stride://wellness/checkin",
                notification_type="wellness_evening_nudge",
                loop_name="wellness",
            )
            if delivered:
                pushed += 1
        await db.commit()

    summary = {"pushed": pushed, "skipped": skipped, "total": len(users)}
    logger.info("evening_nudge_job: %s", summary)
    return summary


def register_jobs() -> None:
    if not scheduler.get_job("wellness_morning_reminder"):
        scheduler.add_job(
            morning_reminder_job,
            trigger=CronTrigger(hour=8, minute=0, timezone=PACIFIC),
            id="wellness_morning_reminder",
            replace_existing=True,
            max_instances=1,
            misfire_grace_time=3600,
        )
    if not scheduler.get_job("wellness_evening_nudge"):
        scheduler.add_job(
            evening_nudge_job,
            trigger=CronTrigger(hour=20, minute=0, timezone=PACIFIC),
            id="wellness_evening_nudge",
            replace_existing=True,
            max_instances=1,
            misfire_grace_time=3600,
        )
    logger.info("Registered wellness jobs: morning 8am PT, evening 8pm PT")
