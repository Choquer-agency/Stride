"""
Interactive weekly check-in orchestration.

Flow:
  invite (rest-day cron or manual) → athlete answers a typeform-style
  questionnaire in iOS → submit → run_weekly_review fires with the answers as
  first-class input → review + optional adjustment delivered via the existing
  get-or-stream-review replay. Unanswered invites are expired by the Monday
  fallback cron, which runs the data-only review exactly as before.
"""

import asyncio
import logging
from datetime import datetime, date, timedelta, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session
from app.models.coaching_event import (
    CoachingEvent,
    CoachingEventTriggerSource,
    CoachingEventType,
)
from app.models.user import User
from app.models.weekly_checkin import WeeklyCheckin, WeeklyCheckinStatus
from app.services import checkin_question_service, push_service

logger = logging.getLogger(__name__)

DEFAULT_CHECKIN_DAY = 6  # Sunday (0=Monday .. 6=Sunday)


def effective_checkin_day(user: User) -> int:
    day = getattr(user, "checkin_day_of_week", None)
    return day if day is not None and 0 <= day <= 6 else DEFAULT_CHECKIN_DAY


def week_ending_for(today: date) -> date:
    """The Sunday that closes the training week containing `today`."""
    return today + timedelta(days=(6 - today.weekday()))


async def create_invite(user_id: UUID, *, force: bool = False) -> Optional[UUID]:
    """
    Create this week's check-in invite for a user: build questions, persist the
    row, write the audit CoachingEvent, and push. Returns the checkin id, or
    None when skipped. Own DB session so cron can fire it per-user safely.
    """
    from app.services.weekly_review_jobs import (
        _block_review_recently_fired,
        _user_in_race_prep_window,
    )

    if not force:
        # Same mutual-exclusion chain as the weekly review cron.
        if await _block_review_recently_fired(user_id):
            return None
        if await _user_in_race_prep_window(user_id):
            return None

    async with async_session() as db:
        user = await db.get(User, user_id)
        if user is None:
            return None

        week_ending = week_ending_for(datetime.now(timezone.utc).date())
        existing = await db.execute(
            select(WeeklyCheckin.id).where(
                WeeklyCheckin.user_id == user_id,
                WeeklyCheckin.week_ending == week_ending,
            ).limit(1)
        )
        if existing.scalar_one_or_none() is not None:
            return None

        questions = await checkin_question_service.build_questions(db, user_id, week_ending)

        checkin = WeeklyCheckin(
            user_id=user_id,
            week_ending=week_ending,
            status=WeeklyCheckinStatus.INVITED.value,
            questions=questions,
        )
        db.add(checkin)
        await db.flush()

        event = CoachingEvent(
            user_id=user_id,
            event_type=CoachingEventType.WEEKLY_CHECKIN_INVITE.value,
            trigger_source=CoachingEventTriggerSource.CRON.value if not force else CoachingEventTriggerSource.MANUAL.value,
            flags_that_fired=[],
            shadow_mode=(user.coaching_modes or {}).get("weekly_review", "shadow") != "live",
            context={
                "checkin_id": str(checkin.id),
                "week_ending": week_ending.isoformat(),
                "question_count": len(questions.get("questions", [])),
            },
        )
        db.add(event)
        await db.flush()
        checkin.invite_event_id = event.id

        delivered, reason = await push_service.send_push(
            db, user,
            title="Sit down with your coach",
            body="Two minutes on your week — then your coach takes it from there.",
            deep_link=f"stride://coach/checkin/{checkin.id}",
            notification_type="weekly_checkin",
            loop_name="weekly_review",
        )
        event.notification_delivered = delivered
        event.notification_reason = reason

        await db.commit()
        checkin_id = checkin.id

    logger.info("weekly_checkin invite created for user=%s checkin=%s pushed=%s", user_id, checkin_id, delivered)
    return checkin_id


async def get_current(db: AsyncSession, user_id: UUID) -> Optional[WeeklyCheckin]:
    """The most recent check-in for this user's current week (any status)."""
    week_ending = week_ending_for(datetime.now(timezone.utc).date())
    result = await db.execute(
        select(WeeklyCheckin)
        .where(WeeklyCheckin.user_id == user_id, WeeklyCheckin.week_ending == week_ending)
        .order_by(desc(WeeklyCheckin.invited_at))
        .limit(1)
    )
    return result.scalar_one_or_none()


async def save_answers(db: AsyncSession, user_id: UUID, checkin_id: UUID, answers: dict) -> tuple[bool, str]:
    """Merge partial answers (resume support). Returns (ok, error)."""
    checkin = await db.get(WeeklyCheckin, checkin_id)
    if checkin is None or checkin.user_id != user_id:
        return False, "checkin not found"
    if checkin.status in (WeeklyCheckinStatus.SUBMITTED.value, WeeklyCheckinStatus.EXPIRED.value):
        return False, f"checkin is {checkin.status}"
    error = checkin_question_service.validate_answers(checkin.questions or {}, answers)
    if error:
        return False, error
    merged = dict(checkin.answers or {})
    merged.update(answers)
    checkin.answers = merged
    checkin.status = WeeklyCheckinStatus.IN_PROGRESS.value
    return True, ""


async def submit(db: AsyncSession, user_id: UUID, checkin_id: UUID, answers: dict) -> tuple[bool, str]:
    """
    Final submit: validate + persist answers, mark submitted, and fire the
    weekly review in the background with the check-in as input.
    """
    checkin = await db.get(WeeklyCheckin, checkin_id)
    if checkin is None or checkin.user_id != user_id:
        return False, "checkin not found"
    if checkin.status == WeeklyCheckinStatus.SUBMITTED.value:
        return False, "already submitted"
    if checkin.status == WeeklyCheckinStatus.EXPIRED.value:
        return False, "checkin expired"

    error = checkin_question_service.validate_answers(checkin.questions or {}, answers)
    if error:
        return False, error

    merged = dict(checkin.answers or {})
    merged.update(answers)
    checkin.answers = merged
    checkin.status = WeeklyCheckinStatus.SUBMITTED.value
    checkin.submitted_at = datetime.now(timezone.utc)
    await db.commit()

    from app.services.weekly_review_service import run_weekly_review

    asyncio.create_task(
        run_weekly_review(
            user_id,
            source=CoachingEventTriggerSource.USER_ACTION.value,
            force=True,  # the athlete explicitly asked — don't skip on quiet weeks
            checkin_id=checkin_id,
        )
    )
    return True, ""
