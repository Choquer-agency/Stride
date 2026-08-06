"""
Coaching endpoints — feedback collection, inbox, plan adjustments, pause/resume.

Coaching loop endpoints (run-weekly-review, run-post-run-check, etc.) are added
in their respective phases (Phase 2, 3, etc.). This file holds the cross-cutting
endpoints that ship in Phase 0.
"""

import asyncio
import json
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy import select, desc, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.chat_message import ChatMessage, ChatRole
from app.models.coaching_event import (
    CoachingEvent,
    CoachingEventFeedback,
    CoachingEventTriggerSource,
    CoachingEventType,
)
from app.models.plan_adjustment import PlanAdjustment, PlanAdjustmentStatus
from app.models.user import User
from app.services import (
    chat_context_loader,
    chat_suggestion_engine,
    chat_summarizer,
    coach_memo_service,
    coaching_models,
    plan_adjustment_service,
    post_run_check,
    weekly_checkin_service,
    weekly_review_service,
)
from app.services.anthropic_client import AnthropicClient
from app.services.auth_service import get_current_user
from app.services.prompt_builder import prompt_builder

router = APIRouter(prefix="/api/coach", tags=["coaching"])


# ── Feedback (first-3-events UX) ────────────────────────────────────────────

class FeedbackRequest(BaseModel):
    event_id: UUID
    feedback: str = Field(..., pattern="^(positive|negative|unclear)$")
    note: Optional[str] = Field(default=None, max_length=500)


@router.post("/feedback")
async def submit_feedback(
    body: FeedbackRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """
    Athlete tap on 👍 👎 🙏 row of a coaching event.
    Updates `coaching_events.athlete_feedback` and increments `User.coaching_feedback_seen[loop_name]`.
    """
    event = await db.get(CoachingEvent, body.event_id)
    if event is None or event.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Coaching event not found.")

    event.athlete_feedback = body.feedback
    if body.note:
        event.athlete_response = body.note

    # Increment seen counter for this loop type
    feedback_seen = dict(current_user.coaching_feedback_seen or {})
    loop_name = event.event_type  # event_type doubles as loop name for tracking
    feedback_seen[loop_name] = feedback_seen.get(loop_name, 0) + 1
    current_user.coaching_feedback_seen = feedback_seen

    db.add(event)
    db.add(current_user)
    await db.flush()

    return {"ok": True, "feedback_seen_count": feedback_seen[loop_name]}


# ── Coach inbox ─────────────────────────────────────────────────────────────

class InboxItem(BaseModel):
    id: UUID
    event_type: str
    triggered_at: datetime
    notification_delivered: bool
    has_llm_output: bool
    flags_that_fired: list = Field(default_factory=list)
    athlete_feedback: Optional[str] = None
    summary: Optional[str] = None  # first 200 chars of llm_output


class InboxResponse(BaseModel):
    items: list[InboxItem]
    next_cursor: Optional[str] = None


@router.get("/inbox", response_model=InboxResponse)
async def get_inbox(
    limit: int = 20,
    before: Optional[datetime] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> InboxResponse:
    """Paginated coaching inbox sorted newest first. `before` cursor is event triggered_at."""
    if limit > 50:
        limit = 50

    stmt = (
        select(CoachingEvent)
        .where(CoachingEvent.user_id == current_user.id)
        .order_by(desc(CoachingEvent.triggered_at))
        .limit(limit + 1)
    )
    if before:
        stmt = stmt.where(CoachingEvent.triggered_at < before)

    rows = list((await db.execute(stmt)).scalars().all())
    has_more = len(rows) > limit
    rows = rows[:limit]

    items = [
        InboxItem(
            id=r.id,
            event_type=r.event_type,
            triggered_at=r.triggered_at,
            notification_delivered=r.notification_delivered,
            has_llm_output=bool(r.llm_output),
            flags_that_fired=r.flags_that_fired or [],
            athlete_feedback=r.athlete_feedback,
            summary=(r.llm_output[:200] if r.llm_output else None),
        )
        for r in rows
    ]
    next_cursor = rows[-1].triggered_at.isoformat() if has_more and rows else None
    return InboxResponse(items=items, next_cursor=next_cursor)


# ── Pause / resume (Phase 3 wires the actual loop skipping) ─────────────────

class PauseRequest(BaseModel):
    duration_days: Optional[int] = Field(default=None, ge=1, le=30)
    until_resume: bool = Field(default=False)


@router.post("/pause")
async def pause_coach(
    body: PauseRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Pause the coach. Critical-severity flags still fire after a 24h grace per Phase 3 logic."""
    if body.until_resume and body.duration_days:
        raise HTTPException(status_code=400, detail="Provide either duration_days or until_resume, not both.")

    if body.until_resume:
        # Sentinel: epoch 0 means "until manually resumed"
        from datetime import timedelta
        # Use far future as sentinel to avoid epoch ambiguity across timezones
        current_user.coaching_paused_until = datetime.now(timezone.utc) + timedelta(days=365 * 100)
    elif body.duration_days:
        from datetime import timedelta
        current_user.coaching_paused_until = datetime.now(timezone.utc) + timedelta(days=body.duration_days)
    else:
        raise HTTPException(status_code=400, detail="Provide duration_days or set until_resume=true.")

    current_user.coaching_resume_pending = False
    db.add(current_user)
    await db.flush()
    return {"ok": True, "paused_until": current_user.coaching_paused_until.isoformat()}


@router.post("/resume")
async def resume_coach(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Resume the coach. Next coaching event will preface with 'noted you paused'."""
    current_user.coaching_paused_until = None
    current_user.coaching_resume_pending = True
    db.add(current_user)
    await db.flush()
    return {"ok": True}


@router.get("/pause-status")
async def pause_status(current_user: User = Depends(get_current_user)) -> dict:
    paused = current_user.coaching_paused_until is not None
    until = current_user.coaching_paused_until.isoformat() if paused else None
    return {
        "paused": paused,
        "paused_until": until,
        "resume_pending": current_user.coaching_resume_pending,
        "modes": current_user.coaching_modes or {},
    }


# ── v2 Phase 2: Weekly review endpoints ────────────────────────────────────

class RunWeeklyReviewRequest(BaseModel):
    """Admin/debug body for manually triggering a review (cron uses no body)."""
    user_id: Optional[UUID] = None  # if absent, current_user
    force: bool = False             # bypass skip checks
    week_offset: int = 0            # 0 = this week ending today, 1 = last week, ...


class RunWeeklyReviewResponse(BaseModel):
    event_id: Optional[UUID]
    skipped: bool


@router.post("/run-weekly-review", response_model=RunWeeklyReviewResponse)
async def run_weekly_review_endpoint(
    body: RunWeeklyReviewRequest,
    current_user: User = Depends(get_current_user),
) -> RunWeeklyReviewResponse:
    """
    Manually trigger the weekly review pipeline. Useful for first-run testing,
    debugging, or running a review after a missed cron.

    Defaults to current_user; admin can target another user via body.user_id.
    """
    target_id = body.user_id or current_user.id
    if body.user_id and body.user_id != current_user.id and not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Only admins can target other users")

    event_id = await weekly_review_service.run_weekly_review(
        target_id,
        source=CoachingEventTriggerSource.MANUAL.value,
        force=body.force,
        week_offset=body.week_offset,
    )
    return RunWeeklyReviewResponse(event_id=event_id, skipped=event_id is None)


# ── Interactive weekly check-in ─────────────────────────────────────────────


class CheckinResponse(BaseModel):
    id: Optional[UUID] = None
    week_ending: Optional[str] = None
    status: str = "none"
    questions: dict = {}
    answers: dict = {}
    review_event_id: Optional[UUID] = None


def _checkin_response(checkin) -> CheckinResponse:
    if checkin is None:
        return CheckinResponse()
    return CheckinResponse(
        id=checkin.id,
        week_ending=checkin.week_ending.isoformat(),
        status=checkin.status,
        questions=checkin.questions or {},
        answers=checkin.answers or {},
        review_event_id=checkin.review_event_id,
    )


@router.get("/checkin/current", response_model=CheckinResponse)
async def get_current_checkin(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CheckinResponse:
    """This week's check-in for the athlete, or {status: 'none'}."""
    checkin = await weekly_checkin_service.get_current(db, current_user.id)
    return _checkin_response(checkin)


class CheckinAnswersRequest(BaseModel):
    answers: dict


@router.patch("/checkin/{checkin_id}/answers", response_model=CheckinResponse)
async def save_checkin_answers(
    checkin_id: UUID,
    body: CheckinAnswersRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CheckinResponse:
    """Merge partial answers so a half-finished check-in survives app restarts."""
    ok, error = await weekly_checkin_service.save_answers(db, current_user.id, checkin_id, body.answers)
    if not ok:
        raise HTTPException(status_code=400, detail=error)
    await db.commit()
    checkin = await weekly_checkin_service.get_current(db, current_user.id)
    return _checkin_response(checkin)


@router.post("/checkin/{checkin_id}/submit", response_model=CheckinResponse)
async def submit_checkin(
    checkin_id: UUID,
    body: CheckinAnswersRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CheckinResponse:
    """
    Final submit — persists answers and fires the weekly review in the
    background with the check-in as first-class input. iOS then polls
    GET /checkin/current until review_event_id is populated and replays the
    review via GET /get-or-stream-review/{event_id}.
    """
    ok, error = await weekly_checkin_service.submit(db, current_user.id, checkin_id, body.answers)
    if not ok:
        raise HTTPException(status_code=400, detail=error)
    checkin = await weekly_checkin_service.get_current(db, current_user.id)
    return _checkin_response(checkin)


class RunCheckinInviteRequest(BaseModel):
    user_id: Optional[UUID] = None
    force: bool = False


@router.post("/run-checkin-invite")
async def run_checkin_invite_endpoint(
    body: RunCheckinInviteRequest,
    current_user: User = Depends(get_current_user),
) -> dict:
    """Manually trigger a check-in invite (testing / missed cron)."""
    target_id = body.user_id or current_user.id
    if body.user_id and body.user_id != current_user.id and not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Only admins can target other users")
    checkin_id = await weekly_checkin_service.create_invite(target_id, force=body.force)
    return {"checkin_id": str(checkin_id) if checkin_id else None, "skipped": checkin_id is None}


class CheckinDayRequest(BaseModel):
    day_of_week: int = Field(..., ge=0, le=6, description="0=Monday .. 6=Sunday")


@router.patch("/checkin-day")
async def set_checkin_day(
    body: CheckinDayRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """iOS pins the athlete's rest day so the invite cron knows when to fire."""
    await db.execute(
        update(User).where(User.id == current_user.id).values(checkin_day_of_week=body.day_of_week)
    )
    await db.commit()
    return {"ok": True, "checkin_day_of_week": body.day_of_week}


# ── v2 Phase 7: Block review ────────────────────────────────────────────────


class RunBlockReviewRequest(BaseModel):
    user_id: Optional[UUID] = None
    force: bool = False


class RunBlockReviewResponse(BaseModel):
    event_id: Optional[UUID]
    skipped: bool


@router.post("/run-block-review", response_model=RunBlockReviewResponse)
async def run_block_review_endpoint(
    body: RunBlockReviewRequest,
    current_user: User = Depends(get_current_user),
) -> RunBlockReviewResponse:
    """
    Manually trigger the block review pipeline. Useful for first-run testing
    or running after a missed daily cron. Defaults to current_user.
    """
    target_id = body.user_id or current_user.id
    if body.user_id and body.user_id != current_user.id and not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Only admins can target other users")

    event_id = await block_review_service.run_block_review(
        target_id,
        source=CoachingEventTriggerSource.MANUAL.value,
        force=body.force,
    )
    return RunBlockReviewResponse(event_id=event_id, skipped=event_id is None)


@router.get("/get-or-stream-review/{event_id}")
async def get_or_stream_review(
    event_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Hybrid endpoint for the iOS WeeklyReviewCardView.

    - If `coaching_events.llm_output` is populated (cron-driven case after the
      LLM call finished), stream the saved text client-side at ~30 tokens/sec
      so it still feels live, then send `done`.
    - If `llm_output` is empty (rare race where the user taps the push DURING
      generation), return a 425 Too Early so iOS retries — Phase 2's cron path
      always finishes generating before sending the push, so this is a safety net.

    All chunks use the same `data: {"content": "..."}\\n\\n` SSE shape as
    `/generate-plan` so iOS can reuse the existing chunk decoder.
    """
    event = await db.get(CoachingEvent, event_id)
    if event is None or event.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Coaching event not found")

    if not event.llm_output:
        # Generation hadn't completed yet (cron typically takes 5-15s after push).
        raise HTTPException(status_code=425, detail="Review still generating — retry in a moment")

    saved_text = event.llm_output

    async def replay():
        try:
            # Chunk by ~6 chars (a fast token feel), 33ms apart for ~30 tok/s.
            chunk_size = 6
            for i in range(0, len(saved_text), chunk_size):
                chunk = saved_text[i:i + chunk_size]
                yield f"data: {json.dumps({'content': chunk})}\n\n"
                await asyncio.sleep(0.033)
            yield f"data: {json.dumps({'done': True})}\n\n"
        except Exception as exc:
            yield f"data: {json.dumps({'error': str(exc)})}\n\n"

    return StreamingResponse(
        replay(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive", "X-Accel-Buffering": "no"},
    )


@router.post("/event/{event_id}/mark-read")
async def mark_event_read(
    event_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Mark a coaching event as read (clears unread badge in inbox)."""
    event = await db.get(CoachingEvent, event_id)
    if event is None or event.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Coaching event not found")
    # We don't have a dedicated read column on the event — track read state
    # via context.read_at so we don't need another migration.
    ctx = dict(event.context or {})
    if "read_at" not in ctx:
        ctx["read_at"] = datetime.now(timezone.utc).isoformat()
        event.context = ctx
        db.add(event)
        await db.flush()
    return {"ok": True, "read_at": ctx["read_at"]}


# ── v2 Phase 3: Post-run check + plan adjustments ──────────────────────────

class RunPostRunCheckRequest(BaseModel):
    workout_id: UUID
    race_event_id: Optional[UUID] = None
    force: bool = False


class RunPostRunCheckResponse(BaseModel):
    event_id: Optional[UUID]


@router.post("/run-post-run-check", response_model=RunPostRunCheckResponse)
async def run_post_run_check_endpoint(
    body: RunPostRunCheckRequest,
    current_user: User = Depends(get_current_user),
) -> RunPostRunCheckResponse:
    """
    Manually trigger the post-run check for a Garmin workout. Useful for
    debugging or replaying after a webhook drop. The Garmin webhook calls
    `run_post_run_check` directly via `asyncio.create_task` in production.
    """
    event_id = await post_run_check.run_post_run_check(
        user_id=current_user.id,
        workout_id=body.workout_id,
        race_event_id=body.race_event_id,
        source=CoachingEventTriggerSource.MANUAL.value,
        force=body.force,
    )
    return RunPostRunCheckResponse(event_id=event_id)


# ── Plan adjustments ────────────────────────────────────────────────────────


class PlanAdjustmentDTO(BaseModel):
    id: UUID
    proposed_at: datetime
    expires_at: datetime
    status: str
    summary_text: str
    structured_diff: dict
    affected_workout_ids: Optional[list[UUID]] = None
    trigger_event_id: Optional[UUID] = None


class PendingAdjustmentsResponse(BaseModel):
    items: list[PlanAdjustmentDTO]


@router.get("/plan/pending-adjustments", response_model=PendingAdjustmentsResponse)
async def get_pending_adjustments(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PendingAdjustmentsResponse:
    rows = await plan_adjustment_service.list_pending(db, current_user)
    return PendingAdjustmentsResponse(items=[
        PlanAdjustmentDTO(
            id=r.id,
            proposed_at=r.proposed_at,
            expires_at=r.expires_at,
            status=r.status,
            summary_text=r.summary_text or "",
            structured_diff=r.structured_diff or {},
            affected_workout_ids=r.affected_workout_ids,
            trigger_event_id=r.trigger_event_id,
        )
        for r in rows
    ])


class AcceptAdjustmentRequest(BaseModel):
    adjustment_id: UUID
    applied_diff_actual: Optional[dict] = None


@router.post("/plan/accept-adjustment")
async def accept_adjustment(
    body: AcceptAdjustmentRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    try:
        row = await plan_adjustment_service.accept(
            db, current_user, body.adjustment_id,
            applied_diff_actual=body.applied_diff_actual,
        )
    except LookupError:
        raise HTTPException(status_code=404, detail="Adjustment not found")
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    return {"ok": True, "status": row.status}


class RejectAdjustmentRequest(BaseModel):
    adjustment_id: UUID
    reason: Optional[str] = Field(default=None, max_length=500)


@router.post("/plan/reject-adjustment")
async def reject_adjustment(
    body: RejectAdjustmentRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    try:
        row = await plan_adjustment_service.reject(
            db, current_user, body.adjustment_id, reason=body.reason,
        )
    except LookupError:
        raise HTTPException(status_code=404, detail="Adjustment not found")
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    return {"ok": True, "status": row.status}


# ── v2 Phase 5: Conversational chat ─────────────────────────────────────────

# Cost cap + spam guard. Both are enforced server-side; iOS also checks the
# 15s cooldown client-side for a snappier UX.
_CHAT_DAILY_LIMIT = 50
_CHAT_COOLDOWN_SECONDS = 15
_RESPONSE_TAG_RE = re.compile(r"<adjustment>\s*(.*?)\s*</adjustment>", re.DOTALL) if (re := __import__("re")) else None  # forward-ref to module-level import
import re as _re
import json as _json
_ADJUSTMENT_TAG_RE = _re.compile(r"<adjustment>\s*(.*?)\s*</adjustment>", _re.DOTALL)


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    training_plan_id: Optional[UUID] = None
    related_event_id: Optional[UUID] = None


@router.post("/chat")
async def coach_chat(
    body: ChatRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    SSE-streaming chat endpoint. Pipeline:
      1. Validate (50/day cap + 15s cooldown server-side)
      2. Load full athlete context via chat_context_loader
      3. Insert athlete ChatMessage
      4. Compose prompt + stream Opus response
      5. Persist coach ChatMessage on completion
      6. Parse <adjustment> tag → propose PlanAdjustment if present
      7. Trigger chat_summarizer in background if thread > 50 messages
    """
    # Rate-limit + daily cap
    await _enforce_chat_limits(db, current_user.id)

    # Load context
    context = await chat_context_loader.load_context(
        db, current_user,
        training_plan_id=body.training_plan_id,
        related_event_id=body.related_event_id,
    )
    context_block = chat_context_loader.render_prompt_block(context)

    # Insert athlete message immediately so it shows up in subsequent loads
    athlete_msg = ChatMessage(
        user_id=current_user.id,
        training_plan_id=body.training_plan_id,
        role=ChatRole.ATHLETE.value,
        content=body.message,
        related_event_id=body.related_event_id,
    )
    db.add(athlete_msg)
    await db.flush()
    await db.commit()

    # Compose prompt
    memo_text = context.get("memo") or ""
    race_type = _resolve_race_type(current_user)
    system_prompt = prompt_builder.get_chat_prompt(race_type, memo=memo_text)
    user_prompt = (
        f"{context_block}\n\n"
        f"━━━ ATHLETE'S MESSAGE ━━━\n"
        f"{body.message}\n\n"
        f"Write your response. Reference specific data from the context above."
    )

    client = AnthropicClient()
    model = coaching_models.CHAT_MODEL
    user_id = str(current_user.id)
    plan_id_str = str(body.training_plan_id) if body.training_plan_id else "none"

    async def stream():
        full = ""
        try:
            async for chunk in client.generate_plan_stream(
                system_prompt,
                user_prompt,
                name="coach-chat",
                user_id=user_id,
                session_id=f"user:{user_id}:chat:{plan_id_str}",
                metadata={"training_plan_id": plan_id_str},
                model=model,
            ):
                full += chunk
                yield f"data: {_json.dumps({'content': chunk})}\n\n"

            # On completion, persist + parse adjustment + maybe summarize.
            async for trailer in _finalize_chat_response(
                user=current_user,
                training_plan_id=body.training_plan_id,
                related_event_id=body.related_event_id,
                user_prompt=user_prompt,
                output_text=full,
                model=model,
                latency_ms=client.last_metrics.latency_ms if client.last_metrics else None,
                input_tokens=client.last_metrics.input_tokens if client.last_metrics else None,
                output_tokens=client.last_metrics.output_tokens if client.last_metrics else None,
            ):
                yield trailer
            yield f"data: {_json.dumps({'done': True})}\n\n"
        except Exception as exc:
            yield f"data: {_json.dumps({'error': str(exc)})}\n\n"

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive", "X-Accel-Buffering": "no"},
    )


async def _enforce_chat_limits(db: AsyncSession, user_id: UUID) -> None:
    """Daily cap (50 msgs) + 15s cooldown between athlete messages."""
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    cutoff_cooldown = datetime.now(timezone.utc) - timedelta(seconds=_CHAT_COOLDOWN_SECONDS)

    daily_count_q = select(ChatMessage.id).where(
        ChatMessage.user_id == user_id,
        ChatMessage.role == ChatRole.ATHLETE.value,
        ChatMessage.sent_at >= today_start,
    )
    daily_count = len((await db.execute(daily_count_q)).scalars().all())
    if daily_count >= _CHAT_DAILY_LIMIT:
        raise HTTPException(
            status_code=429,
            detail=f"Daily chat limit reached ({_CHAT_DAILY_LIMIT}). Try again tomorrow.",
        )

    cooldown_q = select(ChatMessage.id).where(
        ChatMessage.user_id == user_id,
        ChatMessage.role == ChatRole.ATHLETE.value,
        ChatMessage.sent_at > cutoff_cooldown,
    ).limit(1)
    if (await db.execute(cooldown_q)).scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=429,
            detail=f"Slow down — wait {_CHAT_COOLDOWN_SECONDS}s between messages.",
        )


async def _finalize_chat_response(
    *,
    user: User,
    training_plan_id: Optional[UUID],
    related_event_id: Optional[UUID],
    user_prompt: str,
    output_text: str,
    model: str,
    latency_ms: Optional[int],
    input_tokens: Optional[int],
    output_tokens: Optional[int],
):
    """
    Open a fresh DB session (we already returned the original from the route)
    to persist the coach message, parse adjustment, log coaching_event, kick
    off summarization if needed. Yields any extra SSE chunks the client should
    receive (e.g., the related_adjustment_id when an adjustment proposal lands).
    """
    from app.database import async_session

    async with async_session() as db:
        # Parse <adjustment> tag (if any)
        adjustment_dict = _parse_adjustment_tag(output_text)
        clean_output = _ADJUSTMENT_TAG_RE.sub("", output_text).strip()

        # coach_message
        coach_msg = ChatMessage(
            user_id=user.id,
            training_plan_id=training_plan_id,
            role=ChatRole.COACH.value,
            content=clean_output,
            related_event_id=related_event_id,
            context_snapshot={"prompt_chars": len(user_prompt), "model": model},
        )
        db.add(coach_msg)
        await db.flush()

        related_adjustment_id: Optional[UUID] = None
        if adjustment_dict:
            try:
                # We don't have a coaching_event id yet for this chat turn —
                # log one first so PlanAdjustment.trigger_event_id is valid.
                event = CoachingEvent(
                    user_id=user.id,
                    event_type=CoachingEventType.CHAT.value,
                    trigger_source=CoachingEventTriggerSource.USER_MESSAGE.value,
                    flags_that_fired=[],
                    prompt_used=f"coach_chat.txt@{prompt_builder.prompt_sha('coach_chat.txt')}",
                    llm_model_used=model,
                    llm_input=user_prompt[:40000],
                    llm_output=clean_output,
                    llm_input_tokens=input_tokens,
                    llm_output_tokens=output_tokens,
                    llm_cost_usd=coaching_models.estimate_cost_usd(model, input_tokens or 0, output_tokens or 0),
                    llm_latency_ms=latency_ms,
                    notification_delivered=False,
                    shadow_mode=False,
                    context={"chat_message_id": str(coach_msg.id)},
                )
                db.add(event)
                await db.flush()

                adj = await plan_adjustment_service.propose(
                    db, user,
                    trigger_event_id=event.id,
                    summary=adjustment_dict.get("summary", ""),
                    structured_diff=adjustment_dict.get("structured_diff", {}),
                    affected_workout_dates=adjustment_dict.get("affected_workout_dates"),
                )
                related_adjustment_id = adj.id
                coach_msg.related_adjustment_id = adj.id
                db.add(coach_msg)
            except Exception:
                logger = __import__("logging").getLogger(__name__)
                logger.exception("Failed to propose adjustment from chat")
        else:
            # No adjustment — still log a coaching_event for cost/audit
            event = CoachingEvent(
                user_id=user.id,
                event_type=CoachingEventType.CHAT.value,
                trigger_source=CoachingEventTriggerSource.USER_MESSAGE.value,
                flags_that_fired=[],
                prompt_used=f"coach_chat.txt@{prompt_builder.prompt_sha('coach_chat.txt')}",
                llm_model_used=model,
                llm_input=user_prompt[:40000],
                llm_output=clean_output,
                llm_input_tokens=input_tokens,
                llm_output_tokens=output_tokens,
                llm_cost_usd=coaching_models.estimate_cost_usd(model, input_tokens or 0, output_tokens or 0),
                llm_latency_ms=latency_ms,
                notification_delivered=False,
                shadow_mode=False,
                context={"chat_message_id": str(coach_msg.id)},
            )
            db.add(event)

        await db.commit()

        # Yield the trailing payload with metadata before {done: true}
        trailer = {
            "coach_message_id": str(coach_msg.id),
        }
        if related_adjustment_id:
            trailer["related_adjustment_id"] = str(related_adjustment_id)
        yield f"data: {_json.dumps({'meta': trailer})}\n\n"

        # Summarize older history if thread > 50 messages (background, separate session)
        try:
            async with async_session() as bg:
                await chat_summarizer.maybe_summarize_thread(bg, user.id, training_plan_id)
                await bg.commit()
        except Exception:
            logger = __import__("logging").getLogger(__name__)
            logger.exception("Background summarize failed")


def _parse_adjustment_tag(output: str) -> Optional[dict]:
    if not output:
        return None
    m = _ADJUSTMENT_TAG_RE.search(output)
    if not m:
        return None
    try:
        parsed = _json.loads(m.group(1))
        return parsed if isinstance(parsed, dict) else None
    except (_json.JSONDecodeError, ValueError):
        return None


def _resolve_race_type(user: User):
    from app.models.schemas import RaceType
    raw = getattr(user, "current_race_type", None)
    if raw:
        try:
            return RaceType(raw)
        except ValueError:
            pass
    return RaceType.MARATHON


# ── Chat history + suggestions ──────────────────────────────────────────────

class ChatMessageDTO(BaseModel):
    id: UUID
    sent_at: datetime
    role: str
    content: str
    related_event_id: Optional[UUID] = None
    related_adjustment_id: Optional[UUID] = None


class ChatHistoryResponse(BaseModel):
    items: list[ChatMessageDTO]
    summary: Optional[str] = None
    has_more: bool = False


@router.get("/chat/history", response_model=ChatHistoryResponse)
async def chat_history(
    training_plan_id: Optional[UUID] = None,
    limit: int = 50,
    before: Optional[datetime] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ChatHistoryResponse:
    if limit > 100:
        limit = 100
    q = select(ChatMessage).where(ChatMessage.user_id == current_user.id)
    if training_plan_id is not None:
        q = q.where(ChatMessage.training_plan_id == training_plan_id)
    else:
        q = q.where(ChatMessage.training_plan_id.is_(None))
    if before is not None:
        q = q.where(ChatMessage.sent_at < before)
    q = q.order_by(desc(ChatMessage.sent_at)).limit(limit + 1)

    rows = list((await db.execute(q)).scalars().all())
    has_more = len(rows) > limit
    rows = rows[:limit]
    rows.reverse()  # chronological for client display

    # Pull rolling summary if any (so older history below `before` has context)
    summary_text: Optional[str] = None
    from app.models.chat_summary import ChatSummary
    sq = select(ChatSummary).where(ChatSummary.user_id == current_user.id)
    if training_plan_id is not None:
        sq = sq.where(ChatSummary.training_plan_id == training_plan_id)
    else:
        sq = sq.where(ChatSummary.training_plan_id.is_(None))
    sq = sq.order_by(desc(ChatSummary.generated_at)).limit(1)
    s = (await db.execute(sq)).scalar_one_or_none()
    if s:
        summary_text = s.summary_text

    return ChatHistoryResponse(
        items=[
            ChatMessageDTO(
                id=m.id,
                sent_at=m.sent_at,
                role=m.role,
                content=m.content,
                related_event_id=m.related_event_id,
                related_adjustment_id=m.related_adjustment_id,
            )
            for m in rows
        ],
        summary=summary_text,
        has_more=has_more,
    )


class ChatSuggestionsResponse(BaseModel):
    items: list[str]


@router.get("/chat/suggestions", response_model=ChatSuggestionsResponse)
async def chat_suggestions(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ChatSuggestionsResponse:
    chips = await chat_suggestion_engine.get_suggestions(db, current_user)
    return ChatSuggestionsResponse(items=chips)
