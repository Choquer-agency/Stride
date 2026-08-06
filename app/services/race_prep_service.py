"""
Race-prep coaching loop. Replaces the weekly review during the final 28 days
before a registered race. Tone shifts to confidence-building + sharpening.

Two flavors:
  - run_taper_entry: one-time message fired at exactly race-28d. Welcomes the
    athlete to taper + auto-generates the logistics checklist.
  - run_race_prep_review: weekly cadence (Sunday 8 PM PT) within the window.
    Same shape as the weekly review but uses coach_race_prep.txt prompt.
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
from app.models.run import Run
from app.models.schemas import RaceType
from app.models.user import User
from app.models.weekly_focus import WeeklyFocus
from app.services import (
    coach_memo_service,
    coaching_models,
    focus_tracker,
    plan_adjustment_service,
    push_service,
    race_logistics_service,
    wellness_service,
)
from app.services.anthropic_client import AnthropicClient
from app.services.prompt_builder import prompt_builder

logger = logging.getLogger(__name__)


_RACE_PREP_DAYS = 28


# ── Public ─────────────────────────────────────────────────────────────────

async def is_in_race_prep_window(db: AsyncSession, user_id: UUID) -> Optional[Event]:
    """Returns the Event the athlete is in race-prep for, or None."""
    now = datetime.now(timezone.utc)
    cutoff = now + timedelta(days=_RACE_PREP_DAYS)
    result = await db.execute(
        select(Event)
        .join(EventRegistration, EventRegistration.event_id == Event.id)
        .where(
            EventRegistration.user_id == user_id,
            Event.starts_at >= now,
            Event.starts_at <= cutoff,
            Event.is_active.is_(True),
        )
        .order_by(Event.starts_at)
        .limit(1)
    )
    return result.scalar_one_or_none()


async def run_taper_entry(
    user_id: UUID,
    event_id: UUID,
    *,
    source: str = CoachingEventTriggerSource.CRON.value,
) -> Optional[UUID]:
    """
    Fires once at race-28d. "Welcome to taper" event + kick off the logistics
    checklist generation. Idempotent on (user_id, event_id) — won't fire twice
    for the same race.
    """
    async with async_session() as db:
        user = await db.get(User, user_id)
        event = await db.get(Event, event_id)
        if user is None or event is None:
            return None

        # Idempotency check via coaching_events
        idempotency_key = f"taper_entry:{user_id}:{event_id}"
        existing = await db.execute(
            select(CoachingEvent.id).where(CoachingEvent.idempotency_key == idempotency_key).limit(1)
        )
        if existing.scalar_one_or_none() is not None:
            logger.info("taper_entry already fired for user=%s event=%s", user_id, event_id)
            return None

        days_to_race = (event.starts_at.date() - datetime.now(timezone.utc).date()).days

        memo = await coach_memo_service.get_memo_text(db, user.id)
        race_type = _resolve_race_type(user)

        user_prompt = (
            f"TAPER ENTRY — race in {days_to_race} days\n"
            f"Race: {event.title}\n"
            f"Distance: {event.distance_km} km\n"
            f"Athlete: {user.name or 'Athlete'}\n\n"
            f"Write the welcome-to-taper message. Short. Set the tone for the next 4 weeks. "
            f"Reference the work that got them here. End with one focus tag for this week."
        )
        system_prompt = prompt_builder.get_race_prep_prompt(race_type, memo=memo)

        client = AnthropicClient()
        model = coaching_models.RACE_PREP_MODEL
        try:
            output_text = await client.generate_plan(
                system_prompt, user_prompt,
                name="taper-entry",
                user_id=str(user.id),
                metadata={"event_id": str(event.id)},
                model=model,
            )
        except Exception:
            logger.exception("Taper entry LLM call failed user=%s event=%s", user_id, event_id)
            return None

        metrics = client.last_metrics
        next_focuses = focus_tracker.parse_focuses(output_text)
        clean_output = focus_tracker.strip_tags(output_text)

        cost = coaching_models.estimate_cost_usd(
            model, metrics.input_tokens or 0 if metrics else 0,
            metrics.output_tokens or 0 if metrics else 0,
        )

        event_id_new = uuid4()
        coaching_event = CoachingEvent(
            id=event_id_new,
            user_id=user.id,
            event_type=CoachingEventType.RACE_PREP_ENTRY.value,
            trigger_source=source,
            flags_that_fired=[],
            prompt_used=f"coach_race_prep.txt@{prompt_builder.prompt_sha('coach_race_prep.txt')}",
            llm_model_used=model,
            llm_input=user_prompt,
            llm_output=clean_output,
            llm_input_tokens=metrics.input_tokens if metrics else None,
            llm_output_tokens=metrics.output_tokens if metrics else None,
            llm_cost_usd=cost,
            llm_latency_ms=metrics.latency_ms if metrics else None,
            shadow_mode=False,
            idempotency_key=idempotency_key,
            context={"event_id": str(event.id), "days_to_race": days_to_race, "next_focuses": next_focuses},
        )
        db.add(coaching_event)
        await db.flush()

        if next_focuses:
            await focus_tracker.persist_focuses(db, user.id, raised_in_event_id=coaching_event.id, focuses=next_focuses)

        delivered, reason = await push_service.send_push(
            db, user,
            title=f"Welcome to taper — {days_to_race} days out",
            body=_summary_for_notification(clean_output),
            deep_link=f"stride://race-prep/checklist/{event.id}",
            notification_type="race_prep_entry",
            loop_name="race_prep",
        )
        coaching_event.notification_delivered = delivered
        coaching_event.notification_reason = reason
        db.add(coaching_event)

        await db.commit()

    # Kick off logistics checklist generation in background
    asyncio.create_task(race_logistics_service.generate_checklist(user_id, event_id, source=source))

    logger.info("taper_entry fired: user=%s event=%s focuses=%d", user_id, event_id, len(next_focuses))
    return event_id_new


async def run_race_prep_review(
    user_id: UUID,
    *,
    source: str = CoachingEventTriggerSource.CRON.value,
    force: bool = False,
) -> Optional[UUID]:
    """Weekly race-prep review (Sunday 8 PM PT during the 28-day window)."""
    async with async_session() as db:
        user = await db.get(User, user_id)
        if user is None:
            return None

        event = await is_in_race_prep_window(db, user.id)
        if event is None and not force:
            return None
        if event is None:
            # Force mode without an actual race — bail
            return None

        days_to_race = (event.starts_at.date() - datetime.now(timezone.utc).date()).days
        memo = await coach_memo_service.get_memo_text(db, user.id)
        race_type = _resolve_race_type(user)

        runs = await _recent_runs(db, user.id, weeks=2)
        active_focuses = await focus_tracker.get_active_focuses(db, user.id, weeks_back=2)
        active_flags = await _active_flags(db, user.id)
        wellness_trends = await wellness_service.compute_trends(db, user.id, window_days=7)

        user_prompt = _build_review_prompt(
            user=user,
            event=event,
            days_to_race=days_to_race,
            runs=runs,
            active_focuses=active_focuses,
            active_flags=active_flags,
            wellness_trends=wellness_trends,
        )
        system_prompt = prompt_builder.get_race_prep_prompt(race_type, memo=memo)

        client = AnthropicClient()
        model = coaching_models.RACE_PREP_MODEL
        try:
            output_text = await client.generate_plan(
                system_prompt, user_prompt,
                name="race-prep-review",
                user_id=str(user.id),
                metadata={"event_id": str(event.id), "days_to_race": days_to_race},
                model=model,
            )
        except Exception:
            logger.exception("Race-prep review LLM call failed user=%s", user_id)
            return None

        metrics = client.last_metrics
        next_focuses = focus_tracker.parse_focuses(output_text)
        outcomes = focus_tracker.parse_focus_outcomes(output_text)
        adjustment = focus_tracker.parse_adjustment(output_text)
        clean_output = focus_tracker.strip_tags(output_text)

        cost = coaching_models.estimate_cost_usd(
            model, metrics.input_tokens if metrics else 0, metrics.output_tokens if metrics else 0,
        )
        event_id_new = uuid4()
        coaching_event = CoachingEvent(
            id=event_id_new,
            user_id=user.id,
            event_type=CoachingEventType.RACE_PREP_REVIEW.value,
            trigger_source=source,
            flags_that_fired=[f.flag_type for f in active_flags],
            prompt_used=f"coach_race_prep.txt@{prompt_builder.prompt_sha('coach_race_prep.txt')}",
            llm_model_used=model,
            llm_input=user_prompt,
            llm_output=clean_output,
            llm_input_tokens=metrics.input_tokens if metrics else None,
            llm_output_tokens=metrics.output_tokens if metrics else None,
            llm_cost_usd=cost,
            llm_latency_ms=metrics.latency_ms if metrics else None,
            shadow_mode=(user.coaching_modes or {}).get("race_prep", "shadow") != "live",
            context={"event_id": str(event.id), "days_to_race": days_to_race, "next_focuses": next_focuses},
        )
        db.add(coaching_event)
        await db.flush()

        if outcomes:
            await focus_tracker.apply_outcomes(db, user.id, outcomes, set_by_event_id=coaching_event.id)
        if next_focuses:
            await focus_tracker.persist_focuses(db, user.id, raised_in_event_id=coaching_event.id, focuses=next_focuses)
        if adjustment:
            try:
                await plan_adjustment_service.propose(
                    db, user,
                    trigger_event_id=coaching_event.id,
                    summary=adjustment.get("summary", ""),
                    structured_diff=adjustment.get("structured_diff", {}),
                    affected_workout_dates=adjustment.get("affected_workout_dates"),
                )
            except Exception:
                logger.exception("Failed to propose adjustment from race-prep review")

        delivered, reason = await push_service.send_push(
            db, user,
            title=f"Race week minus {days_to_race // 7} — sharpening note",
            body=_summary_for_notification(clean_output),
            deep_link=f"stride://race-prep/review/{coaching_event.id}",
            notification_type="race_prep_review",
            loop_name="race_prep",
        )
        coaching_event.notification_delivered = delivered
        coaching_event.notification_reason = reason
        db.add(coaching_event)

        await db.commit()
        return event_id_new


# ── Internals ──────────────────────────────────────────────────────────────

async def _recent_runs(db: AsyncSession, user_id: UUID, *, weeks: int) -> list[Run]:
    cutoff = datetime.now(timezone.utc) - timedelta(weeks=weeks)
    result = await db.execute(
        select(Run).where(Run.user_id == user_id, Run.completed_at >= cutoff).order_by(Run.completed_at)
    )
    return list(result.scalars().all())


async def _active_flags(db: AsyncSession, user_id: UUID) -> list[AnomalyFlag]:
    result = await db.execute(
        select(AnomalyFlag).where(
            AnomalyFlag.user_id == user_id,
            AnomalyFlag.resolved_at.is_(None),
        ).order_by(desc(AnomalyFlag.raised_at)).limit(10)
    )
    return list(result.scalars().all())


def _build_review_prompt(
    *,
    user: User,
    event: Event,
    days_to_race: int,
    runs: list[Run],
    active_focuses: list[WeeklyFocus],
    active_flags: list[AnomalyFlag],
    wellness_trends: dict,
) -> str:
    sections = [
        f"RACE-PREP REVIEW — {days_to_race} days out",
        f"Race: {event.title} ({event.distance_km} km)",
        f"Athlete: {user.name or 'Athlete'}",
    ]

    if runs:
        sections.append(f"\nLAST 14 DAYS RUNS ({len(runs)})")
        for r in runs[-14:]:
            date = r.completed_at.strftime("%Y-%m-%d") if r.completed_at else "?"
            ptype = r.planned_workout_type or "—"
            dist = f"{r.distance_km:.1f}km" if r.distance_km else "—"
            sections.append(f"  {date} | {ptype} | {dist}")

    if wellness_trends and wellness_trends.get("current", {}).get("n", 0) > 0:
        cur = wellness_trends["current"]
        sections.append("\nWELLNESS (last 7d)")
        for k in ("sleep_quality_avg", "soreness_avg", "motivation_avg", "stress_avg"):
            v = cur.get(k)
            if v is not None:
                sections.append(f"  {k}: {v}")

    if active_flags:
        sections.append("\nACTIVE FLAGS")
        for f in active_flags:
            sections.append(f"  - {f.flag_type} ({f.severity})")

    if active_focuses:
        sections.append("\nACTIVE FOCUSES")
        sections.append(focus_tracker.format_focuses_for_prompt(active_focuses))

    sections.append("\n— end of context —\n\nWrite the race-prep review now.")
    return "\n".join(sections)


def _summary_for_notification(text: str) -> str:
    if not text:
        return "Tap to read your coach's note."
    line = text.split("\n", 1)[0].strip()
    return (line[:107].rstrip() + "…") if len(line) > 110 else line


def _resolve_race_type(user: User) -> RaceType:
    raw = getattr(user, "current_race_type", None)
    if raw:
        try:
            return RaceType(raw)
        except ValueError:
            pass
    return RaceType.MARATHON
