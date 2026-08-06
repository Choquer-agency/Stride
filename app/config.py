from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Legacy — no code path uses OpenAI anymore; kept optional so existing .env files don't break.
    openai_api_key: str = ""
    openai_model: str = "gpt-4.1"

    # Anthropic — default fallback model; most calls override via app.services.coaching_models.
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-opus-5"

    # Database (Neon PostgreSQL)
    database_url: str

    # JWT Authentication
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 10080  # 7 days

    # Google OAuth
    google_client_id: str = ""

    # Apple Sign In — must match the iOS app's bundle identifier. Apple embeds
    # this as the `aud` claim in identity tokens and we verify it on the server.
    apple_bundle_id: str = "com.stride-v.2.app"

    # LangFuse (LLM observability)
    langfuse_public_key: str = ""
    langfuse_secret_key: str = ""
    langfuse_host: str = "https://us.cloud.langfuse.com"

    # PostHog (analytics)
    posthog_api_key: str = ""
    posthog_host: str = "https://us.i.posthog.com"

    # Voice synthesis stays server-side so provider credentials are never shipped
    # in the App Store binary.
    elevenlabs_api_key: str = ""
    elevenlabs_voice_id: str = "fDeOZu1sNd7qahm2fV4k"

    # Cloudflare R2 (S3-compatible storage)
    r2_endpoint_url: str = ""
    r2_access_key_id: str = ""
    r2_secret_access_key: str = ""
    r2_bucket_name: str = "stride-assets"
    r2_public_url: str = ""

    # Admin session
    admin_session_secret: str = ""

    # APNs (Phase 0)
    apns_key_id: str = ""
    apns_team_id: str = ""
    apns_bundle_id: str = "com.stride-v.2.app"
    apns_use_sandbox: bool = False
    apns_key_path: str = ""           # Preferred — file path to .p8
    apns_key_base64: str = ""         # Fallback — base64-encoded .p8 contents

    # Garmin (Phase 1)
    garmin_client_id: str = ""
    garmin_client_secret: str = ""
    garmin_webhook_secret: str = ""
    garmin_redirect_uri: str = "http://localhost:8000/api/garmin/callback"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"


@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()
