import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class CoachingCooldown(Base):
    """
    Per-user, per-flag-type cool-down after a plan adjustment is rejected or expires.
    The anomaly engine keeps raising flags into anomaly_flags for audit, but the
    post-run check filters cooled-down flag types out of the LLM input — preventing nag.

    Cooldowns clear early when severity escalates (handled in cooldown_service).
    """
    __tablename__ = "coaching_cooldowns"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    flag_type = Column(String(40), nullable=False)
    cooldown_until = Column(DateTime(timezone=True), nullable=False)
    set_by_event_id = Column(UUID(as_uuid=True), ForeignKey("coaching_events.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        Index("ix_coaching_cooldowns_user_flag", "user_id", "flag_type"),
        Index("ix_coaching_cooldowns_until", "cooldown_until"),
    )
