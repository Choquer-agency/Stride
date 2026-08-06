import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, Boolean, Integer, Text, ForeignKey, Index, Numeric
from sqlalchemy.dialects.postgresql import UUID, JSONB

from app.database import Base


class CoachingEventType(str, enum.Enum):
    """All event types written to coaching_events."""
    # Cadence-driven
    WEEKLY_REVIEW = "weekly_review"
    WEEKLY_CHECKIN_INVITE = "weekly_checkin_invite"
    BLOCK_REVIEW = "block_review"
    RACE_PREP_ENTRY = "race_prep_entry"
    RACE_PREP_REVIEW = "race_prep_review"
    RACE_LOGISTICS_GENERATED = "race_logistics_generated"
    OFF_SEASON = "off_season"
    # Per-run
    POST_RUN_INFO = "post_run_info"
    POST_RUN_CHECK = "post_run_check"
    POST_RACE = "post_race"
    RED_FLAG = "red_flag"
    CONSOLIDATION = "consolidation"
    # Wellness / nutrition
    WELLNESS_CONCERN = "wellness_concern"
    NUTRITION_GUIDANCE = "nutrition_guidance"
    NUTRITION_GAP = "nutrition_gap"
    NUTRITION_MEAL_FEEDBACK = "nutrition_meal_feedback"
    # Plan changes
    PLAN_ADJUSTMENT_PROPOSED = "plan_adjustment_proposed"
    PLAN_ADJUSTMENT_ACCEPTED = "plan_adjustment_accepted"
    PLAN_ADJUSTMENT_REJECTED = "plan_adjustment_rejected"
    PLAN_ADJUSTMENT_EXPIRED = "plan_adjustment_expired"
    # Chat
    CHAT = "chat"
    # System
    MEMO_UPDATE = "memo_update"
    GARMIN_RECONCILE = "garmin_reconcile"
    NO_ACTIVE_PLAN = "no_active_plan"


class CoachingEventTriggerSource(str, enum.Enum):
    GARMIN_WEBHOOK = "garmin_webhook"
    CRON = "cron"
    USER_MESSAGE = "user_message"
    USER_ACTION = "user_action"
    MANUAL = "manual"
    ADMIN = "admin"


class CoachingEventFeedback(str, enum.Enum):
    POSITIVE = "positive"
    NEGATIVE = "negative"
    UNCLEAR = "unclear"


class CoachingEvent(Base):
    """
    Audit log of every coaching action — notifications sent, adjustments proposed,
    LLM calls made, athlete responses. Critical for replaying bad outputs and
    debugging the coach's behavior.
    """
    __tablename__ = "coaching_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    triggered_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc), index=True)

    event_type = Column(String(40), nullable=False, index=True)  # CoachingEventType value
    trigger_source = Column(String(20), nullable=False)  # CoachingEventTriggerSource value

    # What flags fired (per-run loop only — empty list otherwise)
    flags_that_fired = Column(JSONB, nullable=False, default=list)

    # Prompt versioning + LLM metrics
    prompt_used = Column(String(120), nullable=True)  # e.g. "coach_weekly_review.txt@a3f8b2"
    llm_model_used = Column(String(80), nullable=True)
    llm_input = Column(Text, nullable=True)
    llm_output = Column(Text, nullable=True)
    llm_input_tokens = Column(Integer, nullable=True)
    llm_output_tokens = Column(Integer, nullable=True)
    llm_cost_usd = Column(Numeric(10, 4), nullable=True)
    llm_latency_ms = Column(Integer, nullable=True)

    # Notification + athlete response tracking
    notification_delivered = Column(Boolean, nullable=False, default=False)
    notification_reason = Column(String(200), nullable=True)  # if not delivered, why
    athlete_response = Column(Text, nullable=True)
    athlete_feedback = Column(String(20), nullable=True)  # CoachingEventFeedback value or null

    shadow_mode = Column(Boolean, nullable=False, default=False)
    idempotency_key = Column(String(120), nullable=True, unique=True)

    # Trigger context — thresholds breached, scheduled time, related IDs, parsed adjustment, etc.
    context = Column(JSONB, nullable=False, default=dict)

    __table_args__ = (
        Index("ix_coaching_events_user_triggered", "user_id", "triggered_at"),
        Index("ix_coaching_events_user_type", "user_id", "event_type"),
    )
