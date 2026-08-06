import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, Text, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB, ARRAY

from app.database import Base


class PlanAdjustmentStatus(str, enum.Enum):
    PROPOSED = "proposed"
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    EXPIRED = "expired"  # athlete didn't act before workout time


class PlanAdjustment(Base):
    """
    A coach-proposed change to the athlete's training plan. Athlete reviews via the
    AdjustmentReviewSheet and either accepts (apply diff) or rejects (with optional reason).
    Proposals expire automatically: workout-level at workout start + 1h, block-level at +7d.
    """
    __tablename__ = "plan_adjustments"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    training_plan_id = Column(UUID(as_uuid=True), nullable=True)  # iOS-side TrainingPlan UUID

    proposed_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    expires_at = Column(DateTime(timezone=True), nullable=False)

    status = Column(String(20), nullable=False, default=PlanAdjustmentStatus.PROPOSED.value)

    # The coaching event that produced this proposal (FK by ID — events are source of truth)
    trigger_event_id = Column(UUID(as_uuid=True), ForeignKey("coaching_events.id"), nullable=True)

    summary_text = Column(Text, nullable=False)
    structured_diff = Column(JSONB, nullable=False, default=dict)
    affected_workout_ids = Column(ARRAY(UUID(as_uuid=True)), nullable=True)

    # Set when accepted
    applied_at = Column(DateTime(timezone=True), nullable=True)
    applied_diff_actual = Column(JSONB, nullable=True)  # what was actually applied (may differ if plan shifted)

    # Set when rejected
    rejection_reason = Column(Text, nullable=True)

    __table_args__ = (
        Index("ix_plan_adjustments_user_status", "user_id", "status"),
        Index("ix_plan_adjustments_expires", "expires_at"),
    )
