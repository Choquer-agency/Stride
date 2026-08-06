"""
Daily 6 AM Pacific check: was YESTERDAY the end of a recovery week? If so,
fire run_block_review for every user with an active plan.

We use plan_week_classifier as a proxy for "was it a recovery week" — if the
prior-completed week classified as `recovery`, that's our trigger. Today must
be a Monday so we only fire once per recovery cycle.
"""

import logging
from datetime import datetime, timedelta, timezone

from apscheduler.triggers.cron import CronTrigger
from sqlalchemy import select

from app.database import async_session
from app.models.coaching_event import CoachingEventTriggerSource
from app.models.user import User
from app.scheduler import PACIFIC, scheduler
from app.services.block_review_service import run_block_review
from app.services.plan_week_classifier import classify_week

logger = logging.getLogger(__name__)


async def block_review_check_job() -> dict:
    """
    Iterate users; classify the week that ENDED yesterday. If it was a recovery
    week, fire run_block_review.
    """
    fired = 0
    skipped = 0
    failed = 0

    today = datetime.now(timezone.utc).date()
    # We classify the week ending on the most recent Sunday <= yesterday.
    yesterday = today - timedelta(days=1)

    async with async_session() as db:
        users_q = await db.execute(
            select(User.id).where(User.auth_provider.is_not(None))
        )
        user_ids = [row[0] for row in users_q.all()]

    for user_id in user_ids:
        try:
            async with async_session() as db:
                week_character = await classify_week(db, user_id, today=yesterday)
            if week_character != "recovery":
                skipped += 1
                continue
            event_id = await run_block_review(
                user_id,
                source=CoachingEventTriggerSource.CRON.value,
            )
            if event_id is None:
                skipped += 1
            else:
                fired += 1
        except Exception:
            logger.exception("block_review_check_job: failed for user=%s", user_id)
            failed += 1

    summary = {"fired": fired, "skipped": skipped, "failed": failed, "total_users": len(user_ids)}
    logger.info("block_review_check_job: %s", summary)
    return summary


def register_jobs() -> None:
    if scheduler.get_job("block_review_check"):
        return
    scheduler.add_job(
        block_review_check_job,
        trigger=CronTrigger(hour=6, minute=0, timezone=PACIFIC),
        id="block_review_check",
        replace_existing=True,
        max_instances=1,
        misfire_grace_time=3600,
    )
    logger.info("Registered block_review_check job: daily 6 AM Pacific")
