import uuid
import enum
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, Float, Text, Boolean, Integer, Time
from sqlalchemy.dialects.postgresql import UUID, JSONB, ARRAY

from app.database import Base


# Default per-loop coaching modes for new users.
# Each new loop ships in shadow until manually promoted via admin.
# Chat ships live (low blast-radius). Nutrition ships off until Phase 6 lands.
DEFAULT_COACHING_MODES = {
    "weekly_review": "shadow",
    "block_review": "shadow",
    "post_run_check": "shadow",
    "race_prep": "shadow",
    "chat": "live",
    "nutrition": "off",
    "wellness": "live",
}


class AuthProvider(str, enum.Enum):
    EMAIL = "email"
    GOOGLE = "google"
    APPLE = "apple"


class Gender(str, enum.Enum):
    MALE = "male"
    FEMALE = "female"
    NON_BINARY = "non_binary"
    PREFER_NOT_TO_SAY = "prefer_not_to_say"


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String(255), unique=True, nullable=False, index=True)
    name = Column(String(255), nullable=True)
    auth_provider = Column(String(20), nullable=False)  # email, google, apple
    hashed_password = Column(String(255), nullable=True)  # null for social auth

    # Profile fields
    profile_photo_base64 = Column(Text, nullable=True)
    date_of_birth = Column(String(10), nullable=True)  # ISO date "YYYY-MM-DD"
    gender = Column(String(20), nullable=True)
    height_cm = Column(Float, nullable=True)

    # Apple Sign-In identifier (for subsequent logins)
    apple_user_identifier = Column(String(255), nullable=True, unique=True, index=True)

    # Profile completion
    has_completed_profile = Column(Boolean, default=False, nullable=False)

    # Community
    leaderboard_opt_in = Column(Boolean, default=False, nullable=False)
    display_name = Column(String(50), nullable=True)

    # Social
    bio = Column(String(255), nullable=True)

    # Admin
    is_admin = Column(Boolean, default=False, nullable=False)

    # ── v2 coaching infrastructure (Phase 0) ────────────────────────────────
    # Per-loop shadow/live/off toggle
    coaching_modes = Column(JSONB, nullable=False, default=lambda: dict(DEFAULT_COACHING_MODES))
    # First-3-events feedback counter per loop type
    coaching_feedback_seen = Column(JSONB, nullable=False, default=dict)
    # APNs hex token (set via /api/devices/register)
    apns_device_token = Column(String(64), nullable=True)
    # Garmin OAuth + connection state (Phase 1 wires)
    garmin_access_token = Column(Text, nullable=True)
    garmin_refresh_token = Column(Text, nullable=True)
    garmin_user_id = Column(String(64), nullable=True, index=True)
    garmin_connected_at = Column(DateTime(timezone=True), nullable=True)
    garmin_disconnected_at = Column(DateTime(timezone=True), nullable=True)
    garmin_backfill_status = Column(String(16), nullable=False, default="pending")
    garmin_backfill_progress = Column(Integer, nullable=False, default=0)
    # Fitbit via Google Health API — OAuth + connection state. Ingested data
    # lands in the same garmin_* metric tables so the coaching stack reads it
    # with zero changes.
    fitbit_access_token = Column(Text, nullable=True)
    fitbit_refresh_token = Column(Text, nullable=True)
    fitbit_token_expires_at = Column(DateTime(timezone=True), nullable=True)
    fitbit_health_user_id = Column(String(64), nullable=True, index=True)
    fitbit_connected_at = Column(DateTime(timezone=True), nullable=True)
    fitbit_disconnected_at = Column(DateTime(timezone=True), nullable=True)
    fitbit_backfill_status = Column(String(16), nullable=False, default="pending")
    fitbit_backfill_progress = Column(Integer, nullable=False, default=0)
    # Notification preferences
    quiet_hours_start = Column(Time, nullable=True)
    quiet_hours_end = Column(Time, nullable=True)
    muted_notification_types = Column(ARRAY(String), nullable=False, default=list)
    # Pause coach (Phase 3) — null = not paused; future timestamp = paused until then;
    # epoch 0 (or some sentinel) could indicate "until resume" but we use a separate flag.
    coaching_paused_until = Column(DateTime(timezone=True), nullable=True)
    coaching_resume_pending = Column(Boolean, nullable=False, default=False)

    # ── v2 Phase 2: race-type pin for cron-driven prompts ───────────────────
    # Set by iOS when the active TrainingPlan changes; the weekly-review cron
    # has no iOS context so it reads from here. Defaults to 'marathon'.
    current_race_type = Column(String(20), nullable=True, default="marathon")

    # Weekly check-in day pin (0=Monday .. 6=Sunday; NULL → Sunday). Set by iOS
    # from the active plan's rest day — same pattern as current_race_type.
    checkin_day_of_week = Column(Integer, nullable=True)

    # Timestamps
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
