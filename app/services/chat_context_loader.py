"""
Load full athlete state for the coach chat in ~3000 tokens.

Returns a structured dict that the chat route renders into the user prompt.
The same loader is reusable by Phase 3's post-run check_in followups and
Phase 4's wellness concern follow-ups (so all three coaching channels see
the same world).
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.anomaly_flag import AnomalyFlag
from app.models.chat_message import ChatMessage, ChatRole
from app.models.chat_summary import ChatSummary
from app.models.coaching_event import CoachingEvent
from app.models.garmin_daily_metric import GarminDailyMetric
from app.models.run import Run
from app.models.user import User
from app.models.weekly_focus import WeeklyFocus
from app.services import coach_memo_service, focus_tracker, wellness_service

logger = logging.getLogger(__name__)


_RUNS_LOOKBACK_DAYS = 30
_RECOVERY_LOOKBACK_DAYS = 14
_WELLNESS_LOOKBACK_DAYS = 14
_NUTRITION_LOOKBACK_DAYS = 7
_FLAGS_LIMIT = 10
_RECENT_HISTORY_LIMIT = 50


async def load_context(
    db: AsyncSession,
    user: User,
    *,
    training_plan_id: Optional[UUID] = None,
    related_event_id: Optional[UUID] = None,
) -> dict:
    """
    Returns a dict with all the context the chat coach needs:

      {
        "athlete": {...},
        "plan_summary": {...} | None,        # None during no-plan periods
        "recent_runs": [{...}],              # last 30d, compact
        "recovery": {...},                   # last 14d HRV/RHR/sleep summary
        "wellness": {...},                   # last 14d trends (may be empty)
        "nutrition": {...} | None,           # last 7d (None until Phase 6)
        "active_flags": [{...}],
        "active_focuses": [{...}],
        "memo": "...",
        "history": [{...}],                  # last 50 chat messages, oldest first
        "history_summary": "..." | None,     # Haiku rolling summary if > 50
        "related_event": {...} | None,
      }

    The chat route translates this into a user prompt; nothing here calls the LLM.
    """
    today = datetime.now(timezone.utc).date()

    runs = await _recent_runs(db, user.id, days=_RUNS_LOOKBACK_DAYS)
    recovery = await _recovery_summary(db, user.id, days=_RECOVERY_LOOKBACK_DAYS, today=today)
    wellness_trends = await wellness_service.compute_trends(db, user.id, window_days=_WELLNESS_LOOKBACK_DAYS)
    flags = await _active_flags(db, user.id, limit=_FLAGS_LIMIT)
    focuses = await focus_tracker.get_active_focuses(db, user.id, weeks_back=4)
    memo_text = await coach_memo_service.get_memo_text(db, user.id)
    history, history_summary = await _chat_history(db, user.id, training_plan_id, limit=_RECENT_HISTORY_LIMIT)
    related_event = await _related_event(db, user.id, related_event_id)

    plan_summary = _derive_plan_summary(runs, training_plan_id, user)

    return {
        "athlete": {
            "name": user.name or user.display_name or "Athlete",
            "race_type": getattr(user, "current_race_type", None) or "marathon",
        },
        "plan_summary": plan_summary,
        "recent_runs": _compact_runs(runs),
        "recovery": recovery,
        "wellness": _wellness_summary(wellness_trends),
        "nutrition": None,  # Phase 6 wires this
        "active_flags": [_flag_to_dict(f) for f in flags],
        "active_focuses": [{"id": str(f.id), "text": f.text, "outcome": f.outcome} for f in focuses],
        "memo": memo_text,
        "history": [_chat_msg_to_dict(m) for m in history],
        "history_summary": history_summary,
        "related_event": related_event,
    }


def render_prompt_block(context: dict) -> str:
    """
    Render the context dict as a structured text block for the user prompt.
    The chat route concatenates this with the athlete's just-sent message.
    """
    lines: list[str] = []

    a = context["athlete"]
    lines.append(f"ATHLETE: {a['name']} (race goal: {a['race_type']})")

    plan = context.get("plan_summary")
    if plan:
        lines.append("\nPLAN")
        for k, v in plan.items():
            if v is not None:
                lines.append(f"  {k}: {v}")
    else:
        lines.append("\nPLAN: (no active plan)")

    runs = context.get("recent_runs") or []
    if runs:
        lines.append(f"\nRECENT RUNS — last {_RUNS_LOOKBACK_DAYS} days, {len(runs)} entries")
        for r in runs[-30:]:
            lines.append(f"  {r}")
    else:
        lines.append("\nRECENT RUNS: (none)")

    recovery = context.get("recovery") or {}
    if recovery:
        lines.append(f"\nRECOVERY (last {_RECOVERY_LOOKBACK_DAYS}d)")
        for k, v in recovery.items():
            lines.append(f"  {k}: {v}")

    wellness = context.get("wellness") or {}
    if wellness and wellness.get("n", 0) > 0:
        lines.append(f"\nWELLNESS (last {_WELLNESS_LOOKBACK_DAYS}d, {wellness['n']} entries)")
        for k, v in wellness.items():
            if k == "n":
                continue
            lines.append(f"  {k}: {v}")

    flags = context.get("active_flags") or []
    if flags:
        lines.append("\nACTIVE FLAGS")
        for f in flags:
            lines.append(f"  - {f['type']} ({f['severity']}) raised={f['raised_at']}")

    focuses = context.get("active_focuses") or []
    if focuses:
        lines.append("\nACTIVE FOCUSES")
        for f in focuses:
            outcome = f" [{f['outcome']}]" if f["outcome"] else ""
            lines.append(f"  - id={f['id']} text={f['text']!r}{outcome}")

    if context.get("history_summary"):
        lines.append("\nEARLIER IN THIS CONVERSATION (Haiku-summarized):")
        lines.append(f"  {context['history_summary']}")

    history = context.get("history") or []
    if history:
        lines.append(f"\nRECENT MESSAGES ({len(history)})")
        for m in history:
            who = "ATHLETE" if m["role"] == ChatRole.ATHLETE.value else "COACH"
            lines.append(f"  [{m['sent_at']}] {who}: {m['content']}")

    related = context.get("related_event")
    if related:
        lines.append("\nRELATED COACHING EVENT (the chat was opened from this)")
        lines.append(f"  type={related['event_type']} triggered={related['triggered_at']}")
        if related.get("summary"):
            lines.append(f"  summary: {related['summary']}")

    return "\n".join(lines)


# ── Helpers ────────────────────────────────────────────────────────────────

async def _recent_runs(db: AsyncSession, user_id: UUID, days: int) -> list[Run]:
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    result = await db.execute(
        select(Run)
        .where(Run.user_id == user_id, Run.completed_at >= cutoff)
        .order_by(Run.completed_at)
    )
    return list(result.scalars().all())


def _compact_runs(runs: list[Run]) -> list[str]:
    lines: list[str] = []
    for r in runs:
        date = r.completed_at.strftime("%Y-%m-%d") if r.completed_at else "?"
        pace = r.avg_pace_sec_per_km or 0
        pace_str = f"{int(pace)//60}:{int(pace)%60:02d}/km" if pace else "—"
        ptype = r.planned_workout_type or "—"
        actual = f"{r.distance_km:.1f}km" if r.distance_km else "—"
        planned = f"{r.planned_distance_km:.1f}km" if r.planned_distance_km else "—"
        score = r.completion_score if r.completion_score is not None else "—"
        lines.append(f"{date} | {ptype} | actual {actual} {pace_str} | planned {planned} | score {score}")
    return lines


async def _recovery_summary(db: AsyncSession, user_id: UUID, days: int, today) -> dict:
    cutoff = today - timedelta(days=days)
    result = await db.execute(
        select(GarminDailyMetric)
        .where(GarminDailyMetric.user_id == user_id, GarminDailyMetric.date >= cutoff, GarminDailyMetric.date <= today)
        .order_by(GarminDailyMetric.date)
    )
    rows = list(result.scalars().all())
    if not rows:
        return {}
    hrvs = [r.hrv_overnight for r in rows if r.hrv_overnight]
    rhrs = [r.resting_heart_rate for r in rows if r.resting_heart_rate]
    sleeps = [r.sleep_duration_minutes / 60 for r in rows if r.sleep_duration_minutes]
    latest_baseline = rows[-1].hrv_baseline_7day
    summary = {}
    if hrvs:
        avg = sum(hrvs) / len(hrvs)
        summary["hrv_avg"] = round(avg, 1)
        summary["hrv_baseline_7d"] = round(latest_baseline, 1) if latest_baseline else None
        if latest_baseline:
            summary["hrv_pct_vs_baseline"] = round((avg - latest_baseline) / latest_baseline * 100, 1)
    if rhrs:
        summary["rhr_avg"] = round(sum(rhrs) / len(rhrs), 1)
    if sleeps:
        summary["sleep_hours_avg"] = round(sum(sleeps) / len(sleeps), 1)
        summary["sleep_hours_min"] = round(min(sleeps), 1)
    return summary


def _wellness_summary(trends: dict) -> dict:
    cur = trends.get("current") or {}
    if not cur or cur.get("n", 0) == 0:
        return {}
    return {
        "n": cur.get("n", 0),
        "sleep_avg": cur.get("sleep_quality_avg"),
        "soreness_avg": cur.get("soreness_avg"),
        "motivation_avg": cur.get("motivation_avg"),
        "stress_avg": cur.get("stress_avg"),
        "frequent_areas": cur.get("frequent_soreness_areas") or [],
        "pain_keyword_days": cur.get("any_pain_keyword_days", 0),
    }


async def _active_flags(db: AsyncSession, user_id: UUID, limit: int) -> list[AnomalyFlag]:
    result = await db.execute(
        select(AnomalyFlag)
        .where(AnomalyFlag.user_id == user_id, AnomalyFlag.resolved_at.is_(None))
        .order_by(desc(AnomalyFlag.raised_at))
        .limit(limit)
    )
    return list(result.scalars().all())


def _flag_to_dict(f: AnomalyFlag) -> dict:
    return {
        "type": f.flag_type,
        "severity": f.severity,
        "raised_at": f.raised_at.strftime("%Y-%m-%d") if f.raised_at else "?",
    }


def _derive_plan_summary(runs: list[Run], training_plan_id, user: User) -> Optional[dict]:
    if training_plan_id is None and not runs:
        return None
    latest = runs[-1] if runs else None
    return {
        "training_plan_id": str(training_plan_id) if training_plan_id else None,
        "plan_name": (latest.plan_name if latest else None),
        "current_week_number": (latest.week_number if latest else None),
        "race_type": getattr(user, "current_race_type", None) or "marathon",
    }


async def _chat_history(
    db: AsyncSession,
    user_id: UUID,
    training_plan_id: Optional[UUID],
    *,
    limit: int,
) -> tuple[list[ChatMessage], Optional[str]]:
    """Return (last N messages oldest-first, optional summary of older messages)."""
    q = select(ChatMessage).where(ChatMessage.user_id == user_id)
    if training_plan_id is not None:
        q = q.where(ChatMessage.training_plan_id == training_plan_id)
    else:
        q = q.where(ChatMessage.training_plan_id.is_(None))
    q = q.order_by(desc(ChatMessage.sent_at)).limit(limit)

    result = await db.execute(q)
    rows = list(result.scalars().all())
    rows.reverse()  # oldest first for chronological prompt rendering

    # Pull most recent summary (if any) covering messages older than what's in `rows`.
    summary_text: Optional[str] = None
    sq = select(ChatSummary).where(ChatSummary.user_id == user_id)
    if training_plan_id is not None:
        sq = sq.where(ChatSummary.training_plan_id == training_plan_id)
    else:
        sq = sq.where(ChatSummary.training_plan_id.is_(None))
    sq = sq.order_by(desc(ChatSummary.generated_at)).limit(1)
    sresult = await db.execute(sq)
    srow = sresult.scalar_one_or_none()
    if srow and srow.summary_text:
        summary_text = srow.summary_text

    return rows, summary_text


def _chat_msg_to_dict(m: ChatMessage) -> dict:
    return {
        "id": str(m.id),
        "role": m.role,
        "content": m.content,
        "sent_at": m.sent_at.strftime("%Y-%m-%d %H:%M") if m.sent_at else "?",
    }


async def _related_event(db: AsyncSession, user_id: UUID, event_id: Optional[UUID]) -> Optional[dict]:
    if event_id is None:
        return None
    event = await db.get(CoachingEvent, event_id)
    if event is None or event.user_id != user_id:
        return None
    return {
        "id": str(event.id),
        "event_type": event.event_type,
        "triggered_at": event.triggered_at.strftime("%Y-%m-%d %H:%M") if event.triggered_at else "?",
        "summary": (event.llm_output[:300] if event.llm_output else None),
    }
