import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Integer, String, ForeignKey, Index, Numeric
from sqlalchemy.dialects.postgresql import UUID, JSONB

from app.database import Base


class RecipeTemplate(Base):
    """
    Saved meal that the athlete can tap-to-log without re-parsing.
    Built up over time from frequently-eaten meals (oatmeal+banana, etc.).
    """
    __tablename__ = "recipe_templates"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    name = Column(String(120), nullable=False)
    items = Column(JSONB, nullable=False, default=list)

    total_calories = Column(Integer, nullable=True)
    total_carbs = Column(Numeric(7, 1), nullable=True)
    total_protein = Column(Numeric(7, 1), nullable=True)
    total_fat = Column(Numeric(7, 1), nullable=True)

    use_count = Column(Integer, nullable=False, default=0)
    last_used_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        Index("ix_recipe_user_use", "user_id", "use_count"),
    )
