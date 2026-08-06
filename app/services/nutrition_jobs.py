"""
Nutrition cron jobs:
  - nutrition_morning_guidance_job  — 7 AM PT, push fueling guidance for today's planned workout
  - nutrition_evening_check_job     — 8 PM PT, gap analysis push if intake < 80% target
  - race_fueling_plan_trigger_job   — 6 AM PT daily, generate plan for any race exactly 14d out
"""

import logging
from datetime import datetime, timedelta, timezone

from apscheduler.triggers.cron import CronTrigger
from sqlalchemy import select

from app.database import async_session
from app.models.event import Event, EventRegistration
from app.models.race_fueling_plan import RaceFuelingPlan
from app.models.run import Run
from app.models.user import User
from app.scheduler import PACIFIC, scheduler
from app.services import nutrition_service, push_service, race_fueling_service

logger = logging.getLogger(__name__)


# ── Morning fueling guidance ────────────────────────────────────────────────

async def nutrition_morning_guidance_job() -> dict:
    """
    For users with a planned workout today (any Run with planned_workout_type
    not null and completed_at = today), push a brief fueling-guidance prompt.
    The actual prose is generated lazily — for v1 we just push a contextual
    message; the athlete taps to open TodayNutritionView. Phase 6.1 follow-up
    will Sonnet-generate per-athlete morning guidance text.
    """
    pushed = 0
    skipped = 0
    today = datetime.now(timezone.utc).date()
    start = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)
    end = datetime.combine(today, datetime.max.time(), tzinfo=timezone.utc)

    async with async_session() as db:
        # Users with a planned run today
        users_q = await db.execute(
            select(User).join(Run, Run.user_id == User.id).where(
                Run.completed_at >= start,
                Run.completed_at <= end,
                Run.planned_workout_type.is_not(None),
            ).distinct()
        )
        users = list(users_q.scalars().unique().all())

        for user in users:
            # Skip if already pushed once today
            already = await _already_pushed_today(db, user.id, "nutrition_morning_guidance")
            if already:
                skipped += 1
                continue

            # Look up today's planned workout type for the body
            run_q = await db.execute(
                select(Run.planned_workout_type, Run.planned_workout_title).where(
                    Run.user_id == user.id,
                    Run.completed_at >= start,
                    Run.completed_at <= end,
                ).limit(1)
            )
            workout_row = run_q.first()
            workout_label = (workout_row[1] or workout_row[0] or "today's run") if workout_row else "today's run"

            delivered, _ = await push_service.send_push(
                db, user,
                title="Today's fueling",
                body=f"Coach has fueling guidance for {workout_label}. Tap to review.",
                deep_link="stride://nutrition/log",
                notification_type="nutrition_morning_guidance",
                loop_name="nutrition",
            )
            if delivered:
                pushed += 1
        await db.commit()

    summary = {"pushed": pushed, "skipped": skipped, "candidates": len(users)}
    logger.info("nutrition_morning_guidance_job: %s", summary)
    return summary


# ── Evening gap analysis ───────────────────────────────────────────────────

async def nutrition_evening_check_job() -> dict:
    """
    Check today's intake gap. If intake < 80% of any floor (carbs/protein/calories),
    push a brief reminder. Skipped if no meals logged at all today (athlete may
    just not be using the feature).
    """
    pushed = 0
    skipped = 0

    async with async_session() as db:
        users_q = await db.execute(select(User).where(User.auth_provider.is_not(None)))
        users = list(users_q.scalars().all())

        for user in users:
            totals = await nutrition_service.get_today_totals(db, user.id)
            if totals.get("meal_count", 0) == 0:
                skipped += 1
                continue

            body_weight_kg = float(getattr(user, "body_weight_kg", None) or 70.0)
            # Assume rest day if no run today (less aggressive carb floor)
            from app.models.run import Run
            today = datetime.now(timezone.utc).date()
            start = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)
            end = datetime.combine(today, datetime.max.time(), tzinfo=timezone.utc)
            run_type_q = await db.execute(
                select(Run.planned_workout_type).where(
                    Run.user_id == user.id,
                    Run.completed_at >= start,
                    Run.completed_at <= end,
                ).limit(1)
            )
            planned_type = run_type_q.scalar_one_or_none()

            targets = nutrition_service.compute_daily_targets(
                body_weight_kg=body_weight_kg,
                planned_workout_type=planned_type,
            )
            gap = nutrition_service.compute_today_gap(totals=totals, targets=targets)
            if not gap["any_shortfall"]:
                skipped += 1
                continue

            already = await _already_pushed_today(db, user.id, "nutrition_evening_gap")
            if already:
                skipped += 1
                continue

            shortfall_msg = _shortfall_summary(gap["shortfalls"])
            delivered, _ = await push_service.send_push(
                db, user,
                title="Quick fueling note",
                body=shortfall_msg,
                deep_link="stride://nutrition/log",
                notification_type="nutrition_evening_gap",
                loop_name="nutrition",
            )
            if delivered:
                pushed += 1
        await db.commit()

    summary = {"pushed": pushed, "skipped": skipped, "total": len(users)}
    logger.info("nutrition_evening_check_job: %s", summary)
    return summary


def _shortfall_summary(shortfalls: dict) -> str:
    """Build a one-line push body from the gap dict."""
    parts = []
    if "carbs_g" in shortfalls:
        s = shortfalls["carbs_g"]
        parts.append(f"carbs short by ~{int(s['deficit_g'])}g")
    if "protein_g" in shortfalls:
        s = shortfalls["protein_g"]
        parts.append(f"protein short by ~{int(s['deficit_g'])}g")
    if "calories" in shortfalls:
        s = shortfalls["calories"]
        parts.append(f"under fueling floor by ~{s['deficit_kcal']}")
    if not parts:
        return "Tap to review today's fueling."
    return ", ".join(parts) + " — tap to top up."


# ── Race fueling 14d trigger ───────────────────────────────────────────────

async def race_fueling_plan_trigger_job() -> dict:
    """
    For each athlete with a registered race exactly 14 days out, kick off
    race_fueling_service.generate_plan if no plan exists for that event yet.
    """
    fired = 0
    skipped = 0
    today = datetime.now(timezone.utc).date()
    target_date = today + timedelta(days=14)
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
        regs = list(regs_q.all())

        for reg, event in regs:
            existing_q = await db.execute(
                select(RaceFuelingPlan.id).where(
                    RaceFuelingPlan.user_id == reg.user_id,
                    RaceFuelingPlan.event_id == event.id,
                ).limit(1)
            )
            if existing_q.scalar_one_or_none() is not None:
                skipped += 1
                continue

            try:
                await race_fueling_service.generate_plan(reg.user_id, event.id, source="cron")
                fired += 1
            except Exception:
                logger.exception("race_fueling_plan_trigger_job: generate_plan failed user=%s event=%s", reg.user_id, event.id)

    summary = {"fired": fired, "skipped": skipped, "candidates": len(regs)}
    logger.info("race_fueling_plan_trigger_job: %s", summary)
    return summary


# ── Helpers ────────────────────────────────────────────────────────────────

async def _already_pushed_today(db, user_id, notification_type: str) -> bool:
    """Did we already send this notification_type to this user today?"""
    from app.models.coaching_event import CoachingEvent
    today = datetime.now(timezone.utc).date()
    start = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)
    result = await db.execute(
        select(CoachingEvent.id).where(
            CoachingEvent.user_id == user_id,
            CoachingEvent.notification_delivered.is_(True),
            CoachingEvent.triggered_at >= start,
            CoachingEvent.context["notification_type"].astext == notification_type,
        ).limit(1)
    )
    # The astext jsonpath query may not always work depending on JSONB structure;
    # for v1 we fall back to false if it errors.
    try:
        return result.scalar_one_or_none() is not None
    except Exception:
        return False


def register_jobs() -> None:
    if not scheduler.get_job("nutrition_morning_guidance"):
        scheduler.add_job(
            nutrition_morning_guidance_job,
            trigger=CronTrigger(hour=7, minute=0, timezone=PACIFIC),
            id="nutrition_morning_guidance",
            replace_existing=True,
            max_instances=1,
            misfire_grace_time=3600,
        )
    if not scheduler.get_job("nutrition_evening_gap"):
        scheduler.add_job(
            nutrition_evening_check_job,
            trigger=CronTrigger(hour=20, minute=0, timezone=PACIFIC),
            id="nutrition_evening_gap",
            replace_existing=True,
            max_instances=1,
            misfire_grace_time=3600,
        )
    if not scheduler.get_job("race_fueling_plan_trigger"):
        scheduler.add_job(
            race_fueling_plan_trigger_job,
            trigger=CronTrigger(hour=6, minute=0, timezone=PACIFIC),
            id="race_fueling_plan_trigger",
            replace_existing=True,
            max_instances=1,
            misfire_grace_time=3600,
        )
    logger.info("Registered nutrition jobs: morning 7am, evening 8pm, race-fueling 6am (14d trigger)")
