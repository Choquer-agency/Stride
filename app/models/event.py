import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Column, String, DateTime, Float, Integer, Boolean, ForeignKey, Text,
    UniqueConstraint, Index
)
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Event(Base):
    __tablename__ = "events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    event_type = Column(String(30), nullable=False)  # "race", "virtual_race", "group_run"
    distance_category = Column(String(10), nullable=True)  # "5K", "10K", "HM", "FM", "50K"
    distance_km = Column(Float, nullable=True)

    # Timing
    starts_at = Column(DateTime(timezone=True), nullable=False)
    ends_at = Column(DateTime(timezone=True), nullable=False)
    registration_opens_at = Column(DateTime(timezone=True), nullable=True)
    registration_closes_at = Column(DateTime(timezone=True), nullable=True)
    max_participants = Column(Integer, nullable=True)

    # Branding
    sponsor_name = Column(String(200), nullable=True)
    sponsor_logo_url = Column(String(500), nullable=True)
    banner_image_url = Column(String(500), nullable=True)
    primary_color = Column(String(7), nullable=True)  # hex e.g. "#FF2617"
    accent_color = Column(String(7), nullable=True)

    # Status
    is_active = Column(Boolean, default=True, nullable=False)
    is_featured = Column(Boolean, default=False, nullable=False)

    # Admin
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)

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

    __table_args__ = (
        Index("ix_events_dates", "starts_at", "ends_at"),
        Index("ix_events_active", "is_active"),
    )


class EventRegistration(Base):
    __tablename__ = "event_registrations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False, index=True)
    registered_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Performance tracking
    best_run_id = Column(UUID(as_uuid=True), ForeignKey("runs.id"), nullable=True)
    best_time_seconds = Column(Integer, nullable=True)
    total_distance_km = Column(Float, nullable=True, default=0.0)

    # Status
    status = Column(String(20), default="registered", nullable=False)  # "registered", "completed", "dns"

    __table_args__ = (
        UniqueConstraint("user_id", "event_id", name="uq_user_event"),
    )
