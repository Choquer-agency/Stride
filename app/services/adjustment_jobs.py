"""
Hourly cron sweeping PROPOSED plan adjustments past their expires_at → EXPIRED.
Per Phase 3 plan: expiry is treated as rejection for cool-down purposes
(athlete didn't act = they don't want it).
"""

import logging

from apscheduler.triggers.interval import IntervalTrigger

from app.database import async_session
from app.scheduler import scheduler
from app.services import plan_adjustment_service

logger = logging.getLogger(__name__)


async def adjustment_expiry_job() -> dict:
    """Sweep expired proposals + apply cool-downs. Fires hourly."""
    async with async_session() as db:
        summary = await plan_adjustment_service.expire_pending(db)
        await db.commit()
    if summary.get("expired_count", 0) > 0:
        logger.info("adjustment_expiry_job: %s", summary)
    return summary


def register_jobs() -> None:
    if scheduler.get_job("adjustment_expiry"):
        return
    scheduler.add_job(
        adjustment_expiry_job,
        trigger=IntervalTrigger(hours=1),
        id="adjustment_expiry",
        replace_existing=True,
        max_instances=1,
        misfire_grace_time=600,
    )
    logger.info("Registered adjustment_expiry job: hourly")
