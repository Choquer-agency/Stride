import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, Float, Boolean, Integer, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB

from app.database import Base


# ── Activity-type buckets ───────────────────────────────────────────────────
# Garmin pushes raw activity_type strings like "running", "treadmill_running",
# "indoor_cycling", "weight_training", "walking", "yoga", etc. We normalize
# them into one of these 4 buckets to drive coaching behavior.
ACTIVITY_BUCKET_RUNNING = "running"        # planned vs actual + anomaly checks
ACTIVITY_BUCKET_CYCLING = "cycling"        # cross-training context, no anomaly checks
ACTIVITY_BUCKET_STRENGTH = "strength"      # falls into strength_sessions (Phase 9)
ACTIVITY_BUCKET_OTHER = "other"            # walks/swims/yoga/hikes — recovery context


def bucket_for_activity_type(garmin_activity_type: str) -> str:
    """Map a raw Garmin activity_type to one of the 4 Stride buckets."""
    t = (garmin_activity_type or "").lower()
    if "running" in t:
        return ACTIVITY_BUCKET_RUNNING
    if "cycling" in t or "biking" in t or "e_bike" in t:
        return ACTIVITY_BUCKET_CYCLING
    if "strength" in t or "weight_training" in t:
        return ACTIVITY_BUCKET_STRENGTH
    return ACTIVITY_BUCKET_OTHER


class GarminWorkout(Base):
    """
    Raw + normalized workout record per Garmin activity push.
    Running activities additionally upsert into the canonical Run table
    (data_source='garmin') so existing run-based code paths work unchanged.

    Idempotency is via the unique constraint on garmin_activity_id —
    re-pushes (Garmin retry, manual edit propagation) become UPDATEs.
    """
    __tablename__ = "garmin_workouts"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    # Globally unique across a user's devices — Garmin merges multi-device
    # recordings of the same workout into one ID before pushing.
    garmin_activity_id = Column(String(64), nullable=False, unique=True, index=True)

    # Raw type strings + normalized bucket
    activity_type = Column(String(40), nullable=False)              # bucket value
    activity_subtype = Column(String(40), nullable=True)            # raw garmin string for debugging
    is_indoor = Column(Boolean, nullable=False, default=False)
    is_race = Column(Boolean, nullable=False, default=False)

    start_time = Column(DateTime(timezone=True), nullable=False, index=True)
    duration_seconds = Column(Float, nullable=False)
    distance_km = Column(Float, nullable=True)                      # null for strength

    # HR + pace
    avg_heart_rate = Column(Integer, nullable=True)
    max_heart_rate = Column(Integer, nullable=True)
    avg_pace_sec_per_km = Column(Float, nullable=True)              # null for strength/non-locomotion
    hr_zones = Column(JSONB, nullable=True)                         # {z1, z2, z3, z4, z5} in seconds

    # Per-km splits
    splits = Column(JSONB, nullable=True)                           # [{km, pace_sec_per_km, hr, cadence, elevation}]

    # Garmin's training effect + VO2max for the workout
    training_effect_aerobic = Column(Float, nullable=True)
    training_effect_anaerobic = Column(Float, nullable=True)
    estimated_vo2max = Column(Float, nullable=True)

    # Weather (when Garmin includes it)
    weather_temp_c = Column(Float, nullable=True)
    weather_humidity_pct = Column(Float, nullable=True)

    # Full Garmin payload for replay/debug
    raw_payload = Column(JSONB, nullable=False, default=dict)

    # Plan match — null if unmatched (still ingested, counts toward weekly volume)
    planned_workout_id = Column(UUID(as_uuid=True), nullable=True)

    synced_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        Index("ix_garmin_workouts_user_start", "user_id", "start_time"),
        Index("ix_garmin_workouts_user_bucket", "user_id", "activity_type"),
    )
