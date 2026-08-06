import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Text, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB

from app.database import Base


class RaceFuelingPlan(Base):
    """
    Auto-generated 14 days before a registered race. Four phases —
    3-days-before / race-morning / during / post — each a JSONB blob
    of structured items the athlete can edit + commit.
    """
    __tablename__ = "race_fueling_plans"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False, index=True)

    generated_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))

    # 4 phase plans, each a JSONB structure: {summary, items: [{label, detail, when}]}
    three_days_before = Column(JSONB, nullable=False, default=dict)
    race_morning = Column(JSONB, nullable=False, default=dict)
    during_race = Column(JSONB, nullable=False, default=dict)
    post_race = Column(JSONB, nullable=False, default=dict)

    # Inputs at generation time — kept for replay
    weather_forecast = Column(JSONB, nullable=True)
    course_notes = Column(Text, nullable=True)

    # Athlete-applied modifications layered on top of the LLM's plan
    athlete_edits = Column(JSONB, nullable=False, default=dict)

    __table_args__ = (
        Index("ix_race_fueling_user_event", "user_id", "event_id"),
    )
