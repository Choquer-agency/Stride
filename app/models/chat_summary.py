import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Integer, Text, ForeignKey, Index
from sqlalchemy.dialects.postgresql import ARRAY, UUID

from app.database import Base


class ChatSummary(Base):
    """
    Haiku-generated rolling summary of older chat history.

    When a thread (user_id, training_plan_id) exceeds 50 messages, the oldest 25
    are summarized into a single ChatSummary row and the prompt prepends it as
    "Earlier in this conversation: ..." instead of including those messages
    verbatim.

    Idempotent: chat_summarizer.py only summarizes messages not yet covered.
    """
    __tablename__ = "chat_summaries"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    training_plan_id = Column(UUID(as_uuid=True), nullable=True)

    # The chat_messages.id values this summary covers. Sorted ascending.
    # Stored as UUID array so we can quickly compute "messages not yet covered".
    covers_message_ids = Column(ARRAY(UUID(as_uuid=True)), nullable=False, default=list)

    summary_text = Column(Text, nullable=False)

    generated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        Index("ix_chat_summaries_user_plan_gen", "user_id", "training_plan_id", "generated_at"),
    )
