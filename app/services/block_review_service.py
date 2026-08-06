"""
Block-review orchestrator. Same shape as the weekly review pipeline (Phase 2),
but loads a wider window (4-6 weeks) and adds pace recalibration + race
predictor delta as deterministic prompt inputs.

Skip rules:
  - No active plan
  - Recent post_race event (within 6 days) — race recap took priority
  - In race-prep window (race within 28 days) — Phase 8 owns

Triggered by:
  - Daily 6 AM PT cron when YESTERDAY was the last day of a recovery week
  - Manual /api/coach/run-block-review (admin/debug)
"""

import asyncio
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session
from app.models.anomaly_flag import AnomalyFlag
from app.models.coaching_event import (
    CoachingEvent,
    CoachingEventTriggerSource,
    CoachingEventType,
)
from app.models.event import Event, EventRegistration
from app.models.garmin_daily_metric import GarminDailyMetric
from app.models.garmin_workout import GarminWorkout
from app.models.run import Run
from app.models.schemas import RaceType
from app.models.user import User
from app.models.weekly_focus import WeeklyFocus
from app.services import (
    coach_memo_service,
    coaching_models,
    focus_tracker,
    pace_recalibrator,
    plan_adjustment_service,
    push_service,
    wellness_service,
)
from app.services.anthropic_client import AnthropicClient
from app.services.prompt_builder import prompt_builder

logger = logging.getLogger(__name__)


_POST_RACE_SKIP_DAYS = 6
_RACE_PREP_SKIP_DAYS = 28
_BLOCK_WINDOW_WEEKS = 6


# ── Public entry point ─────────────────────────────────────────────────────

async def run_block_review(
    user_id: UUID,
    *,
    source: str = CoachingEventTriggerSource.MANUAL.value,
    force: bool = False,
) -> Optional[UUID]:
    """
    Generate a block review for the user. Opens its own DB session so it can
    fire from cron via asyncio.create_task. Returns coaching_events.id or None.
    """
    async with async_session() as db:
        user = await db.get(User, user_id)
        if user is None:
            logger.warning("block_review: user %s not found", user_id)
            return None

        if not force:
            if await _has_recent_post_race(db, user.id):
                _log_skip(db, user, "recent_post_race")
                await db.commit()
                return None
            if await _in_race_prep_window(db, user.id):
                _log_skip(db, user, "race_prep_active")
                await db.commit()
                return None

        # Load wider window
        runs = await _fetch_runs(db, user.id, weeks=_BLOCK_WINDOW_WEEKS)
        if not runs and not force:
            _log_skip(db, user, "no_runs_in_block")
            await db.commit()
            return None

        prior_reviews = await _fetch_prior_weekly_reviews(db, user.id, count=4)
        active_focuses = await focus_tracker.get_active_focuses(db, user.id, weeks_back=6)
        active_flags = await _fetch_active_flags(db, user.id)
        memo_text = await coach_memo_service.get_memo_text(db, user.id)
        wellness_trends = await wellness_service.compute_trends(db, user.id, window_days=28)

        race_type = _resolve_race_type(user)
        easy_drift = await pace_recalibrator.compute_easy_pace_drift(db, user.id, weeks_back=4)
        threshold_drift = await pace_recalibrator.compute_threshold_drift(db, user.id, weeks_back=4)
        # Goal time + race type would come from athlete plan; for v1 we don't have it server-side.
        goal_alignment = await pace_recalibrator.compute_race_predictor_delta(
            db, user.id,
            race_type=race_type.value if hasattr(race_type, "value") else "marathon",
            goal_time_seconds=getattr(user, "goal_time_seconds", None),
        )

        system_prompt = prompt_builder.get_block_review_prompt(race_type, memo=memo_text)
        user_prompt = _build_user_prompt(
            user=user,
            runs=runs,
            prior_reviews=prior_reviews,
            active_focuses=active_focuses,
            active_flags=active_flags,
            wellness_trends=wellness_trends,
            easy_drift=easy_drift,
            threshold_drift=threshold_drift,
            goal_alignment=goal_alignment,
        )

        client = AnthropicClient()
        model = coaching_models.BLOCK_REVIEW_MODEL
        try:
            output_text = await client.generate_plan(
                system_prompt,
                user_prompt,
                name="block-review",
                user_id=str(user.id),
                metadata={"window_weeks": _BLOCK_WINDOW_WEEKS},
                model=model,
            )
        except Exception:
            logger.exception("block_review LLM call failed for user=%s", user_id)
            return None

        metrics = client.last_metrics

        next_focuses = focus_tracker.parse_focuses(output_text)
        outcomes = focus_tracker.parse_focus_outcomes(output_text)
        adjustment = focus_tracker.parse_adjustment(output_text)
        clean_output = focus_tracker.strip_tags(output_text)

        cost_usd = coaching_models.estimate_cost_usd(
            model,
            metrics.input_tokens if metrics else 0,
            metrics.output_tokens if metrics else 0,
        )
        prompt_sha = prompt_builder.prompt_sha("coach_block_review.txt")

        event_id = uuid4()
        event = CoachingEvent(
            id=event_id,
            user_id=user.id,
            event_type=CoachingEventType.BLOCK_REVIEW.value,
            trigger_source=source,
            flags_that_fired=[f.flag_type for f in active_flags],
            prompt_used=f"coach_block_review.txt@{prompt_sha}",
            llm_model_used=model,
            llm_input=user_prompt,
            llm_output=clean_output,
            llm_input_tokens=metrics.input_tokens if metrics else None,
            llm_output_tokens=metrics.output_tokens if metrics else None,
            llm_cost_usd=cost_usd,
            llm_latency_ms=metrics.latency_ms if metrics else None,
            shadow_mode=(user.coaching_modes or {}).get("block_review", "shadow") != "live",
            context={
                "window_weeks": _BLOCK_WINDOW_WEEKS,
                "next_focuses": next_focuses,
                "had_adjustment_proposal": adjustment is not None,
                "easy_pace_drift": easy_drift,
                "threshold_drift": threshold_drift,
                "goal_alignment": goal_alignment,
            },
        )
        db.add(event)
        await db.flush()

        if outcomes:
            await focus_tracker.apply_outcomes(db, user.id, outcomes, set_by_event_id=event.id)
        if next_focuses:
            await focus_tracker.persist_focuses(db, user.id, raised_in_event_id=event.id, focuses=next_focuses)

        if adjustment:
            try:
                await plan_adjustment_service.propose(
                    db, user,
                    trigger_event_id=event.id,
                    summary=adjustment.get("summary", ""),
                    structured_diff=adjustment.get("structured_diff", {}),
                    affected_workout_dates=adjustment.get("affected_workout_dates"),
                )
            except Exception:
                logger.exception("Failed to propose adjustment from block review event=%s", event.id)

        delivered, reason = await push_service.send_push(
            db, user,
            title="Block review — let's reset",
            body=_summary_for_notification(clean_output),
            deep_link=f"stride://coach/block-review/{event.id}",
            notification_type="block_review",
            loop_name="block_review",
        )
        event.notification_delivered = delivered
        event.notification_reason = reason
        db.add(event)

        await db.commit()
        new_event_id = event.id

    asyncio.create_task(_update_memo_background(user_id, new_event_id, clean_output))
    logger.info(
        "block_review: user=%s event=%s focuses=%d adjustment=%s pushed=%s",
        user_id, new_event_id, len(next_focuses), adjustment is not None, delivered,
    )
    return new_event_id


# ── Skip checks ────────────────────────────────────────────────────────────

async def _has_recent_post_race(db: AsyncSession, user_id: UUID) -> bool:
    cutoff = datetime.now(timezone.utc) - timedelta(days=_POST_RACE_SKIP_DAYS)
    result = await db.execute(
        select(CoachingEvent.id).where(
            CoachingEvent.user_id == user_id,
            CoachingEvent.event_type == CoachingEventType.POST_RACE.value,
            CoachingEvent.triggered_at >= cutoff,
        ).limit(1)
    )
    return result.scalar_one_or_none() is not None


async def _in_race_prep_window(db: AsyncSession, user_id: UUID) -> bool:
    now = datetime.now(timezone.utc)
    cutoff = now + timedelta(days=_RACE_PREP_SKIP_DAYS)
    result = await db.execute(
        select(Event.starts_at)
        .join(EventRegistration, EventRegistration.event_id == Event.id)
        .where(
            EventRegistration.user_id == user_id,
            Event.starts_at >= now,
            Event.starts_at <= cutoff,
            Event.is_active.is_(True),
        )
        .limit(1)
    )
    return result.scalar_one_or_none() is not None


def _log_skip(db: AsyncSession, user: User, reason: str) -> None:
    event = CoachingEvent(
        user_id=user.id,
        event_type=CoachingEventType.BLOCK_REVIEW.value,
        trigger_source=CoachingEventTriggerSource.CRON.value,
        flags_that_fired=[],
        notification_delivered=False,
        notification_reason=f"skipped:{reason}",
        shadow_mode=True,
        context={"skip_reason": reason},
    )
    db.add(event)


# ── Context loaders ────────────────────────────────────────────────────────

async def _fetch_runs(db: AsyncSession, user_id: UUID, weeks: int) -> list[Run]:
    cutoff = datetime.now(timezone.utc) - timedelta(weeks=weeks)
    result = await db.execute(
        select(Run)
        .where(Run.user_id == user_id, Run.completed_at >= cutoff)
        .order_by(Run.completed_at)
    )
    return list(result.scalars().all())


async def _fetch_prior_weekly_reviews(db: AsyncSession, user_id: UUID, count: int) -> list[CoachingEvent]:
    result = await db.execute(
        select(CoachingEvent)
        .where(
            CoachingEvent.user_id == user_id,
            CoachingEvent.event_type == CoachingEventType.WEEKLY_REVIEW.value,
            CoachingEvent.llm_output.is_not(None),
        )
        .order_by(desc(CoachingEvent.triggered_at))
        .limit(count)
    )
    return list(result.scalars().all())


async def _fetch_active_flags(db: AsyncSession, user_id: UUID) -> list[AnomalyFlag]:
    result = await db.execute(
        select(AnomalyFlag)
        .where(AnomalyFlag.user_id == user_id, AnomalyFlag.resolved_at.is_(None))
        .order_by(desc(AnomalyFlag.raised_at))
        .limit(20)
    )
    return list(result.scalars().all())


def _resolve_race_type(user: User) -> RaceType:
    raw = getattr(user, "current_race_type", None)
    if raw:
        try:
            return RaceType(raw)
        except ValueError:
            pass
    return RaceType.MARATHON


# ── Prompt input ───────────────────────────────────────────────────────────

def _build_user_prompt(
    *,
    user: User,
    runs: list[Run],
    prior_reviews: list[CoachingEvent],
    active_focuses: list[WeeklyFocus],
    active_flags: list[AnomalyFlag],
    wellness_trends: dict,
    easy_drift: Optional[dict],
    threshold_drift: Optional[dict],
    goal_alignment: Optional[dict],
) -> str:
    sections: list[str] = []
    sections.append(f"BLOCK WINDOW: last {_BLOCK_WINDOW_WEEKS} weeks ending today")
    sections.append(f"ATHLETE: {user.name or user.display_name or 'Athlete'}")
    sections.append(f"GOAL RACE: {getattr(user, 'current_race_type', None) or 'marathon'}")

    # Volume per week summary
    sections.append("\nWEEKLY VOLUMES (most recent first)")
    weekly = _bucket_runs_by_week(runs)
    for week_label, total_km in weekly[:_BLOCK_WINDOW_WEEKS]:
        sections.append(f"  {week_label}: {total_km:.1f} km")

    # Pace recalibration
    sections.append("\nPACE RECALIBRATION (compare current 4 weeks vs prior 4 weeks)")
    sections.append(f"  easy: {easy_drift or '(insufficient data)'}")
    sections.append(f"  threshold: {threshold_drift or '(insufficient data)'}")

    # Goal alignment
    sections.append("\nGOAL ALIGNMENT (Garmin race predictor vs goal)")
    if goal_alignment:
        sections.append(f"  predictor_seconds: {goal_alignment['predictor_seconds']}")
        sections.append(f"  goal_seconds: {goal_alignment['goal_seconds']}")
        sections.append(f"  delta_pct: {goal_alignment['delta_pct']}%  (negative = faster than goal)")
        sections.append(f"  on_track: {goal_alignment['on_track']}")
    else:
        sections.append("  (no goal time stored, or no Garmin race predictor available)")

    # Recovery + wellness summary
    if wellness_trends and wellness_trends.get("current", {}).get("n", 0) > 0:
        cur = wellness_trends["current"]
        sections.append("\nWELLNESS (last 28d)")
        for k in ("sleep_quality_avg", "soreness_avg", "motivation_avg", "stress_avg"):
            v = cur.get(k)
            if v is not None:
                sections.append(f"  {k}: {v}")

    # Active flags
    if active_flags:
        sections.append("\nACTIVE FLAGS")
        for f in active_flags:
            sections.append(f"  - {f.flag_type} ({f.severity})")

    # Active focuses
    if active_focuses:
        sections.append("\nACTIVE FOCUSES (carrying in from prior reviews)")
        sections.append(focus_tracker.format_focuses_for_prompt(active_focuses))

    # Prior reviews
    if prior_reviews:
        sections.append("\nPRIOR WEEKLY REVIEWS (last 4, oldest first)")
        for r in reversed(prior_reviews):
            date_s = r.triggered_at.strftime("%Y-%m-%d")
            body = (r.llm_output or "")[:300].replace("\n", " ")
            sections.append(f"  --- {date_s} ---\n  {body}")

    sections.append("\n— end of context —\n\nWrite the block review now.")
    return "\n".join(sections)


def _bucket_runs_by_week(runs: list[Run]) -> list[tuple[str, float]]:
    """Group runs into weekly buckets (Mon-Sun ending today). Most recent first."""
    today = datetime.now(timezone.utc).date()
    days_since_sunday = (today.weekday() + 1) % 7
    most_recent_sunday = today - timedelta(days=days_since_sunday)

    buckets: dict[str, float] = {}
    for r in runs:
        if not r.completed_at:
            continue
        d = r.completed_at.date()
        # Find which week this belongs to (Mon-Sun ending on the Sunday at-or-after d)
        days_after = (6 - d.weekday()) % 7  # Mon=0..Sun=6
        sunday = d + timedelta(days=days_after)
        if sunday > most_recent_sunday:
            sunday = most_recent_sunday
        key = sunday.isoformat()
        buckets[key] = buckets.get(key, 0.0) + float(r.distance_km or 0)

    return sorted(buckets.items(), key=lambda kv: kv[0], reverse=True)


def _summary_for_notification(text: str) -> str:
    if not text:
        return "Tap to read your block review."
    line = text.split("\n", 1)[0].strip()
    return (line[:107].rstrip() + "…") if len(line) > 110 else line


async def _update_memo_background(user_id: UUID, triggering_event_id: UUID, review_output: str) -> None:
    try:
        async with async_session() as db:
            await coach_memo_service.update_memo(
                db, user_id, triggering_event_id, review_output,
                summary_range={"block_review_event_id": str(triggering_event_id)},
            )
            await db.commit()
    except Exception:
        logger.exception("Background memo update failed for user=%s", user_id)
