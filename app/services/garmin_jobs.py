"""
Scheduled Garmin jobs:

- garmin_token_refresh_job — every 6h, refreshes any access token expiring soon
- garmin_reconcile_job — daily 3 AM Pacific, pulls last 48h via REST (catches webhook drops)

Registered with the v2 scheduler in `register_jobs()` — called from app.main before
`start_scheduler()`.

Both jobs open their own DB sessions and never raise (failures logged + ops alerts).
"""

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from app.database import async_session
from app.models.coaching_event import (
    CoachingEvent,
    CoachingEventType,
    CoachingEventTriggerSource,
)
from app.models.user import User
from app.scheduler import PACIFIC, scheduler
from app.services import garmin_service

logger = logging.getLogger(__name__)


# ── Token refresh ──────────────────────────────────────────────────────────

# Refresh tokens that expire within this window. Garmin access tokens are ~24h.
_REFRESH_THRESHOLD = timedelta(hours=1)


async def refresh_expiring_tokens() -> dict:
    """
    Find any user whose Garmin access token will expire soon and refresh it.
    We don't store the explicit expiry timestamp, so this conservatively
    refreshes anyone connected for >23h since last connect/refresh.
    """
    refreshed = 0
    failed = 0
    cutoff = datetime.now(timezone.utc) - timedelta(hours=23)

    async with async_session() as db:
        result = await db.execute(
            select(User).where(
                User.garmin_refresh_token.is_not(None),
                User.garmin_connected_at <= cutoff,
            )
        )
        users = list(result.scalars().all())

        for user in users:
            try:
                client = garmin_service.GarminClient()
                tokens = await client.refresh_token(user.garmin_refresh_token)
                user.garmin_access_token = tokens.get("access_token", user.garmin_access_token)
                if tokens.get("refresh_token"):
                    user.garmin_refresh_token = tokens["refresh_token"]
                # Bump connected_at so we don't re-refresh on every tick
                user.garmin_connected_at = datetime.now(timezone.utc)
                db.add(user)
                refreshed += 1
            except Exception as exc:
                logger.warning("Garmin token refresh failed for user=%s: %s", user.id, exc)
                failed += 1
        await db.commit()

    if refreshed or failed:
        logger.info("Garmin token refresh job: refreshed=%d failed=%d", refreshed, failed)
    return {"refreshed": refreshed, "failed": failed}


# ── Daily reconciliation ───────────────────────────────────────────────────

# Alert if reconciliation finds more than this many missing records for one user
_OPS_ALERT_MISSING_THRESHOLD = 5


async def reconcile_recent_garmin_data() -> dict:
    """
    Pull the last 48h of activities + daily metrics for every connected user
    via the REST API and insert anything missing. Idempotent on activity_id /
    (user_id, date).

    Catches webhook drops, signature mismatches, deploy-window misses.
    """
    total_recovered = 0
    users_processed = 0
    ops_alerts: list[str] = []

    async with async_session() as db:
        result = await db.execute(
            select(User).where(User.garmin_access_token.is_not(None))
        )
        users = list(result.scalars().all())

        today = datetime.now(timezone.utc).date()
        since = today - timedelta(days=2)

        for user in users:
            users_processed += 1
            client = garmin_service.GarminClient(access_token=user.garmin_access_token)
            user_recovered = 0

            try:
                activities = await client.list_activities(since=since, until=today)
                for activity in activities:
                    try:
                        # ingest is idempotent — re-pushes are no-ops at the DB level
                        await garmin_service.ingest_workout(db, user, activity)
                        user_recovered += 1
                    except Exception:
                        logger.exception("Reconcile ingest_workout failed for user=%s", user.id)
            except Exception as exc:
                logger.warning("Reconcile list_activities failed for user=%s: %s", user.id, exc)

            try:
                metrics = await client.list_daily_metrics(since=since, until=today)
                for metric in metrics:
                    try:
                        await garmin_service.ingest_daily_metric(db, user, metric)
                        user_recovered += 1
                    except Exception:
                        logger.exception("Reconcile ingest_daily_metric failed for user=%s", user.id)
            except Exception as exc:
                logger.warning("Reconcile list_daily_metrics failed for user=%s: %s", user.id, exc)

            total_recovered += user_recovered

            # Audit row: even idempotent reconciles get logged for observability
            event = CoachingEvent(
                user_id=user.id,
                event_type=CoachingEventType.GARMIN_RECONCILE.value,
                trigger_source=CoachingEventTriggerSource.CRON.value,
                flags_that_fired=[],
                context={"since": since.isoformat(), "until": today.isoformat(), "recovered": user_recovered},
                idempotency_key=f"garmin_reconcile:{user.id}:{today.isoformat()}",
                shadow_mode=True,  # never user-facing
            )
            db.add(event)

            if user_recovered > _OPS_ALERT_MISSING_THRESHOLD:
                msg = f"Garmin webhook may be degraded — recovered {user_recovered} missing records for user {user.id}"
                logger.error(msg)
                ops_alerts.append(msg)

        await db.commit()

    summary = {
        "users_processed": users_processed,
        "total_recovered": total_recovered,
        "ops_alerts": ops_alerts,
    }
    logger.info("Garmin reconcile job: %s", summary)
    return summary


# ── Job registration ───────────────────────────────────────────────────────

def register_jobs() -> None:
    """
    Wire Garmin cron jobs into the v2 scheduler. Called once from app.main
    before start_scheduler(), so jobs exist when the scheduler boots.
    Idempotent — safe to call multiple times in tests.
    """
    if scheduler.get_job("garmin_token_refresh"):
        return  # already registered

    scheduler.add_job(
        refresh_expiring_tokens,
        trigger=IntervalTrigger(hours=6),
        id="garmin_token_refresh",
        replace_existing=True,
        max_instances=1,
        misfire_grace_time=300,
    )
    scheduler.add_job(
        reconcile_recent_garmin_data,
        trigger=CronTrigger(hour=3, minute=0, timezone=PACIFIC),
        id="garmin_reconcile",
        replace_existing=True,
        max_instances=1,
        misfire_grace_time=600,
    )
    logger.info("Registered Garmin scheduled jobs: token_refresh (6h), reconcile (3am PT daily)")
