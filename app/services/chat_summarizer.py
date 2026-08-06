"""
Rolling Haiku summary of older chat history.

When a (user, training_plan_id) thread exceeds 50 messages, we Haiku-summarize
the OLDEST 25 into a single chat_summaries row and the chat prompt prepends
that summary instead of including those messages verbatim.

Idempotent — only summarizes messages whose IDs aren't already in the latest
summary's covers_message_ids array.
"""

import logging
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.chat_message import ChatMessage, ChatRole
from app.models.chat_summary import ChatSummary
from app.services import coaching_models
from app.services.anthropic_client import AnthropicClient

logger = logging.getLogger(__name__)


_THREAD_HISTORY_THRESHOLD = 50    # summarize when a thread has more than this many messages
_BATCH_SIZE = 25                  # how many oldest messages to summarize per pass


async def maybe_summarize_thread(
    db: AsyncSession,
    user_id: UUID,
    training_plan_id: Optional[UUID],
) -> Optional[ChatSummary]:
    """
    Inspect the thread; if message count > 50, Haiku-summarize the oldest 25
    messages NOT already covered by an existing summary. Returns the new summary
    row or None if no work was needed.
    """
    # Total message count
    count_q = select(func.count(ChatMessage.id)).where(ChatMessage.user_id == user_id)
    if training_plan_id is None:
        count_q = count_q.where(ChatMessage.training_plan_id.is_(None))
    else:
        count_q = count_q.where(ChatMessage.training_plan_id == training_plan_id)
    total = (await db.execute(count_q)).scalar_one() or 0
    if total <= _THREAD_HISTORY_THRESHOLD:
        return None

    # Existing summary covers what?
    existing = await _latest_summary(db, user_id, training_plan_id)
    covered: set[UUID] = set(existing.covers_message_ids) if existing and existing.covers_message_ids else set()

    # Pull the oldest UNCOVERED messages
    q = select(ChatMessage).where(ChatMessage.user_id == user_id)
    if training_plan_id is None:
        q = q.where(ChatMessage.training_plan_id.is_(None))
    else:
        q = q.where(ChatMessage.training_plan_id == training_plan_id)
    q = q.order_by(ChatMessage.sent_at).limit(_BATCH_SIZE * 4)

    candidates = list((await db.execute(q)).scalars().all())
    to_summarize = [m for m in candidates if m.id not in covered][:_BATCH_SIZE]
    if len(to_summarize) < _BATCH_SIZE:
        # Not enough new history yet to warrant summarizing
        return None

    transcript = _render_transcript(to_summarize)
    prior_summary_text = existing.summary_text if existing else None

    client = AnthropicClient()
    system_prompt = (
        "You compress a coaching-chat transcript into a tight rolling summary. "
        "Keep specific data points, decisions made, plan adjustments accepted/rejected, "
        "and any open threads. Drop pleasantries. 200-400 words. Plain prose."
    )
    user_prompt = (
        (f"PRIOR SUMMARY (older than the transcript below):\n{prior_summary_text}\n\n" if prior_summary_text else "")
        + f"TRANSCRIPT TO INCORPORATE:\n{transcript}\n\nWrite the updated rolling summary."
    )

    try:
        summary_text = await client.generate_plan(
            system_prompt,
            user_prompt,
            name="chat-summarize",
            user_id=str(user_id),
            model=coaching_models.CHAT_HISTORY_SUMMARIZE_MODEL,
            metadata={"training_plan_id": str(training_plan_id) if training_plan_id else None},
        )
    except Exception:
        logger.exception("Chat summarize failed for user=%s", user_id)
        return None

    new_covered = list(covered.union(m.id for m in to_summarize))
    row = ChatSummary(
        user_id=user_id,
        training_plan_id=training_plan_id,
        covers_message_ids=new_covered,
        summary_text=summary_text.strip(),
    )
    db.add(row)
    await db.flush()
    logger.info(
        "Chat summarized: user=%s plan=%s now_covers=%d new_chars=%d",
        user_id, training_plan_id, len(new_covered), len(summary_text),
    )
    return row


# ── Helpers ────────────────────────────────────────────────────────────────

async def _latest_summary(
    db: AsyncSession,
    user_id: UUID,
    training_plan_id: Optional[UUID],
) -> Optional[ChatSummary]:
    q = select(ChatSummary).where(ChatSummary.user_id == user_id)
    if training_plan_id is None:
        q = q.where(ChatSummary.training_plan_id.is_(None))
    else:
        q = q.where(ChatSummary.training_plan_id == training_plan_id)
    q = q.order_by(desc(ChatSummary.generated_at)).limit(1)
    return (await db.execute(q)).scalar_one_or_none()


def _render_transcript(messages: list[ChatMessage]) -> str:
    lines: list[str] = []
    for m in messages:
        who = "ATHLETE" if m.role == ChatRole.ATHLETE.value else "COACH"
        date = m.sent_at.strftime("%Y-%m-%d %H:%M") if m.sent_at else "?"
        lines.append(f"[{date}] {who}: {m.content}")
    return "\n".join(lines)
