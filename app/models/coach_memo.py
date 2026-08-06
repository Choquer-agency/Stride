import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, Integer, Text, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB

from app.database import Base


class CoachMemo(Base):
    """
    Persistent ~500-word doc the LLM writes to itself capturing what it knows about the
    athlete that's NOT in the data: tendencies, patterns, what's worked, what's failed.

    Auto-updated after every weekly review via Haiku. Loaded into every coaching prompt
    as `## What you know about this athlete`. The active memo for a user is the row with
    the latest `updated_at`. Historical versions retained for audit.
    """
    __tablename__ = "coach_memos"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    content = Column(Text, nullable=False)
    version = Column(Integer, nullable=False, default=1)

    updated_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))

    # The event whose output triggered this memo update (typically a weekly_review).
    last_event_id = Column(UUID(as_uuid=True), ForeignKey("coaching_events.id"), nullable=True)

    # Date range the memo summarizes — `{"start": "2026-04-01", "end": "2026-05-05"}`
    summary_of = Column(JSONB, nullable=False, default=dict)

    __table_args__ = (
        Index("ix_coach_memos_user_updated", "user_id", "updated_at"),
    )
