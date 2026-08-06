import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Column, String, DateTime, Date, SmallInteger, Text, ForeignKey, Index,
)
from sqlalchemy.dialects.postgresql import UUID, ARRAY

from app.database import Base


# ── Entry methods ──────────────────────────────────────────────────────────
ENTRY_MORNING = "morning"
ENTRY_PRE_RUN = "pre_run"
ENTRY_POST_RUN = "post_run"
ENTRY_MANUAL = "manual"


class WellnessCheckin(Base):
    """
    Subjective wellness data — sliders + optional body-part chips + free-text.

    Phase 4 introduces three flavors via `entry_method`:
      - morning: full check-in, 4 sliders + body areas + notes. ONE per day per user.
      - pre_run: 3 quick sliders (sleep / energy / body) on Start Run.
        Multiple per day allowed.
      - post_run / manual: future hooks; same shape, no day-uniqueness constraint.

    Activates `pain_logged` anomaly flag in Phase 3's anomaly_engine and feeds
    weekly review prompt input.
    """
    __tablename__ = "wellness_checkins"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    date = Column(Date, nullable=False)
    entry_method = Column(String(16), nullable=False)  # ENTRY_* values

    # Sliders 1-5. Nullable so partial entries are allowed (pre_run skips stress/motivation).
    sleep_quality = Column(SmallInteger, nullable=True)
    soreness = Column(SmallInteger, nullable=True)
    motivation = Column(SmallInteger, nullable=True)
    stress = Column(SmallInteger, nullable=True)
    energy = Column(SmallInteger, nullable=True)  # set on pre_run only

    # Optional structured body-area chips (e.g., ["calves", "left_knee"]).
    soreness_areas = Column(ARRAY(String), nullable=False, default=list)

    # Optional free-text. iOS dictation-enabled.
    notes = Column(Text, nullable=True)

    submitted_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        # The unique-per-day constraint on morning entries lives on the partial
        # index added in main.py inline migrations (SQLAlchemy doesn't model
        # partial-unique-indices cleanly across dialects).
        Index("ix_wellness_user_date", "user_id", "date"),
        Index("ix_wellness_user_method_date", "user_id", "entry_method", "date"),
    )
