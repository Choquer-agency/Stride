"""
Wellness concern orchestrator — fired when an incoming wellness check-in is
classified as concerning by `wellness_service.is_concerning()`.

Pipeline:
  1. Build user prompt from the entry + recent training/wellness context
  2. Sonnet call against coach_wellness_concern.txt
  3. Parse <followup> + <adjustment> JSON tags
  4. Persist coaching_events (event_type=wellness_concern)
  5. If `is_serious_concern` (soreness ≥ 4), push immediately; otherwise
     surface as a quiet card on Run tab (no push, but inbox gets a row).
  6. If <adjustment> tag present, propose a PlanAdjustment via plan_adjustment_service
"""

import json
import logging
import re
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session
from app.models.coaching_event import (
    CoachingEvent,
    CoachingEventTriggerSource,
    CoachingEventType,
)
from app.models.user import User
from app.models.wellness_checkin import WellnessCheckin
from app.services import (
    coach_memo_service,
    coaching_models,
    plan_adjustment_service,
    push_service,
    wellness_service,
)
from app.services.anthropic_client import AnthropicClient
from app.services.prompt_builder import prompt_builder

logger = logging.getLogger(__name__)


_FOLLOWUP_RE = re.compile(r"<followup>\s*(.*?)\s*</followup>", re.DOTALL)
_ADJUSTMENT_RE = re.compile(r"<adjustment>\s*(.*?)\s*</adjustment>", re.DOTALL)


async def run_wellness_concern_check(user_id: UUID, checkin_id: UUID) -> Optional[UUID]:
    """
    Orchestrate the immediate-ack pipeline. Opens its own session so the
    submit-checkin route can fire-and-forget via asyncio.create_task.
    Returns the new coaching_event id or None if skipped.
    """
    async with async_session() as db:
        user = await db.get(User, user_id)
        checkin = await db.get(WellnessCheckin, checkin_id)
        if not user or not checkin:
            return None

        if not wellness_service.is_concerning(checkin):
            return None

        memo_text = await coach_memo_service.get_memo_text(db, user.id)
        race_type = _resolve_race_type(user)

        user_prompt = await _build_user_prompt(db, user, checkin)
        system_prompt = prompt_builder.get_wellness_concern_prompt(race_type, memo=memo_text)
        model = coaching_models.WELLNESS_CONCERN_MODEL

        client = AnthropicClient()
        try:
            output_text = await client.generate_plan(
                system_prompt,
                user_prompt,
                name="wellness-concern",
                user_id=str(user.id),
                metadata={"checkin_id": str(checkin.id)},
                model=model,
            )
        except Exception:
            logger.exception("wellness_concern LLM call failed for user=%s", user_id)
            return None

        metrics = client.last_metrics

        # Parse tags
        followup = _parse_first_json_tag(output_text, _FOLLOWUP_RE)
        adjustment = _parse_first_json_tag(output_text, _ADJUSTMENT_RE)
        clean_output = _ADJUSTMENT_RE.sub("", _FOLLOWUP_RE.sub("", output_text)).strip()

        # Persist coaching_events row
        cost_usd = coaching_models.estimate_cost_usd(
            model,
            metrics.input_tokens if metrics else 0,
            metrics.output_tokens if metrics else 0,
        )
        prompt_sha = prompt_builder.prompt_sha("coach_wellness_concern.txt")
        event_id = uuid4()

        event = CoachingEvent(
            id=event_id,
            user_id=user.id,
            event_type=CoachingEventType.WELLNESS_CONCERN.value,
            trigger_source=CoachingEventTriggerSource.USER_ACTION.value,
            flags_that_fired=["wellness_concern"],
            prompt_used=f"coach_wellness_concern.txt@{prompt_sha}",
            llm_model_used=model,
            llm_input=user_prompt,
            llm_output=clean_output,
            llm_input_tokens=metrics.input_tokens if metrics else None,
            llm_output_tokens=metrics.output_tokens if metrics else None,
            llm_cost_usd=cost_usd,
            llm_latency_ms=metrics.latency_ms if metrics else None,
            shadow_mode=(user.coaching_modes or {}).get("wellness", "shadow") != "live",
            context={
                "checkin_id": str(checkin.id),
                "soreness": checkin.soreness,
                "motivation": checkin.motivation,
                "sleep_quality": checkin.sleep_quality,
                "stress": checkin.stress,
                "soreness_areas": checkin.soreness_areas or [],
                "had_pain_keyword": wellness_service.concern_keywords_match(checkin.notes)["has_pain_word"],
                "followup_question": followup.get("question") if followup else None,
                "had_adjustment_proposal": adjustment is not None,
            },
        )
        db.add(event)
        await db.flush()

        # Adjustment branch
        deep_link = f"stride://wellness/concern/{event_id}"
        if adjustment:
            try:
                adj = await plan_adjustment_service.propose(
                    db, user,
                    trigger_event_id=event_id,
                    summary=adjustment.get("summary", ""),
                    structured_diff=adjustment.get("structured_diff", {}),
                    affected_workout_dates=adjustment.get("affected_workout_dates"),
                )
                deep_link = f"stride://coach/adjustment/{adj.id}"
            except Exception:
                logger.exception("Failed to propose adjustment from wellness_concern event=%s", event_id)

        # Push only on serious concerns (soreness ≥ 4)
        if wellness_service.is_serious_concern(checkin):
            delivered, reason = await push_service.send_push(
                db, user,
                title="Quick check-in",
                body=_summary_for_notification(clean_output),
                deep_link=deep_link,
                notification_type="wellness_concern",
                loop_name="wellness",
            )
            event.notification_delivered = delivered
            event.notification_reason = reason
        else:
            event.notification_delivered = False
            event.notification_reason = "low_severity:no_push"
        db.add(event)

        await db.commit()
        logger.info(
            "wellness_concern: user=%s checkin=%s event=%s soreness=%s push=%s",
            user.id, checkin.id, event_id, checkin.soreness, event.notification_delivered,
        )
        return event_id


# ── Helpers ────────────────────────────────────────────────────────────────

def _parse_first_json_tag(text: str, pattern: re.Pattern) -> Optional[dict]:
    if not text:
        return None
    m = pattern.search(text)
    if not m:
        return None
    try:
        parsed = json.loads(m.group(1))
        return parsed if isinstance(parsed, dict) else None
    except (json.JSONDecodeError, ValueError):
        return None


async def _build_user_prompt(db: AsyncSession, user: User, checkin: WellnessCheckin) -> str:
    lines = ["JUST-SUBMITTED WELLNESS CHECK-IN"]
    lines.append(f"  Method: {checkin.entry_method}")
    lines.append(f"  Date: {checkin.date.isoformat() if checkin.date else '?'}")
    lines.append(f"  Sleep quality: {checkin.sleep_quality or '—'} / 5")
    lines.append(f"  Soreness: {checkin.soreness or '—'} / 5")
    lines.append(f"  Motivation: {checkin.motivation or '—'} / 5")
    lines.append(f"  Stress: {checkin.stress or '—'} / 5")
    if checkin.energy is not None:
        lines.append(f"  Energy: {checkin.energy} / 5")
    if checkin.soreness_areas:
        lines.append(f"  Body areas: {', '.join(checkin.soreness_areas)}")
    if checkin.notes:
        lines.append(f"  Notes: {checkin.notes!r}")

    keywords = wellness_service.concern_keywords_match(checkin.notes)
    if keywords["has_pain_word"]:
        lines.append(f"  Pain words detected: {keywords['matched_pain']}")
    if keywords["has_body_part"]:
        lines.append(f"  Body parts detected in notes: {keywords['matched_body']}")

    # 7-day wellness trend for context
    trends = await wellness_service.compute_trends(db, user.id, window_days=7)
    cur = trends.get("current", {})
    if cur.get("n"):
        lines.append("\n7-DAY WELLNESS TREND")
        lines.append(f"  Soreness avg: {cur.get('soreness_avg')} (delta vs prior week: {trends['deltas'].get('soreness_avg', 0):+})")
        lines.append(f"  Motivation avg: {cur.get('motivation_avg')} (delta: {trends['deltas'].get('motivation_avg', 0):+})")
        lines.append(f"  Sleep avg: {cur.get('sleep_quality_avg')} (delta: {trends['deltas'].get('sleep_quality_avg', 0):+})")
        if cur.get("frequent_soreness_areas"):
            lines.append(f"  Frequent areas: {cur['frequent_soreness_areas']}")
        if cur.get("any_pain_keyword_days"):
            lines.append(f"  Days with pain keywords in past 7d: {cur['any_pain_keyword_days']}")

    lines.append("\nWrite your response. Keep it short. End with optional <followup> and/or <adjustment> JSON tags.")
    return "\n".join(lines)


def _summary_for_notification(text: str) -> str:
    if not text:
        return "Tap to read your coach's response."
    line = text.split("\n", 1)[0].strip()
    return (line[:107].rstrip() + "…") if len(line) > 110 else line


def _resolve_race_type(user: User):
    from app.models.schemas import RaceType
    raw = getattr(user, "current_race_type", None)
    if raw:
        try:
            return RaceType(raw)
        except ValueError:
            pass
    return RaceType.MARATHON
