import uuid
import enum
from datetime import datetime, timezone

from sqlalchemy import Column, Date, DateTime, ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID

from app.database import Base


class WeeklyCheckinStatus(str, enum.Enum):
    INVITED = "invited"
    IN_PROGRESS = "in_progress"
    SUBMITTED = "submitted"
    EXPIRED = "expired"


class WeeklyCheckin(Base):
    """
    One interactive weekly check-in per athlete per training week.

    Lifecycle: invited (push sent on the athlete's rest day) → in_progress
    (partial answers saved) → submitted (answers feed the weekly review) —
    or expired (Monday fallback cron ran the data-only review instead).
    """

    __tablename__ = "weekly_checkins"
    __table_args__ = (
        UniqueConstraint("user_id", "week_ending", name="uq_weekly_checkins_user_week"),
        Index("ix_weekly_checkins_user_status", "user_id", "status"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    # The Sunday (end of training week) this check-in reviews.
    week_ending = Column(Date, nullable=False)

    status = Column(String(16), nullable=False, default=WeeklyCheckinStatus.INVITED.value)
    invited_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    submitted_at = Column(DateTime(timezone=True), nullable=True)

    # Question payload served verbatim to iOS: {"version": 1, "questions": [...]}
    questions = Column(JSONB, nullable=False, default=dict)
    # Answers keyed by question id: {"week_feel": 4, "pain": true, ...}
    answers = Column(JSONB, nullable=False, default=dict)

    invite_event_id = Column(UUID(as_uuid=True), ForeignKey("coaching_events.id"), nullable=True)
    review_event_id = Column(UUID(as_uuid=True), ForeignKey("coaching_events.id"), nullable=True)
