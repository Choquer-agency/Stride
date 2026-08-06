import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Date, SmallInteger, Boolean, Integer, Text, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class StrengthSession(Base):
    """
    One row per logged gym session. `quick_logged=True` means the athlete tapped
    "Did the session as prescribed" — no per-exercise detail. Otherwise StrengthSet
    rows hang off this session for sets/reps/weight/RPE detail.
    """
    __tablename__ = "strength_sessions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    date = Column(Date, nullable=False)
    planned_workout_id = Column(UUID(as_uuid=True), nullable=True)  # iOS-side Workout id

    quick_logged = Column(Boolean, nullable=False, default=False)
    perceived_effort = Column(SmallInteger, nullable=True)        # 1-10 RPE for the session as a whole
    duration_minutes = Column(Integer, nullable=True)
    notes = Column(Text, nullable=True)

    submitted_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        Index("ix_strength_sessions_user_date", "user_id", "date"),
    )
