"""Coach replies to post-run notes.

When a run syncs up carrying an athlete note, the coach reads it alongside the
run data and answers in the chat thread — acknowledging specifics, adding one
insight, and asking a follow-up question when the note invites one (travel,
conditions, niggles). Conversation continues naturally in Ask Coach, where
<adjustment> proposals already work.
"""

import asyncio
import logging
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select

logger = logging.getLogger(__name__)

# Only reply to fresh runs (not history backfills)
_FRESHNESS_HOURS = 36


async def send_note_reply(user_id: uuid.UUID, run_id: uuid.UUID) -> None:
    """Own-session background job. Never raises into the caller."""
    try:
        await _send(user_id, run_id)
    except Exception:
        logger.exception("run-note reply failed for run %s", run_id)


async def _send(user_id: uuid.UUID, run_id: uuid.UUID) -> None:
    from app.database import async_session
    from app.models.chat_message import ChatMessage, ChatRole
    from app.models.run import Run
    from app.models.user import User
    from app.routes.coaching import _finalize_chat_response, _resolve_race_type
    from app.services import chat_context_loader, coaching_models
    from app.services.prompt_builder import prompt_builder
    from app.services.anthropic_client import AnthropicClient
    from app.services.push_service import send_push

    async with async_session() as db:
        user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
        run = (await db.execute(select(Run).where(Run.id == run_id))).scalar_one_or_none()
        if user is None or run is None or not (run.notes or "").strip():
            return
        if run.completed_at < datetime.now(timezone.utc) - timedelta(hours=_FRESHNESS_HOURS):
            return

        # The note joins the chat thread as the athlete's message, so the
        # conversation reads naturally and can simply continue there.
        run_label = run.planned_workout_title or "Run"
        note_header = (
            f"[Post-run note — {run_label}, {run.distance_km:.2f} km "
            f"in {int(run.duration_seconds // 60)}:{int(run.duration_seconds % 60):02d}]"
        )
        athlete_msg = ChatMessage(
            user_id=user.id,
            training_plan_id=None,
            role=ChatRole.ATHLETE.value,
            content=f"{note_header}\n{run.notes.strip()}",
        )
        db.add(athlete_msg)
        await db.commit()

        context = await chat_context_loader.load_context(db, user)
        context_block = chat_context_loader.render_prompt_block(context)
        memo_text = context.get("memo") or ""
        race_type = _resolve_race_type(user)
        system_prompt = prompt_builder.get_chat_prompt(race_type, memo=memo_text)

    pace = run.avg_pace_sec_per_km or 0
    pace_str = f"{int(pace // 60)}:{int(pace % 60):02d}/km" if pace else "n/a"
    user_prompt = (
        f"{context_block}\n\n"
        f"━━━ ATHLETE'S POST-RUN NOTE ━━━\n"
        f"The athlete just finished: {run_label}, {run.distance_km:.2f} km at {pace_str}"
        f" (planned: {run.planned_workout_title or 'free run'}"
        f"{f', score {run.completion_score}' if run.completion_score else ''}).\n"
        f"Their note: \"{run.notes.strip()}\"\n\n"
        f"Reply as their coach, under 120 words. Acknowledge the SPECIFICS they "
        f"mentioned (terrain, heat, travel, how it felt) against the actual run "
        f"data. Give one genuine insight. If the note raises something that "
        f"affects upcoming training (travel, conditions, a niggle), ask ONE "
        f"concrete follow-up question. If an immediate plan change is clearly "
        f"warranted you may propose it with an <adjustment> tag, but prefer "
        f"asking first."
    )

    client = AnthropicClient()
    model = coaching_models.CHAT_MODEL
    output = await client.generate_plan(
        system_prompt,
        user_prompt,
        name="coach-note-reply",
        user_id=str(user_id),
        session_id=f"user:{user_id}:note-reply",
        metadata={"run_id": str(run_id)},
        model=model,
    )
    if not output:
        return

    # Persist coach message + adjustment parsing via the shared chat finalizer
    async for _ in _finalize_chat_response(
        user=user,
        training_plan_id=None,
        related_event_id=None,
        user_prompt=user_prompt,
        output_text=output,
        model=model,
        latency_ms=client.last_metrics.latency_ms if client.last_metrics else None,
        input_tokens=client.last_metrics.input_tokens if client.last_metrics else None,
        output_tokens=client.last_metrics.output_tokens if client.last_metrics else None,
    ):
        pass

    async with async_session() as db:
        user = (await db.execute(select(User).where(User.id == user_id))).scalar_one()
        preview = output.split("<adjustment>")[0].strip()
        preview = preview[:110] + ("…" if len(preview) > 110 else "")
        await send_push(
            db, user,
            title="Coach replied to your run note",
            body=preview,
            deep_link="stride://coach/chat",
            notification_type="note_reply",
            loop_name="note_reply",
        )
