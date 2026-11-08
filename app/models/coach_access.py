"""Explicit coach grants and phone-approved external plan proposals."""
import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID, JSONB

from app.database import Base


class CoachCredential(Base):
    __tablename__ = "coach_credentials"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    token_hash = Column(String(64), nullable=False, unique=True)
    label = Column(String(100), nullable=False)
    can_read = Column(Boolean, nullable=False, default=True)
    can_propose = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    revoked_at = Column(DateTime(timezone=True), nullable=True)


class CoachAthleteGrant(Base):
    __tablename__ = "coach_athlete_grants"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    credential_id = Column(UUID(as_uuid=True), ForeignKey("coach_credentials.id"), nullable=False)
    athlete_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    can_read = Column(Boolean, nullable=False, default=True)
    can_propose = Column(Boolean, nullable=False, default=False)
    revoked_at = Column(DateTime(timezone=True), nullable=True)
    __table_args__ = (UniqueConstraint("credential_id", "athlete_id"),)


class ExternalPlanProposal(Base):
    __tablename__ = "external_plan_proposals"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    credential_id = Column(UUID(as_uuid=True), ForeignKey("coach_credentials.id"), nullable=False)
    athlete_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    expected_plan_id = Column(UUID(as_uuid=True), ForeignKey("training_plans.id"), nullable=False)
    applied_plan_id = Column(UUID(as_uuid=True), ForeignKey("training_plans.id"), nullable=True)
    idempotency_key = Column(String(100), nullable=False)
    status = Column(String(20), nullable=False, default="proposed")
    reason = Column(String(1000), nullable=False)
    before_text = Column(Text, nullable=False)
    after_text = Column(Text, nullable=False)
    diff = Column(JSONB, nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    delivered_at = Column(DateTime(timezone=True), nullable=True)
    decided_at = Column(DateTime(timezone=True), nullable=True)
    applied_at = Column(DateTime(timezone=True), nullable=True)
    __table_args__ = (
        UniqueConstraint("credential_id", "idempotency_key"),
        Index("ix_external_proposals_athlete_status", "athlete_id", "status"),
    )


class CoachAccessAudit(Base):
    __tablename__ = "coach_access_audit"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    credential_id = Column(UUID(as_uuid=True), ForeignKey("coach_credentials.id"), nullable=True)
    athlete_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    proposal_id = Column(UUID(as_uuid=True), ForeignKey("external_plan_proposals.id"), nullable=True)
    action = Column(String(50), nullable=False)
    before_plan_id = Column(UUID(as_uuid=True), nullable=True)
    after_plan_id = Column(UUID(as_uuid=True), nullable=True)
    occurred_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
