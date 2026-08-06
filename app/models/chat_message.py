import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, Text, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB

from app.database import Base


class ChatRole(str, enum.Enum):
    ATHLETE = "athlete"
    COACH = "coach"


class ChatMessage(Base):
    """
    One conversational message in the persistent "Ask Coach" chat (Phase 5).

    Threading:
    - One thread per (user_id, training_plan_id). Plan archived → thread archived (read-only).
    - During no-plan periods training_plan_id is NULL — the chat returns a stub
      response and accepts limited questions.

    Cross-references:
    - related_event_id: when chat was opened from a coaching event "Reply" button
      (weekly review, post-run check, wellness concern, adjustment proposal).
    - related_adjustment_id: when the coach's response produced a plan adjustment
      via the <adjustment> JSON tag.

    The first ~50 messages of each thread are loaded verbatim into the prompt;
    older history is Haiku-summarized into chat_summaries.
    """
    __tablename__ = "chat_messages"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    training_plan_id = Column(UUID(as_uuid=True), nullable=True)  # iOS-side TrainingPlan UUID

    sent_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    role = Column(String(16), nullable=False)  # ChatRole value
    content = Column(Text, nullable=False)

    # What context the coach saw when generating its response. Athlete messages have null.
    context_snapshot = Column(JSONB, nullable=True)

    related_event_id = Column(UUID(as_uuid=True), ForeignKey("coaching_events.id"), nullable=True)
    related_adjustment_id = Column(UUID(as_uuid=True), ForeignKey("plan_adjustments.id"), nullable=True)

    __table_args__ = (
        Index("ix_chat_messages_user_plan_sent", "user_id", "training_plan_id", "sent_at"),
        Index("ix_chat_messages_user_sent", "user_id", "sent_at"),
    )
