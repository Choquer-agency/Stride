"""
Race fueling plan generator. Fired automatically 14 days before any registered
race via the race_fueling_plan_trigger_job cron, or manually via the API.

Pipeline:
  1. Pull race details (distance, expected duration from goal time)
  2. Pull athlete training nutrition patterns (avg carb intake/hr during long runs)
  3. Pull weather forecast for race day (NWS — may be None for non-US or >7d out)
  4. Pull course profile from event metadata (may be None)
  5. Opus call with coach_race_fueling.txt → strict JSON, 4 phases
  6. Persist RaceFuelingPlan + push notification + log coaching_event
"""

import json
import logging
import re
import statistics
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session
from app.models.coaching_event import (
    CoachingEvent,
    CoachingEventTriggerSource,
    CoachingEventType,
)
from app.models.event import Event, EventRegistration
from app.models.garmin_workout import ACTIVITY_BUCKET_RUNNING, GarminWorkout
from app.models.race_fueling_plan import RaceFuelingPlan
from app.models.user import User
from app.services import coach_memo_service, coaching_models, push_service
from app.services.anthropic_client import AnthropicClient
from app.services.prompt_builder import prompt_builder
from app.services.weather_service import fetch_weather

logger = logging.getLogger(__name__)


_FOUR_PHASES = ("three_days_before", "race_morning", "during_race", "post_race")


# ── Public entry points ─────────────────────────────────────────────────────

async def generate_plan(
    user_id: UUID,
    event_id: UUID,
    *,
    source: str = CoachingEventTriggerSource.MANUAL.value,
) -> Optional[UUID]:
    """
    Generate (or regenerate) a race fueling plan. Opens its own DB session so
    cron + manual triggers can fire-and-forget.
    Returns the new RaceFuelingPlan.id or None on failure.
    """
    async with async_session() as db:
        user = await db.get(User, user_id)
        event = await db.get(Event, event_id)
        if user is None or event is None:
            logger.warning("generate_plan: user or event missing (user=%s event=%s)", user_id, event_id)
            return None

        # Verify the athlete is actually registered for this race
        reg_q = await db.execute(
            select(EventRegistration.id).where(
                EventRegistration.user_id == user.id,
                EventRegistration.event_id == event.id,
            ).limit(1)
        )
        if reg_q.scalar_one_or_none() is None:
            logger.warning("generate_plan: user %s not registered for event %s", user_id, event_id)
            return None

        # Build inputs
        weather = await _fetch_weather_safe(event)
        training_carb_pattern = await _avg_training_carb_intake_per_hour(db, user.id)
        memo = await coach_memo_service.get_memo_text(db, user.id)

        user_prompt = _build_user_prompt(
            user=user,
            event=event,
            weather=weather,
            training_carb_pattern=training_carb_pattern,
        )
        race_type = _resolve_race_type(user)
        system_prompt = prompt_builder.get_race_fueling_prompt(race_type, memo=memo)

        client = AnthropicClient()
        model = coaching_models.RACE_FUELING_MODEL
        try:
            output_text = await client.generate_plan(
                system_prompt,
                user_prompt,
                name="race-fueling-plan",
                user_id=str(user.id),
                session_id=f"user:{user.id}:race-fueling:{event.id}",
                metadata={"event_id": str(event.id)},
                model=model,
            )
        except Exception:
            logger.exception("Race fueling LLM call failed user=%s event=%s", user_id, event_id)
            return None

        metrics = client.last_metrics

        plan_dict = _safe_parse_phases(output_text)
        if plan_dict is None:
            logger.warning("Race fueling output didn't parse — user=%s event=%s", user_id, event_id)
            return None

        # Persist
        row = RaceFuelingPlan(
            user_id=user.id,
            event_id=event.id,
            three_days_before=plan_dict.get("three_days_before") or {},
            race_morning=plan_dict.get("race_morning") or {},
            during_race=plan_dict.get("during_race") or {},
            post_race=plan_dict.get("post_race") or {},
            weather_forecast=weather,
            course_notes=None,
            athlete_edits={},
        )
        db.add(row)
        await db.flush()

        # Audit event
        cost = coaching_models.estimate_cost_usd(
            model,
            metrics.input_tokens if metrics else 0,
            metrics.output_tokens if metrics else 0,
        )
        event_row = CoachingEvent(
            user_id=user.id,
            event_type=CoachingEventType.RACE_LOGISTICS_GENERATED.value,
            trigger_source=source,
            flags_that_fired=[],
            prompt_used=f"coach_race_fueling.txt@{prompt_builder.prompt_sha('coach_race_fueling.txt')}",
            llm_model_used=model,
            llm_input=user_prompt,
            llm_output=output_text,
            llm_input_tokens=metrics.input_tokens if metrics else None,
            llm_output_tokens=metrics.output_tokens if metrics else None,
            llm_cost_usd=cost,
            llm_latency_ms=metrics.latency_ms if metrics else None,
            shadow_mode=False,
            context={"event_id": str(event.id), "race_fueling_plan_id": str(row.id)},
            idempotency_key=f"race_fueling:{user.id}:{event.id}",
        )
        db.add(event_row)
        await db.flush()

        # Push
        delivered, reason = await push_service.send_push(
            db, user,
            title="Race fueling plan ready",
            body=f"Your plan for {event.title} just landed. Review it.",
            deep_link=f"stride://race-prep/checklist/{event.id}",
            notification_type="race_fueling_plan",
            loop_name="race_prep",
        )
        event_row.notification_delivered = delivered
        event_row.notification_reason = reason
        db.add(event_row)

        await db.commit()
        logger.info(
            "Race fueling plan generated: user=%s event=%s plan=%s",
            user.id, event.id, row.id,
        )
        return row.id


# ── Helpers ────────────────────────────────────────────────────────────────

async def _fetch_weather_safe(event: Event) -> Optional[dict]:
    """Pull weather for race day if we have lat/lon (currently we don't store
    these on Event, so this returns None until that's added). Hooked here so
    the wiring is in place for when Event gains lat/lon columns."""
    lat = getattr(event, "lat", None)
    lon = getattr(event, "lon", None)
    if lat is None or lon is None:
        return None
    return await fetch_weather(float(lat), float(lon), event.starts_at.date())


async def _avg_training_carb_intake_per_hour(db: AsyncSession, user_id: UUID) -> Optional[float]:
    """
    Approximate the athlete's typical during-run carb intake by summing
    nutrition_logs flagged with related_workout_id over the last 90 days,
    divided by total run duration. Returns None if no data — race plan
    will use distance-based defaults instead.
    """
    # Stub for v2 — proper computation would require linking nutrition_logs
    # to actual workout duration. Phase 6.1 follow-up.
    return None


def _build_user_prompt(
    *,
    user: User,
    event: Event,
    weather: Optional[dict],
    training_carb_pattern: Optional[float],
) -> str:
    lines = [f"RACE: {event.title}"]
    if event.distance_km:
        lines.append(f"Distance: {event.distance_km} km")
    if event.starts_at:
        lines.append(f"Date: {event.starts_at.date().isoformat()}")
    lines.append(f"Athlete: {user.name or user.display_name or 'Athlete'}")
    bw = getattr(user, "body_weight_kg", None)
    if bw:
        lines.append(f"Body weight: {bw} kg")

    if training_carb_pattern is not None:
        lines.append(f"Athlete's training carb intake: ~{training_carb_pattern:.0f} g/hr during long runs")
    else:
        lines.append("Athlete's training carb intake: insufficient data — use distance-based defaults")

    if weather:
        lines.append("\nWEATHER FORECAST")
        for k, v in weather.items():
            if v is not None:
                lines.append(f"  {k}: {v}")
    else:
        lines.append("\nWEATHER FORECAST: not available (treat as moderate conditions)")

    lines.append("\nWrite the four-phase race fueling plan as strict JSON.")
    return "\n".join(lines)


def _safe_parse_phases(raw: str) -> Optional[dict]:
    """Parse the strict JSON response into the 4 expected phase keys."""
    if not raw:
        return None
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
        cleaned = re.sub(r"\s*```\s*$", "", cleaned)
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start == -1 or end == -1:
        return None
    try:
        parsed = json.loads(cleaned[start:end + 1])
    except json.JSONDecodeError:
        return None
    if not isinstance(parsed, dict):
        return None
    if not all(k in parsed for k in _FOUR_PHASES):
        logger.warning("Race fueling output missing phases: keys=%s", list(parsed.keys()))
        return None
    return parsed


def _resolve_race_type(user: User):
    from app.models.schemas import RaceType
    raw = getattr(user, "current_race_type", None)
    if raw:
        try:
            return RaceType(raw)
        except ValueError:
            pass
    return RaceType.MARATHON
