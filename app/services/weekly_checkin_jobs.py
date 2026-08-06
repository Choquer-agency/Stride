"""
Daily check-in invite cron — 09:00 Pacific. For each active user whose
effective check-in day (User.checkin_day_of_week, default Sunday) is today,
create this week's interactive check-in invite.

The Monday-morning weekly_review cron remains the fallback for athletes who
never answer (see weekly_review_jobs).
"""

import logging
from datetime import datetime

from apscheduler.triggers.cron import CronTrigger
from sqlalchemy import select

from app.database import async_session
from app.models.user import User
from app.scheduler import PACIFIC, scheduler
from app.services import weekly_checkin_service

logger = logging.getLogger(__name__)


async def weekly_checkin_invite_job() -> dict:
    """Invite every user whose check-in day is today (Pacific)."""
    today_dow = datetime.now(PACIFIC).weekday()  # 0=Monday .. 6=Sunday
    invited = 0
    skipped = 0
    failed = 0

    async with async_session() as db:
        result = await db.execute(
            select(User.id, User.checkin_day_of_week).where(
                User.auth_provider.is_not(None),
            )
        )
        rows = result.all()

    for user_id, checkin_day in rows:
        effective = checkin_day if checkin_day is not None and 0 <= checkin_day <= 6 else weekly_checkin_service.DEFAULT_CHECKIN_DAY
        if effective != today_dow:
            continue
        try:
            checkin_id = await weekly_checkin_service.create_invite(user_id)
            if checkin_id is None:
                skipped += 1
            else:
                invited += 1
        except Exception:
            logger.exception("weekly_checkin_invite_job failed for user=%s", user_id)
            failed += 1

    summary = {"invited": invited, "skipped": skipped, "failed": failed, "day_of_week": today_dow}
    logger.info("weekly_checkin_invite_job complete: %s", summary)
    return summary


def register_jobs() -> None:
    """Wire the daily 9 AM Pacific check-in invite cron."""
    if scheduler.get_job("weekly_checkin_invite"):
        return
    scheduler.add_job(
        weekly_checkin_invite_job,
        trigger=CronTrigger(hour=9, minute=0, timezone=PACIFIC),
        id="weekly_checkin_invite",
        replace_existing=True,
        max_instances=1,
        misfire_grace_time=3600,
    )
    logger.info("Registered weekly_checkin_invite job: daily 9 AM Pacific")
