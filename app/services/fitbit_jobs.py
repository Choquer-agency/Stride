"""
Scheduled Fitbit (Google Health API) jobs:

- fitbit_hourly_sync — every hour, pulls the last 48h for every connected user.
  This is the primary feed: the watch syncs to Google's cloud every few
  minutes-to-hours, and this job pulls it down so the coach always has vitals
  at most ~1h stale. (A Health API subscription webhook can tighten this
  later; the hourly pull stays as the safety net.)
- fitbit_daily_reconcile — 3:30 AM Pacific, pulls the last 7 days to catch
  anything the hourly window missed (device offline for a trip, etc.).

Registered from app.main before start_scheduler(), same as garmin_jobs.
Both jobs open their own DB sessions and never raise.
"""

import logging

from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger
from sqlalchemy import select

from app.database import async_session
from app.models.user import User
from app.scheduler import PACIFIC, scheduler
from app.services import fitbit_service

logger = logging.getLogger(__name__)


async def _sync_all_connected(days: int, job_name: str) -> dict:
    synced = 0
    failed = 0
    async with async_session() as db:
        result = await db.execute(
            select(User).where(User.fitbit_refresh_token.is_not(None))
        )
        users = list(result.scalars().all())

        for user in users:
            try:
                await fitbit_service.sync_user(db, user, days=days)
                synced += 1
            except Exception as exc:
                logger.warning("%s failed for user=%s: %s", job_name, user.id, exc)
                failed += 1
        await db.commit()

    summary = {"synced": synced, "failed": failed}
    if synced or failed:
        logger.info("%s: %s", job_name, summary)
    return summary


async def hourly_sync() -> dict:
    return await _sync_all_connected(days=2, job_name="fitbit_hourly_sync")


async def daily_reconcile() -> dict:
    return await _sync_all_connected(days=7, job_name="fitbit_daily_reconcile")


def register_jobs() -> None:
    """Idempotent job registration, called once from app.main."""
    if scheduler.get_job("fitbit_hourly_sync"):
        return

    scheduler.add_job(
        hourly_sync,
        trigger=IntervalTrigger(hours=1),
        id="fitbit_hourly_sync",
        replace_existing=True,
        max_instances=1,
        misfire_grace_time=600,
    )
    scheduler.add_job(
        daily_reconcile,
        trigger=CronTrigger(hour=3, minute=30, timezone=PACIFIC),
        id="fitbit_daily_reconcile",
        replace_existing=True,
        max_instances=1,
        misfire_grace_time=600,
    )
    logger.info("Registered Fitbit scheduled jobs: hourly_sync (1h), daily_reconcile (3:30am PT)")
