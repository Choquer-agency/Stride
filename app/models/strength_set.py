import uuid

from sqlalchemy import Column, SmallInteger, ForeignKey, Index, Numeric
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class StrengthSet(Base):
    """
    One row per individual set in a detailed strength session.
    weight_kg is loaded weight (NOT body weight — body weight tracking is
    explicitly out of scope per LEA guardrails).
    """
    __tablename__ = "strength_sets"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id = Column(UUID(as_uuid=True), ForeignKey("strength_sessions.id"), nullable=False, index=True)
    exercise_id = Column(UUID(as_uuid=True), ForeignKey("strength_exercises.id"), nullable=False, index=True)

    set_number = Column(SmallInteger, nullable=False)
    reps = Column(SmallInteger, nullable=False)
    weight_kg = Column(Numeric(6, 2), nullable=True)              # null = bodyweight
    rpe = Column(SmallInteger, nullable=True)                     # 1-10

    __table_args__ = (
        Index("ix_strength_sets_session_exercise", "session_id", "exercise_id"),
        Index("ix_strength_sets_exercise_session", "exercise_id", "session_id"),
    )
