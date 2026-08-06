"""
Generate race-day logistics checklist via Opus call to coach_race_logistics.txt.
Persists as RaceLogisticsChecklist (one per user per event — regenerating
replaces). Pulls weather + course intel from existing services where available.
"""

import json
import logging
import re
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session
from app.models.coaching_event import (
    CoachingEvent,
    CoachingEventTriggerSource,
    CoachingEventType,
)
from app.models.event import Event, EventRegistration
from app.models.race_logistics_checklist import RaceLogisticsChecklist
from app.models.user import User
from app.services import coach_memo_service, coaching_models, push_service
from app.services.anthropic_client import AnthropicClient
from app.services.prompt_builder import prompt_builder
from app.services.weather_service import fetch_weather

logger = logging.getLogger(__name__)


async def generate_checklist(
    user_id: UUID,
    event_id: UUID,
    *,
    source: str = CoachingEventTriggerSource.MANUAL.value,
) -> Optional[UUID]:
    """Generate (or regenerate) the logistics checklist. Returns the row ID or None on failure."""
    async with async_session() as db:
        user = await db.get(User, user_id)
        event = await db.get(Event, event_id)
        if user is None or event is None:
            logger.warning("generate_checklist: missing user or event")
            return None

        # Verify the athlete is registered
        reg_q = await db.execute(
            select(EventRegistration.id).where(
                EventRegistration.user_id == user.id,
                EventRegistration.event_id == event.id,
            ).limit(1)
        )
        if reg_q.scalar_one_or_none() is None:
            logger.warning("generate_checklist: user %s not registered for event %s", user_id, event_id)
            return None

        weather = await _fetch_weather_safe(event)
        memo = await coach_memo_service.get_memo_text(db, user.id)
        race_type = _resolve_race_type(user)

        user_prompt = _build_user_prompt(user=user, event=event, weather=weather)
        system_prompt = prompt_builder.get_race_logistics_prompt(race_type, memo=memo)

        client = AnthropicClient()
        model = coaching_models.RACE_LOGISTICS_MODEL
        try:
            output_text = await client.generate_plan(
                system_prompt,
                user_prompt,
                name="race-logistics-checklist",
                user_id=str(user.id),
                metadata={"event_id": str(event.id)},
                model=model,
            )
        except Exception:
            logger.exception("Race logistics LLM call failed user=%s event=%s", user_id, event_id)
            return None

        metrics = client.last_metrics
        parsed = _safe_parse_json(output_text)
        if parsed is None:
            return None

        # Upsert the row
        items = parsed.get("items") or []
        stmt = pg_insert(RaceLogisticsChecklist).values(
            user_id=user.id,
            event_id=event.id,
            generated_at=datetime.now(timezone.utc),
            items=items,
            weather_forecast=weather,
            course_intel=None,
        ).on_conflict_do_update(
            constraint="uq_race_logistics_user_event",
            set_={
                "generated_at": datetime.now(timezone.utc),
                "items": items,
                "weather_forecast": weather,
            },
        ).returning(RaceLogisticsChecklist)
        row = (await db.execute(stmt)).scalar_one()

        # Audit
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
            prompt_used=f"coach_race_logistics.txt@{prompt_builder.prompt_sha('coach_race_logistics.txt')}",
            llm_model_used=model,
            llm_input=user_prompt,
            llm_output=output_text,
            llm_input_tokens=metrics.input_tokens if metrics else None,
            llm_output_tokens=metrics.output_tokens if metrics else None,
            llm_cost_usd=cost,
            llm_latency_ms=metrics.latency_ms if metrics else None,
            shadow_mode=False,
            context={"event_id": str(event.id), "checklist_id": str(row.id), "item_count": len(items)},
            idempotency_key=f"race_logistics:{user.id}:{event.id}:{datetime.now(timezone.utc).date().isoformat()}",
        )
        db.add(event_row)
        await db.flush()

        # Push
        delivered, reason = await push_service.send_push(
            db, user,
            title="Race logistics checklist ready",
            body=f"Your checklist for {event.title} just landed.",
            deep_link=f"stride://race-prep/checklist/{event.id}",
            notification_type="race_logistics_generated",
            loop_name="race_prep",
        )
        event_row.notification_delivered = delivered
        event_row.notification_reason = reason
        db.add(event_row)

        await db.commit()
        return row.id


# ── Helpers ────────────────────────────────────────────────────────────────

async def _fetch_weather_safe(event: Event) -> Optional[dict]:
    lat = getattr(event, "lat", None)
    lon = getattr(event, "lon", None)
    if lat is None or lon is None:
        return None
    return await fetch_weather(float(lat), float(lon), event.starts_at.date())


def _build_user_prompt(*, user: User, event: Event, weather: Optional[dict]) -> str:
    lines = [
        f"RACE: {event.title}",
        f"Distance: {event.distance_km} km" if event.distance_km else "Distance: unknown",
        f"Start: {event.starts_at.isoformat() if event.starts_at else 'unknown'}",
        f"Athlete: {user.name or user.display_name or 'Athlete'}",
    ]
    bw = getattr(user, "body_weight_kg", None)
    if bw:
        lines.append(f"Body weight: {bw} kg")

    if weather:
        lines.append("\nWEATHER FORECAST")
        for k, v in weather.items():
            if v is not None:
                lines.append(f"  {k}: {v}")
    else:
        lines.append("\nWEATHER FORECAST: not available — give weather-agnostic guidance")

    lines.append("\nGenerate the strict-JSON logistics checklist now.")
    return "\n".join(lines)


def _safe_parse_json(raw: str) -> Optional[dict]:
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
    return parsed if isinstance(parsed, dict) else None


def _resolve_race_type(user: User):
    from app.models.schemas import RaceType
    raw = getattr(user, "current_race_type", None)
    if raw:
        try:
            return RaceType(raw)
        except ValueError:
            pass
    return RaceType.MARATHON
