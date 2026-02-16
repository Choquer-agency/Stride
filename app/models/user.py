import uuid
import enum
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, Float, Text, Boolean
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


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
