from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    openai_api_key: str
    openai_model: str = "gpt-4.1"

    # Anthropic (A/B testing)
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-opus-4-6"

    # Database (Neon PostgreSQL)
    database_url: str

    # JWT Authentication
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 10080  # 7 days

    # Google OAuth
    google_client_id: str = ""

    # LangFuse (LLM observability)
    langfuse_public_key: str = ""
    langfuse_secret_key: str = ""
    langfuse_host: str = "https://us.cloud.langfuse.com"

    # PostHog (analytics)
    posthog_api_key: str = ""
    posthog_host: str = "https://us.i.posthog.com"

    # Cloudflare R2 (S3-compatible storage)
    r2_endpoint_url: str = ""
    r2_access_key_id: str = ""
    r2_secret_access_key: str = ""
    r2_bucket_name: str = "stride-assets"
    r2_public_url: str = ""

    # Admin session
    admin_session_secret: str = ""

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"


@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()
