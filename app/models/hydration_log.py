import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Date, Integer, ForeignKey, Index, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class HydrationLog(Base):
    """
    One row per user per day, upserted as the athlete taps glass icons.
    Separate from food logs so it's a snappy quick-tap counter.
    """
    __tablename__ = "hydration_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    date = Column(Date, nullable=False)

    glasses_logged = Column(Integer, nullable=False, default=0)
    estimated_ml = Column(Integer, nullable=False, default=0)
    electrolyte_servings = Column(Integer, nullable=False, default=0)

    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        UniqueConstraint("user_id", "date", name="uq_hydration_user_date"),
        Index("ix_hydration_user_date", "user_id", "date"),
    )
