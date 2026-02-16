import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Column, String, DateTime, Float, Integer, Boolean, ForeignKey,
    UniqueConstraint, Index
)
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Challenge(Base):
    __tablename__ = "challenges"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title = Column(String(200), nullable=False)
    challenge_type = Column(String(30), nullable=False)  # "weekly_race", "monthly_distance"
    distance_category = Column(String(10), nullable=True)  # "5K", "10K", etc. (for race type)
    cumulative_target_km = Column(Float, nullable=True)  # For monthly distance challenges
    starts_at = Column(DateTime(timezone=True), nullable=False)
    ends_at = Column(DateTime(timezone=True), nullable=False)
    auto_generated = Column(Boolean, nullable=False, default=False)
    series_id = Column(String(50), nullable=True)  # e.g. "weekly_5k" to group recurring
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    __table_args__ = (
        Index("ix_challenges_dates", "starts_at", "ends_at"),
    )


class ChallengeParticipation(Base):
    __tablename__ = "challenge_participations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    challenge_id = Column(UUID(as_uuid=True), ForeignKey("challenges.id"), nullable=False, index=True)
    joined_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    # For race challenges: best qualifying run
    best_run_id = Column(UUID(as_uuid=True), ForeignKey("runs.id"), nullable=True)
    best_time_seconds = Column(Integer, nullable=True)
    # For monthly distance challenges: cumulative km
    total_distance_km = Column(Float, nullable=True, default=0.0)

    __table_args__ = (
        UniqueConstraint("user_id", "challenge_id", name="uq_user_challenge"),
    )
