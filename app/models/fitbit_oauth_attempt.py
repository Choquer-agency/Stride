"""Short-lived, single-use Fitbit authorization attempts shared by all workers."""
from sqlalchemy import Column, DateTime, String

from app.database import Base


class FitbitOAuthAttempt(Base):
    __tablename__ = "fitbit_oauth_attempts"

    # Store only a digest of the browser secret. No OAuth codes or tokens.
    nonce_hash = Column(String(64), primary_key=True)
    user_id = Column(String(36), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False, index=True)
