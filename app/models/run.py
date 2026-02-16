import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, Float, Integer, Text, Boolean, ForeignKey
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Run(Base):
    __tablename__ = "runs"

    # Use iOS-generated UUID for deduplication
    id = Column(UUID(as_uuid=True), primary_key=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    # Core run data
    completed_at = Column(DateTime(timezone=True), nullable=False)
    distance_km = Column(Float, nullable=False)
    duration_seconds = Column(Float, nullable=False)
    avg_pace_sec_per_km = Column(Float, nullable=False)
    km_splits_json = Column(Text, nullable=True)

    # User feedback
    feedback_rating = Column(Integer, nullable=True)
    notes = Column(Text, nullable=True)

    # Denormalized plan context
    planned_workout_title = Column(String(255), nullable=True)
    planned_workout_type = Column(String(50), nullable=True)
    planned_distance_km = Column(Float, nullable=True)
    completion_score = Column(Integer, nullable=True)
    plan_name = Column(String(255), nullable=True)
    week_number = Column(Integer, nullable=True)

    # Run verification
    data_source = Column(String(20), nullable=False, default="manual")  # "bluetooth_ftms" | "manual"
    treadmill_brand = Column(String(100), nullable=True)
    is_leaderboard_eligible = Column(Boolean, nullable=False, default=False)

    # Sync metadata
    synced_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
