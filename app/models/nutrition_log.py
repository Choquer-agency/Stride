import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Column, String, DateTime, Float, Integer, Boolean, Text, ForeignKey, Index, Numeric
)
from sqlalchemy.dialects.postgresql import UUID, JSONB

from app.database import Base


class MealType(str, enum.Enum):
    BREAKFAST = "breakfast"
    LUNCH = "lunch"
    DINNER = "dinner"
    SNACK = "snack"
    PRE_WORKOUT = "pre_workout"
    POST_WORKOUT = "post_workout"
    OTHER = "other"


class EntryMethod(str, enum.Enum):
    PHOTO = "photo"
    TEXT = "text"
    MANUAL = "manual"
    TEMPLATE = "template"


class NutritionLog(Base):
    """
    One row per meal/snack. Parsed items are stored as JSONB so we can show
    them line-by-line in the confirm UI and re-render later. Totals are
    denormalized for fast daily aggregation.
    """
    __tablename__ = "nutrition_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    logged_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    meal_type = Column(String(20), nullable=False)             # MealType value
    entry_method = Column(String(16), nullable=False)          # EntryMethod value

    # Photo (R2 URL) and/or raw user text
    photo_url = Column(String(500), nullable=True)
    raw_description = Column(Text, nullable=True)

    # [{name, qty, calories, carbs, protein, fat, fiber}, ...]
    parsed_items = Column(JSONB, nullable=False, default=list)

    total_calories = Column(Integer, nullable=True)
    total_carbs = Column(Numeric(7, 1), nullable=True)
    total_protein = Column(Numeric(7, 1), nullable=True)
    total_fat = Column(Numeric(7, 1), nullable=True)
    total_fiber = Column(Numeric(7, 1), nullable=True)

    # Vision-parse confidence 0–1; 1.0 for manual entries
    confidence = Column(Float, nullable=True)
    edited_after_parse = Column(Boolean, nullable=False, default=False)

    # Optional link to a planned/completed Workout when this is a pre/post workout meal
    related_workout_id = Column(UUID(as_uuid=True), nullable=True)

    __table_args__ = (
        Index("ix_nutrition_user_logged", "user_id", "logged_at"),
    )
