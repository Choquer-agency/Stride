"""
APScheduler-based cron scheduler for v2 coaching loops.

All athlete-facing cadences fire on Pacific time. Cross-cutting jobs (Garmin
reconciliation, adjustment expiry sweeps, etc.) also use Pacific to avoid timezone
debugging confusion.

Usage:
    from app.scheduler import scheduler

    @scheduler.scheduled_job('cron', day_of_week='sun', hour=20, timezone=PACIFIC)
    async def my_job():
        ...

The scheduler is started/stopped from app/main.py startup/shutdown hooks.
Single Railway worker → single fire per cron entry. If we ever scale to multiple
workers, switch to a distributed lock (e.g., postgres advisory locks) on each job.
"""

import logging
from zoneinfo import ZoneInfo

from apscheduler.schedulers.asyncio import AsyncIOScheduler

logger = logging.getLogger(__name__)

# All athlete-local cadences use this timezone.
PACIFIC = ZoneInfo("America/Los_Angeles")

# Module-level singleton — feature modules import and register jobs.
scheduler = AsyncIOScheduler(timezone=PACIFIC)


def start_scheduler() -> None:
    """Start the scheduler. Called from app.main startup hook."""
    if not scheduler.running:
        scheduler.start()
        jobs = scheduler.get_jobs()
        logger.info("Scheduler started with %d jobs: %s", len(jobs), [j.id for j in jobs])


def shutdown_scheduler() -> None:
    """Cleanly shut down the scheduler. Called from app.main shutdown hook."""
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Scheduler shut down")
