import logging

import posthog
from app.config import get_settings

logger = logging.getLogger(__name__)

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
    if not posthog.api_key:
        return
    # Analytics must never break a request path — swallow SDK errors.
    try:
        posthog.capture(distinct_id=user_id, event=event, properties=properties or {})
    except Exception:
        logger.warning("posthog capture failed (event=%s)", event, exc_info=True)


def identify(user_id: str, properties: dict | None = None):
    _init()
    if not posthog.api_key:
        return
    try:
        if hasattr(posthog, "identify"):
            posthog.identify(distinct_id=user_id, properties=properties or {})
        else:
            # posthog-python >= 6 removed identify(); set() writes person properties.
            posthog.set(distinct_id=user_id, properties=properties or {})
    except Exception:
        logger.warning("posthog identify failed", exc_info=True)


def shutdown():
    try:
        if posthog.api_key:
            posthog.flush()
            posthog.shutdown()
    except Exception:
        logger.warning("posthog shutdown failed", exc_info=True)
