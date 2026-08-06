import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Integer, ForeignKey, Index, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID, JSONB

from app.database import Base


class RaceLogisticsChecklist(Base):
    """
    Phase 8 race-prep logistics checklist. Generated automatically when the
    athlete enters the final 28-day window (or manually via API).

    Items are stored as JSONB so the LLM-generated structure can evolve
    without migrations. Each item: {label, detail, completed (bool), athlete_note}.
    A/B/C goals stored separately as goal_seconds for direct querying.
    """
    __tablename__ = "race_logistics_checklists"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False, index=True)

    generated_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))

    items = Column(JSONB, nullable=False, default=list)
    weather_forecast = Column(JSONB, nullable=True)
    course_intel = Column(JSONB, nullable=True)

    # A / B / C goal times in seconds. A = stretch, B = primary, C = floor.
    a_goal_seconds = Column(Integer, nullable=True)
    b_goal_seconds = Column(Integer, nullable=True)
    c_goal_seconds = Column(Integer, nullable=True)

    __table_args__ = (
        # One checklist per user per race event — regenerate replaces.
        UniqueConstraint("user_id", "event_id", name="uq_race_logistics_user_event"),
        Index("ix_race_logistics_user_event", "user_id", "event_id"),
    )
