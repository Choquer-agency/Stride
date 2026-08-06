import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB

from app.database import Base


class FlagType(str, enum.Enum):
    """All anomaly flag types raised by the deterministic engine."""
    # Workout-level
    PACE_OFF_TARGET = "pace_off_target"
    WORKOUT_INCOMPLETE = "workout_incomplete"
    HR_ZONE_VIOLATION = "hr_zone_violation"
    # Daily-recovery
    HRV_DROP = "hrv_drop"
    RHR_RISE = "rhr_rise"
    SLEEP_DEFICIT = "sleep_deficit"
    # Pattern
    MISSED_WORKOUTS = "missed_workouts"
    PAIN_LOGGED = "pain_logged"
    LEA_PATTERN = "lea_pattern"
    STRENGTH_SKIPS = "strength_skips"
    # Race detection (informational)
    RACE_DETECTED = "race_detected"
    # Positive
    CONSOLIDATION_QUALITY_STREAK = "consolidation_quality_streak"
    CONSOLIDATION_RUN_STREAK = "consolidation_run_streak"
    CONSOLIDATION_HRV_BUILD = "consolidation_hrv_build"
    CONSOLIDATION_DISTRIBUTION_LOCK = "consolidation_distribution_lock"


class FlagSeverity(str, enum.Enum):
    INFO = "info"
    WARNING = "warning"
    WARNING_PLUS = "warning_plus"  # contributes to critical override (e.g. HRV drop >15%)
    CRITICAL = "critical"


class AnomalyFlag(Base):
    """
    Persistent record of every flag the anomaly engine raises. Active flags have
    `resolved_at IS NULL`. Used for trend analysis and audit trail.
    """
    __tablename__ = "anomaly_flags"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    raised_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))

    flag_type = Column(String(40), nullable=False)  # FlagType value
    severity = Column(String(20), nullable=False)  # FlagSeverity value

    # Optional refs
    workout_id = Column(UUID(as_uuid=True), nullable=True)  # Run.id if workout-level

    # Resolution tracking
    resolved_at = Column(DateTime(timezone=True), nullable=True)
    resolved_by = Column(String(40), nullable=True)  # 'auto' | 'coach_event' | 'user_action'

    # Structured context: what triggered, magnitude, baseline, etc.
    context = Column(JSONB, nullable=False, default=dict)

    __table_args__ = (
        Index("ix_anomaly_flags_user_raised", "user_id", "raised_at"),
        Index("ix_anomaly_flags_user_active", "user_id", "resolved_at"),
        Index("ix_anomaly_flags_user_type", "user_id", "flag_type"),
    )
