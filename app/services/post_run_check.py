"""
Post-run check orchestrator — fired by the Garmin webhook after every workout
sync (and exposable as /api/coach/run-post-run-check for admin/debug).

Pipeline:
    if race_event:
        → coach_post_race.txt (Opus) — race recap loop
        return

    flags = anomaly_engine.evaluate_workout(...)
    streak = streak_detector.detect_all(...)

    if no flags + no streak:
        log POST_RUN_INFO event, no LLM, no push
        return

    if streak only:
        Haiku coach_consolidation.txt → push if not paused

    has_critical = critical-combo check
    paused = pause_service.is_paused

    if has_critical:
        Opus coach_red_flag.txt → push (with pause-escalation logic)
    else if paused:
        log info-only, return
    else:
        active = cooldown_service.filter_active_flags(flags)
        if active is empty:
            log info-only (cooled-down)
            return
        Sonnet coach_post_run.txt → push if mode allows

Parses <response>{type:info|check_in|adjustment, ...}</response>:
    info       → no further action
    check_in   → push deep links to chat (Phase 5 wires actual chat)
    adjustment → propose PlanAdjustment + push deep links to AdjustmentReviewSheet
"""

import json
import logging
import re
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session
from app.models.anomaly_flag import AnomalyFlag, FlagSeverity, FlagType
from app.models.coaching_event import (
    CoachingEvent,
    CoachingEventTriggerSource,
    CoachingEventType,
)
from app.models.event import Event
from app.models.garmin_workout import GarminWorkout
from app.models.run import Run
from app.models.user import User
from app.services import (
    anomaly_engine,
    coach_memo_service,
    coaching_models,
    cooldown_service,
    pause_service,
    plan_adjustment_service,
    push_service,
    streak_detector,
)
from app.services.anthropic_client import AnthropicClient
from app.services.prompt_builder import prompt_builder

logger = logging.getLogger(__name__)


_RESPONSE_TAG_RE = re.compile(r"<response>\s*(.*?)\s*</response>", re.DOTALL)


# ── Public entry point ─────────────────────────────────────────────────────

async def run_post_run_check(
    user_id: UUID,
    workout_id: UUID,
    *,
    race_event_id: Optional[UUID] = None,
    source: str = CoachingEventTriggerSource.GARMIN_WEBHOOK.value,
    force: bool = False,
) -> Optional[UUID]:
    """
    Orchestrate the post-run analysis. Opens its own DB session so it can be
    safely fired from `asyncio.create_task` in the webhook handler.
    Returns the new coaching_event id, or None if no event was logged.
    """
    async with async_session() as db:
        user = await db.get(User, user_id)
        if user is None:
            logger.warning("post_run_check: user %s not found", user_id)
            return None

        garmin_workout = await db.get(GarminWorkout, workout_id)
        run = await _resolve_run_for_garmin_workout(db, garmin_workout) if garmin_workout else None
        if not garmin_workout or not run:
            logger.warning("post_run_check: missing garmin_workout or run (gw=%s)", workout_id)
            return None

        # ── Race-day branch ──────────────────────────────────────────────
        if race_event_id is not None:
            event_id = await _run_race_recap(db, user, garmin_workout, run, race_event_id, source)
            await db.commit()
            return event_id

        # ── Anomaly + streak detection ───────────────────────────────────
        flags = await anomaly_engine.evaluate_workout(db, user, run, garmin_workout)
        streak_flags = await streak_detector.detect_all(db, user)

        # No flags + no streak → info-only
        if not flags and not streak_flags:
            event_id = await _log_info_event(db, user, garmin_workout, run, source, reason="no_flags_no_streak")
            await db.commit()
            return event_id

        # Streak-only branch
        if streak_flags and not flags:
            event_id = await _run_consolidation(db, user, run, streak_flags, source)
            await db.commit()
            return event_id

        # ── Has flags. Critical override check. ──────────────────────────
        is_critical = _is_critical_combo(flags)
        paused = pause_service.is_paused(user)

        if is_critical:
            event_id = await _run_red_flag(db, user, run, flags, paused, source)
            await db.commit()
            return event_id

        # Non-critical. Skip if paused (data still flowed in via ingest).
        if paused and not force:
            event_id = await _log_info_event(db, user, garmin_workout, run, source, reason="user_paused")
            await db.commit()
            return event_id

        # Filter cooled-down flags
        active = await cooldown_service.filter_active_flags(db, user.id, flags)
        if not active:
            event_id = await _log_info_event(db, user, garmin_workout, run, source, reason="all_flags_cooled")
            await db.commit()
            return event_id

        event_id = await _run_post_run(db, user, run, garmin_workout, active, source)
        await db.commit()
        return event_id


# ── Branch handlers ────────────────────────────────────────────────────────

async def _run_race_recap(
    db: AsyncSession,
    user: User,
    garmin_workout: GarminWorkout,
    run: Run,
    race_event_id: UUID,
    source: str,
) -> UUID:
    """Race-day: fire coach_post_race.txt prompt + push."""
    race = await db.get(Event, race_event_id)
    memo_text = await coach_memo_service.get_memo_text(db, user.id)
    race_type = _resolve_race_type(user)

    user_prompt = _build_race_recap_user_prompt(user, race, garmin_workout, run)
    system_prompt = prompt_builder.get_post_race_prompt(race_type, memo=memo_text)

    return await _call_llm_and_persist(
        db=db,
        user=user,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        prompt_filename="coach_post_race.txt",
        model=coaching_models.POST_RACE_MODEL,
        event_type=CoachingEventType.POST_RACE.value,
        flags=[],
        source=source,
        notification_title="Big day. Let's break it down.",
        notification_loop="post_race",
        notification_type="post_race",
        deep_link_template="stride://coach/post-run/{event_id}",
        idempotency_key=f"post_race:{garmin_workout.garmin_activity_id}",
        force_push=True,  # race recaps always notify
        context_extra={
            "garmin_activity_id": garmin_workout.garmin_activity_id,
            "race_event_id": str(race_event_id),
            "race_title": race.title if race else None,
            "branch": "race_recap",
        },
    )


async def _run_consolidation(
    db: AsyncSession,
    user: User,
    run: Run,
    streak_flags: list[AnomalyFlag],
    source: str,
) -> UUID:
    """Streak only — Haiku call, push if not paused."""
    memo_text = await coach_memo_service.get_memo_text(db, user.id)
    race_type = _resolve_race_type(user)

    user_prompt = _build_consolidation_user_prompt(user, streak_flags, run)
    system_prompt = prompt_builder.get_consolidation_prompt(race_type, memo=memo_text)
    paused = pause_service.is_paused(user)

    return await _call_llm_and_persist(
        db=db,
        user=user,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        prompt_filename="coach_consolidation.txt",
        model=coaching_models.CONSOLIDATION_MODEL,
        event_type=CoachingEventType.CONSOLIDATION.value,
        flags=streak_flags,
        source=source,
        notification_title="You're locked in",
        notification_loop="post_run_check",
        notification_type="consolidation",
        deep_link_template="stride://coach/streak/{event_id}",
        idempotency_key=None,
        force_push=False,
        skip_push=paused,
        context_extra={"branch": "consolidation", "streak_types": [f.flag_type for f in streak_flags]},
    )


async def _run_red_flag(
    db: AsyncSession,
    user: User,
    run: Run,
    flags: list[AnomalyFlag],
    paused: bool,
    source: str,
) -> UUID:
    """Critical combo — Opus, force push (with pause-escalation grace)."""
    memo_text = await coach_memo_service.get_memo_text(db, user.id)
    race_type = _resolve_race_type(user)

    user_prompt = _build_post_run_user_prompt(user, run, flags, branch="red_flag")
    system_prompt = prompt_builder.get_red_flag_prompt(race_type, memo=memo_text)

    # During pause, only escalate after the 24h grace
    should_push = True
    if paused and not pause_service.should_critical_escalate(user):
        should_push = False  # log it for audit, athlete sees on resume

    return await _call_llm_and_persist(
        db=db,
        user=user,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        prompt_filename="coach_red_flag.txt",
        model=coaching_models.RED_FLAG_MODEL,
        event_type=CoachingEventType.RED_FLAG.value,
        flags=flags,
        source=source,
        notification_title="I have to flag this.",
        notification_loop=None,  # bypass loop-mode check (force_critical)
        notification_type="red_flag",
        deep_link_template="stride://coach/red-flag/{event_id}",
        idempotency_key=None,
        force_push=should_push,
        skip_push=not should_push,
        context_extra={"branch": "red_flag", "paused_at_fire_time": paused},
    )


async def _run_post_run(
    db: AsyncSession,
    user: User,
    run: Run,
    garmin_workout: GarminWorkout,
    flags: list[AnomalyFlag],
    source: str,
) -> UUID:
    """Standard non-critical post-run check — Sonnet, push if mode=live."""
    memo_text = await coach_memo_service.get_memo_text(db, user.id)
    race_type = _resolve_race_type(user)

    user_prompt = _build_post_run_user_prompt(user, run, flags, branch="post_run")
    system_prompt = prompt_builder.get_post_run_check_prompt(race_type, memo=memo_text)

    return await _call_llm_and_persist(
        db=db,
        user=user,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        prompt_filename="coach_post_run.txt",
        model=coaching_models.POST_RUN_CHECK_MODEL,
        event_type=CoachingEventType.POST_RUN_CHECK.value,
        flags=flags,
        source=source,
        notification_title="Today's run — let's talk.",
        notification_loop="post_run_check",
        notification_type="post_run_check",
        deep_link_template="stride://coach/post-run/{event_id}",
        idempotency_key=f"post_run:{garmin_workout.garmin_activity_id}",
        force_push=False,
        context_extra={"branch": "post_run", "active_flag_types": [f.flag_type for f in flags]},
    )


# ── Critical override + helpers ────────────────────────────────────────────

def _is_critical_combo(flags: list[AnomalyFlag]) -> bool:
    """
    Critical override per Phase 3 plan:
      LEA pattern at severity=critical, OR
      HRV drop at warning_plus AND missed_workouts at severity ≥ warning
    """
    if any(f.flag_type == FlagType.LEA_PATTERN.value and f.severity == FlagSeverity.CRITICAL.value for f in flags):
        return True
    has_hrv_plus = any(
        f.flag_type == FlagType.HRV_DROP.value and f.severity == FlagSeverity.WARNING_PLUS.value
        for f in flags
    )
    has_missed_warning = any(
        f.flag_type == FlagType.MISSED_WORKOUTS.value
        and f.severity in (FlagSeverity.WARNING.value, FlagSeverity.CRITICAL.value)
        for f in flags
    )
    return has_hrv_plus and has_missed_warning


# ── Generic LLM + persist + parse ──────────────────────────────────────────

async def _call_llm_and_persist(
    *,
    db: AsyncSession,
    user: User,
    system_prompt: str,
    user_prompt: str,
    prompt_filename: str,
    model: str,
    event_type: str,
    flags: list[AnomalyFlag],
    source: str,
    notification_title: str,
    notification_loop: Optional[str],
    notification_type: str,
    deep_link_template: str,
    idempotency_key: Optional[str],
    force_push: bool = False,
    skip_push: bool = False,
    context_extra: Optional[dict] = None,
) -> UUID:
    """
    Run the LLM, persist coaching_events, parse <response> tag, propose adjustment
    if applicable, send push, return event id.
    """
    client = AnthropicClient()
    output_text = await client.generate_plan(
        system_prompt,
        user_prompt,
        name=event_type,
        user_id=str(user.id),
        session_id=f"user:{user.id}:{event_type}",
        metadata={"flags": [f.flag_type for f in flags]},
        model=model,
    )
    metrics = client.last_metrics

    parsed = _parse_response_tag(output_text)
    clean_output = _strip_response_tag(output_text)
    cost_usd = coaching_models.estimate_cost_usd(
        model,
        metrics.input_tokens if metrics else 0,
        metrics.output_tokens if metrics else 0,
    )

    event_id = uuid4()
    event = CoachingEvent(
        id=event_id,
        user_id=user.id,
        event_type=event_type,
        trigger_source=source,
        flags_that_fired=[f.flag_type for f in flags],
        prompt_used=f"{prompt_filename}@{prompt_builder.prompt_sha(prompt_filename)}",
        llm_model_used=model,
        llm_input=user_prompt,
        llm_output=clean_output,
        llm_input_tokens=metrics.input_tokens if metrics else None,
        llm_output_tokens=metrics.output_tokens if metrics else None,
        llm_cost_usd=cost_usd,
        llm_latency_ms=metrics.latency_ms if metrics else None,
        idempotency_key=idempotency_key,
        shadow_mode=not _mode_is_live(user, notification_loop),
        context={**(context_extra or {}), "response_type": parsed.get("type") if parsed else None},
    )
    db.add(event)
    await db.flush()

    # Adjustment branch — propose PlanAdjustment
    if parsed and parsed.get("type") == "adjustment":
        try:
            await plan_adjustment_service.propose(
                db, user,
                trigger_event_id=event_id,
                summary=parsed.get("summary", ""),
                structured_diff=parsed.get("structured_diff", {}),
                affected_workout_dates=parsed.get("affected_workout_dates"),
            )
            # Override deep link to point straight to AdjustmentReviewSheet
            deep_link = f"stride://coach/adjustment/{await _latest_adjustment_id_for_event(db, event_id)}"
        except Exception:
            logger.exception("Failed to propose adjustment from event=%s", event_id)
            deep_link = deep_link_template.format(event_id=event_id)
    else:
        deep_link = deep_link_template.format(event_id=event_id)

    # Push notification
    if skip_push:
        event.notification_delivered = False
        event.notification_reason = "skipped:paused_grace_window" if not force_push else "skipped:caller"
    else:
        delivered, reason = await push_service.send_push(
            db, user,
            title=notification_title,
            body=_summary_for_notification(clean_output),
            deep_link=deep_link,
            notification_type=notification_type,
            loop_name=notification_loop,
            force_critical=force_push,
        )
        event.notification_delivered = delivered
        event.notification_reason = reason
    db.add(event)
    await db.flush()
    return event_id


# ── Logging-only helpers ───────────────────────────────────────────────────

async def _log_info_event(
    db: AsyncSession,
    user: User,
    garmin_workout: GarminWorkout,
    run: Run,
    source: str,
    *,
    reason: str,
) -> UUID:
    """Write an audit-only POST_RUN_INFO row when no LLM call is needed."""
    event = CoachingEvent(
        user_id=user.id,
        event_type=CoachingEventType.POST_RUN_INFO.value,
        trigger_source=source,
        flags_that_fired=[],
        notification_delivered=False,
        notification_reason=f"info_only:{reason}",
        shadow_mode=True,
        context={
            "garmin_activity_id": garmin_workout.garmin_activity_id,
            "distance_km": garmin_workout.distance_km,
            "skip_reason": reason,
        },
        idempotency_key=f"post_run_info:{garmin_workout.garmin_activity_id}",
    )
    db.add(event)
    await db.flush()
    return event.id


# ── Prompt user-input builders ─────────────────────────────────────────────

def _build_post_run_user_prompt(user: User, run: Run, flags: list[AnomalyFlag], *, branch: str) -> str:
    lines = [
        "WORKOUT JUST SYNCED",
        f"  Date: {run.completed_at.strftime('%Y-%m-%d %H:%M') if run.completed_at else '?'}",
        f"  Planned: {run.planned_workout_title or '—'} ({run.planned_workout_type or '—'}, {run.planned_distance_km or '—'} km)",
        f"  Actual: {run.distance_km:.1f} km in {int(run.duration_seconds // 60)} min" if run.distance_km else "  Actual: (no distance)",
    ]
    if run.avg_pace_sec_per_km:
        m, s = divmod(int(run.avg_pace_sec_per_km), 60)
        lines.append(f"  Avg pace: {m}:{s:02d}/km")
    if run.completion_score is not None:
        lines.append(f"  Completion score: {run.completion_score}/100")

    lines.append("")
    lines.append("FLAGS RAISED BY THE ANOMALY ENGINE")
    for f in flags:
        ctx = json.dumps(f.context, default=str)
        lines.append(f"  - type={f.flag_type} severity={f.severity} context={ctx}")

    lines.append("")
    lines.append("Write your response. End with a <response> JSON tag.")
    return "\n".join(lines)


def _build_consolidation_user_prompt(user: User, streak_flags: list[AnomalyFlag], run: Run) -> str:
    lines = ["A POSITIVE STREAK FIRED"]
    for f in streak_flags:
        ctx = json.dumps(f.context, default=str)
        lines.append(f"  - {f.flag_type}: {ctx}")
    if run.completed_at:
        lines.append(f"\nMost recent run: {run.completed_at.strftime('%Y-%m-%d')} — {run.distance_km:.1f} km")
    lines.append("\nWrite your message. Plain prose only. No JSON tags.")
    return "\n".join(lines)


def _build_race_recap_user_prompt(user: User, race: Optional[Event], gw: GarminWorkout, run: Run) -> str:
    lines = ["RACE DAY"]
    if race:
        lines.append(f"  Race: {race.title}")
        if race.distance_km:
            lines.append(f"  Race distance: {race.distance_km} km")
    if run:
        h = int(run.duration_seconds // 3600)
        m = int((run.duration_seconds % 3600) // 60)
        s = int(run.duration_seconds % 60)
        lines.append(f"  Final time: {h:01d}:{m:02d}:{s:02d}")
        lines.append(f"  Distance: {run.distance_km:.2f} km")
        if run.avg_pace_sec_per_km:
            pm, ps = divmod(int(run.avg_pace_sec_per_km), 60)
            lines.append(f"  Avg pace: {pm}:{ps:02d}/km")
    if gw.avg_heart_rate:
        lines.append(f"  Avg HR: {gw.avg_heart_rate}")
    if gw.max_heart_rate:
        lines.append(f"  Max HR: {gw.max_heart_rate}")
    if gw.splits:
        lines.append("\n  Splits:")
        for s in gw.splits[:50]:
            lines.append(f"    km {s.get('km', '?')}: pace {s.get('pace_sec_per_km', '?')}s/km hr {s.get('hr', '?')}")
    lines.append("\nWrite the race recap now.")
    return "\n".join(lines)


# ── Output parsing ─────────────────────────────────────────────────────────

def _parse_response_tag(output: str) -> Optional[dict]:
    if not output:
        return None
    m = _RESPONSE_TAG_RE.search(output)
    if not m:
        return None
    try:
        parsed = json.loads(m.group(1))
        return parsed if isinstance(parsed, dict) else None
    except (json.JSONDecodeError, ValueError):
        logger.warning("Failed to parse <response> JSON: %s", m.group(1)[:200])
        return None


def _strip_response_tag(output: str) -> str:
    return _RESPONSE_TAG_RE.sub("", output or "").strip()


# ── Misc helpers ───────────────────────────────────────────────────────────

async def _resolve_run_for_garmin_workout(db: AsyncSession, gw: Optional[GarminWorkout]) -> Optional[Run]:
    """The Run row mirrored from a GarminWorkout uses a deterministic UUID."""
    if gw is None:
        return None
    import uuid as _uuid
    deterministic_run_id = _uuid.uuid5(_uuid.NAMESPACE_URL, f"garmin:{gw.garmin_activity_id}")
    return await db.get(Run, deterministic_run_id)


def _resolve_race_type(user: User):
    from app.models.schemas import RaceType
    raw = getattr(user, "current_race_type", None)
    if raw:
        try:
            return RaceType(raw)
        except ValueError:
            pass
    return RaceType.MARATHON


def _mode_is_live(user: User, loop_name: Optional[str]) -> bool:
    if loop_name is None:
        return True  # critical / forced
    return (user.coaching_modes or {}).get(loop_name, "shadow") == "live"


async def _latest_adjustment_id_for_event(db: AsyncSession, event_id: UUID) -> str:
    from sqlalchemy import select, desc
    from app.models.plan_adjustment import PlanAdjustment
    result = await db.execute(
        select(PlanAdjustment.id)
        .where(PlanAdjustment.trigger_event_id == event_id)
        .order_by(desc(PlanAdjustment.proposed_at))
        .limit(1)
    )
    row = result.scalar_one_or_none()
    return str(row) if row else str(event_id)


def _summary_for_notification(text: str) -> str:
    if not text:
        return "Tap to read your coach's note."
    line = text.split("\n", 1)[0].strip()
    return (line[:107].rstrip() + "…") if len(line) > 110 else line
