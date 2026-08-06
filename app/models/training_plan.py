import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, Date, DateTime, Float, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class TrainingPlanRecord(Base):
    """
    Server-side copy of every training plan, versioned per user.

    The iOS SwiftData plan remains the working copy the athlete trains from;
    every generation, edit, and backfill writes a row here so plans can be
    reviewed and adjusted server-side. Exactly one row per user has
    is_active=True (the latest content). When a server-side edit bumps
    updated_at past what the phone last applied, the app offers to apply it.
    """

    __tablename__ = "training_plans"
    __table_args__ = (
        Index("ix_training_plans_user_active", "user_id", "is_active"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    created_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    is_active = Column(Boolean, nullable=False, default=True)
    # generated | edited | ios_backfill | server_edit
    source = Column(String(16), nullable=False, default="generated")

    # Plan metadata (mirrors the iOS TrainingPlan fields needed to re-parse)
    race_type = Column(String(32), nullable=True)
    race_date = Column(Date, nullable=True)
    race_name = Column(String(255), nullable=True)
    goal_time = Column(String(32), nullable=True)
    custom_distance_km = Column(Float, nullable=True)
    start_date = Column(Date, nullable=True)
    fitness_level = Column(String(16), nullable=True)

    # SwiftData TrainingPlan.id on the device, when known (backfill/sync)
    client_plan_id = Column(UUID(as_uuid=True), nullable=True)

    # The full raw plan text — the same content PlanParser consumes on iOS
    raw_plan_content = Column(Text, nullable=False)

    # For edits: what changed (edit instructions or server-side note)
    change_note = Column(Text, nullable=True)
