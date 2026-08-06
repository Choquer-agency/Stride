"""
Weekly check-in question builder.

Hybrid model: a fixed core of 5 questions (comparable week over week) plus up to
2 targeted questions derived from this week's data by deterministic rules.
Milestone 2 may swap the rule engine for a Haiku call (CHECKIN_QUESTIONS_MODEL);
the output shape stays identical either way.

Question types the iOS flow renders: scale_1_5, multiple_choice, yes_no
(optionally with a nested free_text follow-up), free_text.
"""

import logging
from datetime import date
from typing import Optional
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.services import wellness_service

logger = logging.getLogger(__name__)

QUESTIONS_VERSION = 1
MAX_TARGETED_QUESTIONS = 2

VALID_QUESTION_TYPES = {"scale_1_5", "multiple_choice", "yes_no", "free_text"}


def core_questions() -> list[dict]:
    """The fixed question set — asked every week so answers trend."""
    return [
        {
            "id": "week_feel",
            "type": "scale_1_5",
            "text": "How did this week feel overall?",
            "low_label": "Brutal",
            "high_label": "Easy",
        },
        {
            "id": "effort_headroom",
            "type": "multiple_choice",
            "text": "Could you have gone harder this week?",
            "options": ["Definitely — it felt easy", "A little", "It was about right", "It was too much"],
        },
        {
            "id": "pain",
            "type": "yes_no",
            "text": "Anything hurting right now?",
            "follow_up_if_yes": {
                "id": "pain_detail",
                "type": "free_text",
                "text": "Where, and how bad?",
            },
        },
        {
            "id": "life_load",
            "type": "scale_1_5",
            "text": "How heavy was life outside running?",
            "low_label": "Calm",
            "high_label": "Chaos",
        },
        {
            "id": "coach_note",
            "type": "free_text",
            "text": "Anything else your coach should know?",
            "optional": True,
        },
    ]


async def build_questions(db: AsyncSession, user_id: UUID, week_ending: date) -> dict:
    """Core questions + up to MAX_TARGETED_QUESTIONS rule-derived targeted ones."""
    questions = core_questions()
    try:
        questions += await _targeted_questions(db, user_id, week_ending)
    except Exception:
        # Targeting is best-effort — a data hiccup must never block the invite.
        logger.exception("checkin targeted-question build failed for user=%s", user_id)
    return {"version": QUESTIONS_VERSION, "questions": questions}


async def _targeted_questions(db: AsyncSession, user_id: UUID, week_ending: date) -> list[dict]:
    # Reuse the weekly review's context loaders (import here to avoid a cycle).
    from app.services.weekly_review_service import (
        _fetch_daily_metrics,
        _fetch_runs_in_window,
    )

    targeted: list[dict] = []

    runs = await _fetch_runs_in_window(db, user_id, days=7, today=week_ending)

    # Rule 1 — a planned workout was logged well short of plan, or scored poorly.
    for r in runs:
        if len(targeted) >= MAX_TARGETED_QUESTIONS:
            return targeted
        planned = r.planned_distance_km or 0
        actual = r.distance_km or 0
        day = r.completed_at.strftime("%A") if r.completed_at else "that day"
        title = r.planned_workout_title or "the planned session"
        if planned > 0 and actual > 0 and actual < planned * 0.7:
            targeted.append({
                "id": f"t_short_{r.completed_at.strftime('%a').lower() if r.completed_at else 'run'}",
                "type": "free_text",
                "text": f"{day}'s {title} came in at {actual:.0f} of {planned:.0f} km — what happened?",
                "targeted": True,
                "source_rule": "short_workout",
            })
            break

    # Rule 2 — HRV trending down vs baseline → recovery probe.
    if len(targeted) < MAX_TARGETED_QUESTIONS:
        metrics = await _fetch_daily_metrics(db, user_id, days=7, today=week_ending)
        hrv_values = [m.hrv_overnight for m in metrics if m.hrv_overnight]
        baseline = metrics[-1].hrv_baseline_7day if metrics else None
        if hrv_values and baseline:
            avg_hrv = sum(hrv_values) / len(hrv_values)
            if (avg_hrv - baseline) / baseline * 100 < -10:
                targeted.append({
                    "id": "t_recovery",
                    "type": "multiple_choice",
                    "text": "Your recovery numbers dipped this week. What do you think is behind it?",
                    "options": ["Training load", "Poor sleep", "Work/life stress", "Coming down with something", "No idea"],
                    "targeted": True,
                    "source_rule": "hrv_drop",
                })

    # Rule 3 — recurring soreness area from wellness check-ins → pain probe.
    if len(targeted) < MAX_TARGETED_QUESTIONS:
        try:
            trends = await wellness_service.compute_trends(db, user_id, window_days=7)
            areas = (trends or {}).get("current", {}).get("frequent_soreness_areas") or []
            if areas:
                area = areas[0]["area"]
                targeted.append({
                    "id": "t_soreness",
                    "type": "yes_no",
                    "text": f"You've flagged {area} soreness more than once this week. Is it getting worse?",
                    "targeted": True,
                    "source_rule": "recurring_soreness",
                })
        except Exception:
            logger.debug("wellness trends unavailable for checkin targeting", exc_info=True)

    return targeted


def validate_answers(questions: dict, answers: dict) -> Optional[str]:
    """
    Validate submitted answers against the stored question payload.
    Returns an error string, or None when valid. Unknown ids are rejected;
    unanswered optional questions are fine.
    """
    if not isinstance(answers, dict):
        return "answers must be an object"

    by_id: dict[str, dict] = {}
    for q in questions.get("questions", []):
        by_id[q["id"]] = q
        follow = q.get("follow_up_if_yes")
        if follow:
            by_id[follow["id"]] = follow

    for qid, value in answers.items():
        q = by_id.get(qid)
        if q is None:
            return f"unknown question id: {qid}"
        qtype = q.get("type")
        if qtype == "scale_1_5" and not (isinstance(value, int) and 1 <= value <= 5):
            return f"{qid}: expected integer 1-5"
        if qtype == "yes_no" and not isinstance(value, bool):
            return f"{qid}: expected boolean"
        if qtype == "multiple_choice" and value not in (q.get("options") or []):
            return f"{qid}: not a valid option"
        if qtype == "free_text" and not isinstance(value, str):
            return f"{qid}: expected string"
    return None
