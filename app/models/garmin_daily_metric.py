import uuid
from datetime import datetime, timezone, date

from sqlalchemy import Column, String, DateTime, Date, Float, Integer, ForeignKey, Index, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID, JSONB

from app.database import Base


class GarminDailyMetric(Base):
    """
    One row per athlete per date — overnight HRV, RHR, sleep stages, body battery, stress.
    Pushed by Garmin overnight (typically arrives 4-9 AM Pacific).

    Idempotency via UNIQUE (user_id, date) — re-pushes UPDATE.
    Phase 3's anomaly engine reads this for HRV drop / RHR rise / sleep deficit checks.
    """
    __tablename__ = "garmin_daily_metrics"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    date = Column(Date, nullable=False)

    resting_heart_rate = Column(Integer, nullable=True)
    hrv_overnight = Column(Float, nullable=True)              # ms
    hrv_baseline_7day = Column(Float, nullable=True)          # rolling 7-day median, recomputed on every insert

    sleep_duration_minutes = Column(Integer, nullable=True)
    sleep_score = Column(Integer, nullable=True)              # Garmin 0-100
    sleep_stages = Column(JSONB, nullable=True)               # {deep_min, light_min, rem_min, awake_min}

    body_battery_start = Column(Integer, nullable=True)       # 0-100
    body_battery_end = Column(Integer, nullable=True)
    body_battery_low = Column(Integer, nullable=True)

    stress_score = Column(Integer, nullable=True)             # daily avg, 0-100
    steps = Column(Integer, nullable=True)
    active_minutes = Column(Integer, nullable=True)

    synced_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        UniqueConstraint("user_id", "date", name="uq_garmin_daily_user_date"),
        Index("ix_garmin_daily_user_date", "user_id", "date"),
    )
