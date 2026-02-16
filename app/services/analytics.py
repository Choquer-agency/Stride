import posthog
from app.config import get_settings

_initialized = False


def _init():
    global _initialized
    if _initialized:
        return
    settings = get_settings()
    if settings.posthog_api_key:
        posthog.api_key = settings.posthog_api_key
        posthog.host = settings.posthog_host
    _initialized = True


def capture(user_id: str, event: str, properties: dict | None = None):
    _init()
    if posthog.api_key:
        posthog.capture(distinct_id=user_id, event=event, properties=properties or {})


def identify(user_id: str, properties: dict | None = None):
    _init()
    if posthog.api_key:
        posthog.identify(distinct_id=user_id, properties=properties or {})


def shutdown():
    if posthog.api_key:
        posthog.flush()
        posthog.shutdown()
