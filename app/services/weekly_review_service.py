"""
Weekly-review orchestrator — the first real coaching loop.

Pipeline (run_weekly_review):
  1. Skip if no plan / recent post_race event / in race-prep window
  2. Load full context (7d data, 4 reviews, active focuses, memo, week character, plan summary)
  3. Compose prompt via prompt_builder.get_weekly_review_prompt
  4. Call Opus (non-streaming for cron — iOS replays saved output)
  5. Parse focuses / focus outcomes / adjustment proposal from JSON tags
  6. Persist coaching_events row with full I/O + tokens + cost + sha
  7. Apply outcomes to prior focuses + persist new focuses
  8. Persist plan_adjustment if proposal present
  9. Trigger memo update (background, Haiku)
  10. Send APNs push when coaching_modes['weekly_review'] == 'live'
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
    CoachingEventType,
    CoachingEventTriggerSource,
)
from app.models.event import Event, EventRegistration
from app.models.garmin_daily_metric import GarminDailyMetric
from app.models.garmin_workout import GarminWorkout
from app.models.plan_adjustment import PlanAdjustment, PlanAdjustmentStatus
from app.models.run import Run
from app.models.schemas import RaceType
from app.models.user import User
from app.services import (
    coach_memo_service,
    coaching_models,
    focus_tracker,
    push_service,
    strength_service,
    wellness_service,
)
from app.services.anthropic_client import AnthropicClient
from app.services.plan_week_classifier import classify_week
from app.services.prompt_builder import prompt_builder

logger = logging.getLogger(__name__)


# Skip if any post_race event landed in this window (race recap took priority)
_POST_RACE_SKIP_DAYS = 6


# ── Public entry point ────────────────────────────────────────────────────

async def run_weekly_review(
    user_id: UUID,
    *,
    source: str = CoachingEventTriggerSource.MANUAL.value,
    force: bool = False,
    week_offset: int = 0,
    checkin_id: Optional[UUID] = None,
    anchor_date=None,
) -> Optional[UUID]:
    """
    Generate this week's review for a user. Runs in its own DB session so it can
    be safely fired as an asyncio.create_task from cron.

    When `checkin_id` points at a submitted WeeklyCheckin (or one is
    auto-discovered for the current week), the athlete's answers are rendered
    into the prompt and the check-in row is linked to the resulting event.

    Returns the new coaching_events.id, or None if skipped.
    """
    from app.models.weekly_checkin import WeeklyCheckin, WeeklyCheckinStatus

    async with async_session() as db:
        user = await db.get(User, user_id)
        if user is None:
            logger.warning("weekly_review: user %s not found", user_id)
            return None

        # ── Load submitted check-in (explicit id, or auto-discover) ──────
        checkin = None
        if checkin_id is not None:
            checkin = await db.get(WeeklyCheckin, checkin_id)
            if checkin is not None and checkin.user_id != user_id:
                checkin = None
        else:
            from app.services import weekly_checkin_service
            candidate = await weekly_checkin_service.get_current(db, user_id)
            if candidate is not None and candidate.status == WeeklyCheckinStatus.SUBMITTED.value:
                checkin = candidate

        # ── Skip checks ──────────────────────────────────────────────────
        if not force:
            if await _has_recent_post_race(db, user.id):
                _log_skip(db, user, "recent_post_race")
                await db.commit()
                return None
            if await _in_race_prep_window(db, user.id):
                _log_skip(db, user, "race_prep_active")
                await db.commit()
                return None

        # ── Context loading ──────────────────────────────────────────────
        today = anchor_date or (datetime.now(timezone.utc).date() - timedelta(days=7 * week_offset))
        week_character = await classify_week(db, user.id, today=today)

        runs = await _fetch_runs_in_window(db, user.id, days=7, today=today)
        if not runs and week_character != "first" and not force:
            # Genuinely empty week. Log and skip — don't waste an Opus call.
            _log_skip(db, user, "no_runs_this_week")
            await db.commit()
            return None

        garmin_workouts = await _fetch_garmin_workouts(db, user.id, days=7, today=today)
        daily_metrics = await _fetch_daily_metrics(db, user.id, days=7, today=today)
        prior_reviews = await _fetch_prior_reviews(db, user.id, count=4)
        active_focuses = await focus_tracker.get_active_focuses(db, user.id, weeks_back=4)
        active_flags = await _fetch_active_flags(db, user.id)
        memo_text = await coach_memo_service.get_memo_text(db, user.id)
        plan_summary = _derive_plan_summary(runs, user)
        goal_alignment = _derive_goal_alignment(runs, user)
        wellness_trends = await wellness_service.compute_trends(db, user.id, window_days=7)
        strength_summary = {
            "session_count": await strength_service.compute_session_count(db, user.id, days=7),
            "skip_info": await strength_service.compute_skip_count(db, user.id, days=7),
            "total_volume_kg": await strength_service.compute_total_volume_kg(db, user.id, days=7),
        }

        # ── Prompt assembly ──────────────────────────────────────────────
        race_type = _resolve_race_type(user)
        system_prompt = prompt_builder.get_weekly_review_prompt(
            race_type=race_type,
            memo=memo_text,
        )
        user_prompt = _build_user_prompt(
            user=user,
            today=today,
            week_character=week_character,
            runs=runs,
            garmin_workouts=garmin_workouts,
            daily_metrics=daily_metrics,
            prior_reviews=prior_reviews,
            active_focuses=active_focuses,
            active_flags=active_flags,
            plan_summary=plan_summary,
            goal_alignment=goal_alignment,
            wellness_trends=wellness_trends,
            strength_summary=strength_summary,
            checkin=checkin,
        )

        # ── LLM call ─────────────────────────────────────────────────────
        client = AnthropicClient()
        model = coaching_models.WEEKLY_REVIEW_MODEL
        try:
            output_text = await client.generate_plan(
                system_prompt,
                user_prompt,
                name="weekly-review",
                user_id=str(user.id),
                session_id=f"user:{user.id}:weekly-review:{today.isoformat()}",
                metadata={"week_character": week_character, "week_offset": week_offset},
                model=model,
            )
        except Exception as exc:
            logger.exception("weekly_review LLM call failed for user=%s", user.id)
            event = CoachingEvent(
                user_id=user.id,
                event_type=CoachingEventType.WEEKLY_REVIEW.value,
                trigger_source=source,
                flags_that_fired=[],
                prompt_used=f"coach_weekly_review.txt@{prompt_builder.prompt_sha('coach_weekly_review.txt')}",
                llm_model_used=model,
                notification_delivered=False,
                notification_reason=f"llm_error:{type(exc).__name__}",
                shadow_mode=True,
                context={"week_character": week_character, "error": str(exc)[:300]},
            )
            db.add(event)
            await db.commit()
            return event.id

        metrics = client.last_metrics

        # ── Parse JSON tags ──────────────────────────────────────────────
        next_focuses = focus_tracker.parse_focuses(output_text)
        outcomes = focus_tracker.parse_focus_outcomes(output_text)
        adjustment = focus_tracker.parse_adjustment(output_text)
        clean_output = focus_tracker.strip_tags(output_text)

        # ── Persist coaching_events row ──────────────────────────────────
        cost_usd = coaching_models.estimate_cost_usd(
            model,
            metrics.input_tokens if metrics else 0,
            metrics.output_tokens if metrics else 0,
        )
        prompt_sha = prompt_builder.prompt_sha("coach_weekly_review.txt")

        event = CoachingEvent(
            id=uuid4(),
            user_id=user.id,
            event_type=CoachingEventType.WEEKLY_REVIEW.value,
            trigger_source=source,
            flags_that_fired=[f.flag_type for f in active_flags],
            prompt_used=f"coach_weekly_review.txt@{prompt_sha}",
            llm_model_used=model,
            llm_input=user_prompt,
            llm_output=clean_output,
            llm_input_tokens=metrics.input_tokens if metrics else None,
            llm_output_tokens=metrics.output_tokens if metrics else None,
            llm_cost_usd=cost_usd,
            llm_latency_ms=metrics.latency_ms if metrics else None,
            shadow_mode=(user.coaching_modes or {}).get("weekly_review", "shadow") != "live",
            context={
                "week_character": week_character,
                "week_offset": week_offset,
                "next_focuses": next_focuses,
                "had_adjustment_proposal": adjustment is not None,
                "plan_summary": plan_summary,
                "goal_alignment": goal_alignment,
                "checkin_id": str(checkin.id) if checkin else None,
            },
        )
        db.add(event)
        await db.flush()

        # ── Link the check-in to its review ──────────────────────────────
        if checkin is not None:
            checkin.review_event_id = event.id

        # ── Apply outcomes + persist new focuses ─────────────────────────
        if outcomes:
            await focus_tracker.apply_outcomes(db, user.id, outcomes, set_by_event_id=event.id)
        if next_focuses:
            await focus_tracker.persist_focuses(db, user.id, raised_in_event_id=event.id, focuses=next_focuses)

        # ── Persist plan adjustment if proposed ──────────────────────────
        if adjustment:
            adj_row = _build_plan_adjustment(adjustment, user, event.id)
            db.add(adj_row)

        # ── Notification ─────────────────────────────────────────────────
        delivered, reason = await push_service.send_push(
            db, user,
            title="Your week's review is ready",
            body=_summary_for_notification(clean_output, plan_summary),
            deep_link=f"stride://coach/weekly-review/{event.id}",
            notification_type="weekly_review",
            loop_name="weekly_review",
        )
        event.notification_delivered = delivered
        event.notification_reason = reason
        db.add(event)

        await db.commit()
        new_event_id = event.id

    # ── Background memo update (separate session, fire-and-forget) ───────
    asyncio.create_task(_update_memo_background(user_id, new_event_id, clean_output))

    logger.info(
        "weekly_review for user=%s: event=%s focuses=%d outcomes=%d adjustment=%s pushed=%s",
        user_id, new_event_id, len(next_focuses), len(outcomes),
        adjustment is not None, delivered,
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
    """True when there's a registered race within 28 days (Phase 8 owns it)."""
    now = datetime.now(timezone.utc)
    cutoff = now + timedelta(days=28)
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
    """Write an info-only event for the audit trail when we skip a review."""
    event = CoachingEvent(
        user_id=user.id,
        event_type=CoachingEventType.NO_ACTIVE_PLAN.value if reason == "no_runs_this_week" else CoachingEventType.WEEKLY_REVIEW.value,
        trigger_source=CoachingEventTriggerSource.CRON.value,
        flags_that_fired=[],
        notification_delivered=False,
        notification_reason=f"skipped:{reason}",
        shadow_mode=True,
        context={"skip_reason": reason},
    )
    db.add(event)


# ── Context loaders ────────────────────────────────────────────────────────

async def _fetch_runs_in_window(db: AsyncSession, user_id: UUID, days: int, today) -> list[Run]:
    cutoff = datetime.combine(today - timedelta(days=days), datetime.min.time(), tzinfo=timezone.utc)
    end = datetime.combine(today, datetime.max.time(), tzinfo=timezone.utc)
    result = await db.execute(
        select(Run)
        .where(Run.user_id == user_id, Run.completed_at >= cutoff, Run.completed_at <= end)
        .order_by(Run.completed_at)
    )
    return list(result.scalars().all())


async def _fetch_garmin_workouts(db: AsyncSession, user_id: UUID, days: int, today) -> list[GarminWorkout]:
    cutoff = datetime.combine(today - timedelta(days=days), datetime.min.time(), tzinfo=timezone.utc)
    end = datetime.combine(today, datetime.max.time(), tzinfo=timezone.utc)
    result = await db.execute(
        select(GarminWorkout)
        .where(GarminWorkout.user_id == user_id, GarminWorkout.start_time >= cutoff, GarminWorkout.start_time <= end)
        .order_by(GarminWorkout.start_time)
    )
    return list(result.scalars().all())


async def _fetch_daily_metrics(db: AsyncSession, user_id: UUID, days: int, today) -> list[GarminDailyMetric]:
    cutoff = today - timedelta(days=days)
    result = await db.execute(
        select(GarminDailyMetric)
        .where(GarminDailyMetric.user_id == user_id, GarminDailyMetric.date >= cutoff, GarminDailyMetric.date <= today)
        .order_by(GarminDailyMetric.date)
    )
    return list(result.scalars().all())


async def _fetch_prior_reviews(db: AsyncSession, user_id: UUID, count: int) -> list[CoachingEvent]:
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


def _derive_plan_summary(runs: list[Run], user: User) -> dict:
    """Inferred from denormalized fields on Run (we don't have plan tables on backend)."""
    if not runs:
        return {}
    latest = runs[-1]
    return {
        "plan_name": latest.plan_name,
        "current_week_number": latest.week_number,
        "athlete_name": user.name or user.display_name or "Athlete",
    }


def _derive_goal_alignment(runs: list[Run], user: User) -> dict:
    """Phase 7 will use Garmin race predictors. For Phase 2 we expose what we have."""
    return {
        "race_type": _resolve_race_type(user).value if hasattr(_resolve_race_type(user), "value") else "marathon",
    }


def _resolve_race_type(user: User) -> RaceType:
    """
    Phase 2: derive race type from User.current_race_type (Phase 2 column),
    falling back to MARATHON. Phase 7 will read from synced plan structure.
    """
    raw = getattr(user, "current_race_type", None)
    if raw:
        try:
            return RaceType(raw)
        except ValueError:
            pass
    return RaceType.MARATHON


# ── Prompt input building ──────────────────────────────────────────────────

def _build_user_prompt(
    *,
    user: User,
    today,
    week_character: str,
    runs: list[Run],
    garmin_workouts: list[GarminWorkout],
    daily_metrics: list[GarminDailyMetric],
    prior_reviews: list[CoachingEvent],
    active_focuses,
    active_flags: list[AnomalyFlag],
    plan_summary: dict,
    goal_alignment: dict,
    wellness_trends: Optional[dict] = None,
    strength_summary: Optional[dict] = None,
    checkin=None,
) -> str:
    """Render structured context for the weekly review prompt."""

    sections: list[str] = []

    # ── Athlete + plan ────────────────────────────────────────────────────
    sections.append(f"WEEK ENDING: {today.isoformat()}")
    sections.append(f"WEEK CHARACTER: {week_character}")
    if plan_summary:
        sections.append("PLAN")
        sections.append(f"  Athlete: {plan_summary.get('athlete_name', '')}")
        if plan_summary.get("plan_name"):
            sections.append(f"  Plan: {plan_summary['plan_name']}")
        if plan_summary.get("current_week_number"):
            sections.append(f"  Current week: {plan_summary['current_week_number']}")
    if goal_alignment:
        sections.append(f"GOAL: {goal_alignment.get('race_type', 'marathon')}")

    # ── Runs ──────────────────────────────────────────────────────────────
    sections.append("\nRUNS THIS WEEK")
    if not runs:
        sections.append("(none logged)")
    else:
        total_km = sum(r.distance_km or 0 for r in runs)
        sections.append(f"Total: {total_km:.1f} km across {len(runs)} runs")
        for r in runs:
            date_s = r.completed_at.strftime("%a %m-%d %H:%M") if r.completed_at else "?"
            pace = r.avg_pace_sec_per_km or 0
            pace_str = f"{int(pace)//60}:{int(pace)%60:02d}/km" if pace else "-"
            planned = r.planned_workout_title or "—"
            ptype = r.planned_workout_type or "—"
            sections.append(
                f"  {date_s} | {r.distance_km:.1f}km {pace_str} | "
                f"planned: {planned} ({ptype}) | "
                f"score: {r.completion_score or '-'}"
            )

    # ── Garmin (additional fidelity beyond Run) ───────────────────────────
    if garmin_workouts:
        running_g = [w for w in garmin_workouts if w.activity_type == "running"]
        cross_g = [w for w in garmin_workouts if w.activity_type != "running"]
        if cross_g:
            sections.append("\nCROSS-TRAINING THIS WEEK")
            for w in cross_g:
                sections.append(f"  {w.start_time.strftime('%a %m-%d')} | {w.activity_type} | {(w.distance_km or 0):.1f}km | {int(w.duration_seconds or 0)//60} min")
        # HR zone summary across the week's running
        if running_g:
            zones_total = {"z1": 0, "z2": 0, "z3": 0, "z4": 0, "z5": 0}
            for w in running_g:
                if w.hr_zones:
                    for k, v in w.hr_zones.items():
                        if k in zones_total:
                            zones_total[k] += int(v or 0)
            total_z = sum(zones_total.values())
            if total_z > 0:
                pct = {k: round(v / total_z * 100) for k, v in zones_total.items()}
                sections.append(
                    f"\nHR ZONE DISTRIBUTION (running): "
                    f"Z1 {pct['z1']}% / Z2 {pct['z2']}% / Z3 {pct['z3']}% / Z4 {pct['z4']}% / Z5 {pct['z5']}%"
                )

    # ── Recovery ──────────────────────────────────────────────────────────
    sections.append("\nRECOVERY (last 7 days)")
    if not daily_metrics:
        sections.append("(no Garmin daily metrics in window — Phase 1 may not yet have data)")
    else:
        hrv_values = [m.hrv_overnight for m in daily_metrics if m.hrv_overnight]
        rhr_values = [m.resting_heart_rate for m in daily_metrics if m.resting_heart_rate]
        sleep_values = [m.sleep_duration_minutes for m in daily_metrics if m.sleep_duration_minutes]
        if hrv_values:
            avg_hrv = sum(hrv_values) / len(hrv_values)
            baseline = daily_metrics[-1].hrv_baseline_7day
            pct_change = ((avg_hrv - baseline) / baseline * 100) if baseline else 0
            sections.append(f"  HRV avg: {avg_hrv:.0f}ms (baseline: {baseline or 'unknown'}, change: {pct_change:+.1f}%)")
        if rhr_values:
            sections.append(f"  RHR avg: {sum(rhr_values)/len(rhr_values):.0f} bpm")
        if sleep_values:
            avg_sleep = sum(sleep_values) / len(sleep_values) / 60
            min_sleep = min(sleep_values) / 60
            sections.append(f"  Sleep avg: {avg_sleep:.1f}h (worst night: {min_sleep:.1f}h)")
        # Detect freshness: did today's metric arrive yet?
        today_pushed = any(m.date == today for m in daily_metrics)
        sections.append(f"  metrics_freshness: {'today' if today_pushed else 'yesterday' if any(m.date == today - timedelta(days=1) for m in daily_metrics) else 'stale'}")

    # ── Wellness (Phase 4) — render when present, omit otherwise ──────────
    if wellness_trends and wellness_trends.get("current", {}).get("n", 0) > 0:
        cur = wellness_trends["current"]
        deltas = wellness_trends.get("deltas", {})
        sections.append("\nWELLNESS (last 7 days)")
        sections.append(f"  Entries: {cur.get('n', 0)}")
        if cur.get("sleep_quality_avg") is not None:
            sections.append(f"  Sleep avg: {cur['sleep_quality_avg']}/5 (delta vs prior week: {deltas.get('sleep_quality_avg', 0):+})")
        if cur.get("soreness_avg") is not None:
            sections.append(f"  Soreness avg: {cur['soreness_avg']}/5 (delta: {deltas.get('soreness_avg', 0):+})")
        if cur.get("motivation_avg") is not None:
            sections.append(f"  Motivation avg: {cur['motivation_avg']}/5 (delta: {deltas.get('motivation_avg', 0):+})")
        if cur.get("stress_avg") is not None:
            sections.append(f"  Stress avg: {cur['stress_avg']}/5 (delta: {deltas.get('stress_avg', 0):+})")
        if cur.get("frequent_soreness_areas"):
            areas = ", ".join(f"{a['area']}({a['count']}x)" for a in cur["frequent_soreness_areas"])
            sections.append(f"  Frequent soreness areas: {areas}")
        if cur.get("any_pain_keyword_days", 0) > 0:
            sections.append(f"  Days with pain keywords in notes: {cur['any_pain_keyword_days']}")
        if cur.get("notes_concatenated"):
            blob = cur["notes_concatenated"][:600]
            sections.append(f"  Recent notes: {blob}{'…' if len(cur['notes_concatenated']) > 600 else ''}")

    # ── Strength (Phase 9) ─────────────────────────────────────────────────
    if strength_summary and (strength_summary.get("session_count", 0) > 0 or strength_summary.get("skip_info", {}).get("skip_count", 0) > 0):
        sections.append("\nSTRENGTH (last 7 days)")
        sections.append(f"  Sessions logged: {strength_summary.get('session_count', 0)}")
        skip = strength_summary.get("skip_info") or {}
        if skip.get("skip_count", 0) > 0:
            dates = ", ".join(skip.get("skipped_dates", []))
            sections.append(f"  Skipped gym sessions: {skip['skip_count']} ({dates})")
        if strength_summary.get("total_volume_kg", 0) > 0:
            sections.append(f"  Total volume: {strength_summary['total_volume_kg']:.0f} kg")

    # ── Nutrition (Phase 6) ────────────────────────────────────────────────
    # Intentionally not rendered when empty per prompt spec ("skip silently")

    # ── Active flags ──────────────────────────────────────────────────────
    if active_flags:
        sections.append("\nACTIVE ANOMALY FLAGS")
        for f in active_flags:
            sections.append(f"  - {f.flag_type} (severity={f.severity}) raised={f.raised_at.strftime('%m-%d')}")

    # ── Athlete check-in answers (interactive weekly check-in) ────────────
    if checkin is not None and (checkin.answers or {}):
        sections.append("\nATHLETE CHECK-IN (their own words — weigh heavily)")
        by_id: dict[str, dict] = {}
        for q in (checkin.questions or {}).get("questions", []):
            by_id[q["id"]] = q
            if q.get("follow_up_if_yes"):
                by_id[q["follow_up_if_yes"]["id"]] = q["follow_up_if_yes"]
        for qid, value in checkin.answers.items():
            q = by_id.get(qid, {})
            text = q.get("text", qid)
            if isinstance(value, bool):
                rendered = "Yes" if value else "No"
            elif q.get("type") == "scale_1_5":
                lo, hi = q.get("low_label"), q.get("high_label")
                rendered = f"{value}/5" + (f" (1={lo}, 5={hi})" if lo and hi else "")
            else:
                rendered = str(value)
            sections.append(f"  Q: {text}\n  A: {rendered}")

    # ── Last week's focuses (active = unresolved or recent) ───────────────
    sections.append("\nLAST WEEK'S FOCUSES")
    sections.append(focus_tracker.format_focuses_for_prompt(active_focuses))

    # ── Prior reviews (compact) ───────────────────────────────────────────
    if prior_reviews:
        sections.append("\nPRIOR REVIEWS (last 4, oldest first)")
        for review in reversed(prior_reviews):
            date_s = review.triggered_at.strftime("%Y-%m-%d")
            # Trim to ~400 chars to keep the prompt budget reasonable
            body = (review.llm_output or "")[:400].replace("\n", " ")
            sections.append(f"  --- {date_s} ---\n  {body}{'…' if len(review.llm_output or '') > 400 else ''}")

    sections.append("\n— end of context —\n\nWrite this week's review now.")
    return "\n".join(sections)


def _build_plan_adjustment(adjustment: dict, user: User, trigger_event_id: UUID) -> PlanAdjustment:
    """Translate the LLM's <adjustment> JSON into a PlanAdjustment row."""
    affected_dates = adjustment.get("affected_workout_dates") or []
    # Workout-level proposals expire at the earliest affected workout's start + 1h.
    # If only block-level (multi-week), 7-day expiry. Phase 2 conservatively
    # uses 7 days for any review-driven proposal — these are weekly cadence anyway.
    expires_at = datetime.now(timezone.utc) + timedelta(days=7)

    return PlanAdjustment(
        user_id=user.id,
        training_plan_id=None,
        proposed_at=datetime.now(timezone.utc),
        expires_at=expires_at,
        status=PlanAdjustmentStatus.PROPOSED.value,
        trigger_event_id=trigger_event_id,
        summary_text=str(adjustment.get("summary", "")),
        structured_diff=adjustment.get("structured_diff", {}),
        affected_workout_ids=None,  # iOS-side workout IDs not known on backend
    )


def _summary_for_notification(clean_output: str, plan_summary: dict) -> str:
    """First-line preview for the push notification body."""
    line = clean_output.split("\n", 1)[0].strip() if clean_output else ""
    if len(line) > 110:
        line = line[:107].rstrip() + "…"
    return line or "Tap to read your week's review."


# ── Background memo update ─────────────────────────────────────────────────

async def _update_memo_background(user_id: UUID, triggering_event_id: UUID, review_output: str) -> None:
    try:
        async with async_session() as db:
            await coach_memo_service.update_memo(
                db, user_id, triggering_event_id, review_output,
                summary_range={"weekly_review_event_id": str(triggering_event_id)},
            )
            await db.commit()
    except Exception:
        logger.exception("Background memo update failed for user=%s", user_id)
