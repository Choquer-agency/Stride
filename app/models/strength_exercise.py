import enum
import uuid

from sqlalchemy import Column, String, SmallInteger, Index
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class ExerciseCategory(str, enum.Enum):
    POSTERIOR_CHAIN = "posterior_chain"
    HIP_STABILITY = "hip_stability"
    SINGLE_LEG = "single_leg"
    CORE = "core"


class Equipment(str, enum.Enum):
    BODYWEIGHT = "bodyweight"
    DUMBBELL = "dumbbell"
    BARBELL = "barbell"
    KETTLEBELL = "kettlebell"
    BAND = "band"
    MACHINE = "machine"


class StrengthExercise(Base):
    """
    Curated library of running-specific strength exercises. Seeded from
    app/data/strength_exercises.json on startup. Athletes pick from this
    library when logging detailed strength sessions.
    """
    __tablename__ = "strength_exercises"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(120), nullable=False, unique=True)
    category = Column(String(24), nullable=False)              # ExerciseCategory value
    equipment = Column(String(24), nullable=False)             # Equipment value
    youtube_demo_url = Column(String(500), nullable=True)
    default_set_count = Column(SmallInteger, nullable=False, default=3)
    default_rep_range = Column(String(32), nullable=False, default="8-12")  # display only

    __table_args__ = (
        Index("ix_strength_exercises_category", "category"),
    )
