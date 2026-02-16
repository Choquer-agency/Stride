import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, Float, Integer, ForeignKey, UniqueConstraint, Index
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class PersonalBest(Base):
    __tablename__ = "personal_bests"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    distance_category = Column(String(10), nullable=False)  # "5K", "10K", "HM", "FM", "50K"
    time_seconds = Column(Integer, nullable=False)
    achieved_at = Column(DateTime(timezone=True), nullable=False)
    run_id = Column(UUID(as_uuid=True), ForeignKey("runs.id"), nullable=False)

    __table_args__ = (
        UniqueConstraint("user_id", "distance_category", name="uq_user_distance_category"),
        Index("ix_distance_category_time", "distance_category", "time_seconds"),
    )
