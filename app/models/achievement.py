import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Column, String, DateTime, Integer, Text, ForeignKey, UniqueConstraint, Index
)
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class AchievementDefinition(Base):
    __tablename__ = "achievement_definitions"

    id = Column(String(50), primary_key=True)  # e.g. "distance_100km", "streak_7"
    category = Column(String(30), nullable=False)  # "distance", "streak", "performance", "milestone"
    title = Column(String(100), nullable=False)
    description = Column(Text, nullable=False)
    icon = Column(String(50), nullable=False)  # SF Symbol name
    threshold = Column(Integer, nullable=False)  # Category-specific value (km, days, seconds)
    tier = Column(String(20), nullable=False, default="bronze")  # "bronze", "silver", "gold", "platinum"
    sort_order = Column(Integer, nullable=False, default=0)


class UserAchievement(Base):
    __tablename__ = "user_achievements"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    achievement_id = Column(String(50), ForeignKey("achievement_definitions.id"), nullable=False)
    unlocked_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    run_id = Column(UUID(as_uuid=True), ForeignKey("runs.id"), nullable=True)  # Run that triggered unlock
    notified = Column(String(5), nullable=False, default="false")  # "true" / "false"

    __table_args__ = (
        UniqueConstraint("user_id", "achievement_id", name="uq_user_achievement"),
        Index("ix_user_achievements_user_notified", "user_id", "notified"),
    )
