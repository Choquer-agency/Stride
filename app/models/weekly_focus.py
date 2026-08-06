import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, Text, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class FocusOutcome(str, enum.Enum):
    ACHIEVED = "achieved"
    PARTIAL = "partial"
    MISSED = "missed"


class WeeklyFocus(Base):
    """
    A specific intention the coach sets for the upcoming week (from a weekly review or
    block review). Next review references the focus by name and reports outcome.

    The focus_tracker service parses focuses from the LLM output and persists them.
    Outcomes are inferred from the next review's <focus_outcomes> JSON tag.
    """
    __tablename__ = "weekly_focuses"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    raised_in_event_id = Column(UUID(as_uuid=True), ForeignKey("coaching_events.id"), nullable=False)
    raised_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))

    text = Column(Text, nullable=False)

    outcome = Column(String(20), nullable=True)  # FocusOutcome value or null (still active)
    outcome_set_at = Column(DateTime(timezone=True), nullable=True)
    outcome_event_id = Column(UUID(as_uuid=True), ForeignKey("coaching_events.id"), nullable=True)

    __table_args__ = (
        Index("ix_weekly_focuses_user_active", "user_id", "outcome"),
        Index("ix_weekly_focuses_user_raised", "user_id", "raised_at"),
    )
