"""
APNs push notification service.

Sends notifications directly to Apple Push Notification service via aioapns,
respecting:
  - per-loop coaching mode (`User.coaching_modes`)
  - pause state (`User.coaching_paused_until`)
  - quiet hours (`User.quiet_hours_start` / `quiet_hours_end`)
  - muted notification types (`User.muted_notification_types`)
  - daily rate limit (max 4 non-critical / day)

`force_critical=True` bypasses everything except missing token.
Critical pushes during pause hold for 24h then escalate (handled in caller).

Returns (delivered: bool, reason: str). Caller logs to coaching_events.
"""

import base64
import logging
import os
import tempfile
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from aioapns import APNs, NotificationRequest, PushType
from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.coaching_event import CoachingEvent
from app.models.user import User

logger = logging.getLogger(__name__)


_DAILY_NON_CRITICAL_LIMIT = 4

# Module-level singleton APNs client; lazy-initialized.
_apns_client: Optional[APNs] = None
_apns_temp_key_path: Optional[str] = None  # Tracked so we can remove the temp file at shutdown.


def _ensure_apns_client() -> APNs:
    global _apns_client, _apns_temp_key_path
    if _apns_client is not None:
        return _apns_client

    settings = get_settings()
    if not settings.apns_key_id or not settings.apns_team_id:
        raise RuntimeError(
            "APNs not configured: missing APNS_KEY_ID and/or APNS_TEAM_ID env vars. "
            "See app/integrations/apns/README.md for setup."
        )

    key_path = settings.apns_key_path
    if not key_path and settings.apns_key_base64:
        # Decode base64 → temp file (aioapns requires a path)
        decoded = base64.b64decode(settings.apns_key_base64)
        fd, tmp_path = tempfile.mkstemp(suffix=".p8", prefix="apns_")
        with os.fdopen(fd, "wb") as f:
            f.write(decoded)
        _apns_temp_key_path = tmp_path
        key_path = tmp_path

    if not key_path or not os.path.exists(key_path):
        raise RuntimeError(
            f"APNs P8 key not found at {key_path or '(unset)'}. "
            "Set APNS_KEY_PATH or APNS_KEY_BASE64 env var. See app/integrations/apns/README.md."
        )

    _apns_client = APNs(
        key=key_path,
        key_id=settings.apns_key_id,
        team_id=settings.apns_team_id,
        topic=settings.apns_bundle_id,
        use_sandbox=settings.apns_use_sandbox,
    )
    logger.info(
        "APNs client initialized: bundle=%s sandbox=%s",
        settings.apns_bundle_id, settings.apns_use_sandbox,
    )
    return _apns_client


def cleanup_apns_temp_files() -> None:
    """Remove any temp .p8 file created from APNS_KEY_BASE64. Called at shutdown."""
    global _apns_temp_key_path
    if _apns_temp_key_path and os.path.exists(_apns_temp_key_path):
        try:
            os.remove(_apns_temp_key_path)
        except OSError:
            pass
        _apns_temp_key_path = None


async def send_push(
    db: AsyncSession,
    user: User,
    *,
    title: str,
    body: str,
    deep_link: Optional[str] = None,
    notification_type: Optional[str] = None,
    loop_name: Optional[str] = None,
    force_critical: bool = False,
    badge: Optional[int] = None,
) -> tuple[bool, str]:
    """
    Send a push to a user, respecting their coaching preferences and rate limits.

    Args:
        user: target user (must have apns_device_token)
        title / body: visible notification text
        deep_link: stride:// URL routed by DeepLinkRouter on tap
        notification_type: matched against user.muted_notification_types
        loop_name: matched against user.coaching_modes ("weekly_review", "post_run_check", etc.)
        force_critical: bypass shadow/off/quiet/rate-limit. Token must still exist.
        badge: optional iOS app icon badge count

    Returns:
        (delivered, reason) — caller logs both to coaching_events.
    """
    if not user.apns_device_token:
        return False, "no_device_token"

    if not force_critical:
        # Loop-mode check
        if loop_name:
            mode = (user.coaching_modes or {}).get(loop_name, "live")
            if mode == "off":
                return False, f"loop_off:{loop_name}"
            if mode == "shadow":
                return False, f"shadow:{loop_name}"

        # Pause check
        if user.coaching_paused_until is not None:
            now = datetime.now(timezone.utc)
            if user.coaching_paused_until > now or user.coaching_paused_until == datetime.fromtimestamp(0, tz=timezone.utc):
                return False, "user_paused"

        # Muted notification type
        if notification_type and notification_type in (user.muted_notification_types or []):
            return False, f"muted_type:{notification_type}"

        # Quiet hours (athlete-local approximation — use UTC for v2 since we don't yet
        # store user TZ; quiet hours typically defaulted to Pacific evenings)
        if user.quiet_hours_start and user.quiet_hours_end:
            now_local = datetime.now().time()  # server-local
            if _in_quiet_window(now_local, user.quiet_hours_start, user.quiet_hours_end):
                return False, "quiet_hours"

        # Daily rate limit (non-critical)
        delivered_today = await _count_pushes_delivered_today(db, user.id)
        if delivered_today >= _DAILY_NON_CRITICAL_LIMIT:
            return False, f"rate_limit:{delivered_today}/{_DAILY_NON_CRITICAL_LIMIT}"

    # Build payload
    aps_payload: dict = {
        "alert": {"title": title, "body": body},
        "sound": "default",
    }
    if badge is not None:
        aps_payload["badge"] = badge

    payload: dict = {"aps": aps_payload}
    if deep_link:
        payload["deep_link"] = deep_link
    if notification_type:
        payload["notification_type"] = notification_type

    try:
        client = _ensure_apns_client()
        request = NotificationRequest(
            device_token=user.apns_device_token,
            message=payload,
            push_type=PushType.ALERT,
        )
        result = await client.send_notification(request)
        if result.is_successful:
            logger.info("APNs delivered to user=%s type=%s loop=%s", user.id, notification_type, loop_name)
            return True, "delivered"
        else:
            logger.warning("APNs failed: user=%s status=%s desc=%s", user.id, result.status, result.description)
            return False, f"apns_error:{result.status}:{result.description}"
    except Exception as exc:
        logger.exception("APNs exception for user=%s", user.id)
        return False, f"exception:{type(exc).__name__}"


async def _count_pushes_delivered_today(db: AsyncSession, user_id: UUID) -> int:
    """Number of non-critical notifications delivered to a user since midnight UTC."""
    # Using UTC midnight for v2 simplicity — we'll move to athlete-local when TZ field exists
    today_utc_midnight = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    result = await db.execute(
        select(func.count(CoachingEvent.id)).where(
            and_(
                CoachingEvent.user_id == user_id,
                CoachingEvent.notification_delivered.is_(True),
                CoachingEvent.triggered_at >= today_utc_midnight,
            )
        )
    )
    return result.scalar_one() or 0


def _in_quiet_window(now_time, start, end) -> bool:
    """
    True if now_time is inside the quiet-hours window. Handles wrap-around (22:00–07:00).
    All inputs are time objects.
    """
    if start <= end:
        return start <= now_time < end
    # Window crosses midnight
    return now_time >= start or now_time < end
