import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Float, String, Integer, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB

from app.database import Base


class GarminPeriodicMetric(Base):
    """
    Weekly snapshot of Garmin's longer-cadence metrics — VO2max trend, training status,
    acute/chronic load, lactate threshold estimate, race predictors.

    History retained — one row per push. Block reviews (Phase 7) compare current to prior.
    """
    __tablename__ = "garmin_periodic_metrics"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    fetched_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))

    vo2max_running = Column(Float, nullable=True)
    # Garmin enum: productive | maintaining | recovery | unproductive | detraining | strained | overreaching
    training_status = Column(String(24), nullable=True)

    acute_load = Column(Float, nullable=True)
    chronic_load = Column(Float, nullable=True)
    acute_chronic_ratio = Column(Float, nullable=True)

    lactate_threshold_hr = Column(Integer, nullable=True)
    lactate_threshold_pace_sec_per_km = Column(Float, nullable=True)

    # {five_k, ten_k, half_marathon, marathon} — all in seconds
    race_predictors = Column(JSONB, nullable=True)

    __table_args__ = (
        Index("ix_garmin_periodic_user_fetched", "user_id", "fetched_at"),
    )
