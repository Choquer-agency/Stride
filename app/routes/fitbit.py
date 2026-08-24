"""
Fitbit (Google Health API) routes — OAuth, webhook, refresh, disconnect, status.

Connect flow (mirrors the Garmin flow in routes/garmin.py):
  1. iOS taps "Connect Fitbit" → opens GET /api/fitbit/connect (SFSafariView)
  2. We sign a state token (itsdangerous) carrying the user id
  3. Redirect to Google's OAuth consent (access_type=offline → refresh token)
  4. Google redirects to GET /api/fitbit/callback?code=...&state=...
  5. We exchange the code, fetch the Health identity, persist on User,
     kick off a 90-day backfill
  6. Return an HTML page that deep-links back: stride://fitbit/connected

Ongoing sync is pull-based (hourly cron in services/fitbit_jobs.py). The
webhook endpoint accepts Health API subscription pushes once a subscriber is
configured on GCP project stride-506514; it verifies a shared token and
triggers a 2-day sync for the referenced user.
"""

import asyncio
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import HTMLResponse, RedirectResponse
from itsdangerous import BadSignature, URLSafeTimedSerializer
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import async_session, get_db
from app.models.user import User
from app.services import fitbit_service
from app.services.auth_service import decode_access_token, get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/fitbit", tags=["fitbit"])

_STATE_TTL_SECONDS = 300
_STATE_SALT = "fitbit-oauth-state"


def _state_serializer() -> URLSafeTimedSerializer:
    settings = get_settings()
    secret = settings.admin_session_secret or settings.jwt_secret_key
    if not secret:
        raise RuntimeError("Need admin_session_secret or jwt_secret_key to sign Fitbit OAuth state")
    return URLSafeTimedSerializer(secret, salt=_STATE_SALT)


# ── OAuth flow ──────────────────────────────────────────────────────────────

@router.get("/connect")
async def connect(
    request: Request,
    db: AsyncSession = Depends(get_db),
    token: Optional[str] = None,
) -> RedirectResponse:
    """
    Start the Google Health OAuth flow. Accepts JWT via Authorization header
    or ?token= (SFSafariViewController can't carry our auth headers).
    """
    settings = get_settings()
    if not settings.google_health_client_id:
        raise HTTPException(
            status_code=503,
            detail="Fitbit integration not configured (GOOGLE_HEALTH_CLIENT_ID missing).",
        )

    user: Optional[User] = None
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        try:
            user = await db.get(User, decode_access_token(auth_header[len("Bearer "):]))
        except Exception:
            user = None
    if user is None and token:
        try:
            user = await db.get(User, decode_access_token(token))
        except Exception:
            user = None
    if user is None:
        raise HTTPException(status_code=401, detail="Auth required to connect Fitbit")

    state_payload = {
        "user_id": str(user.id),
        "ts": datetime.now(timezone.utc).timestamp(),
    }
    signed_state = _state_serializer().dumps(state_payload)

    authorize_url = fitbit_service.GoogleHealthClient.build_authorize_url(
        redirect_uri=settings.google_health_redirect_uri,
        state=signed_state,
    )
    return RedirectResponse(url=authorize_url, status_code=302)


@router.get("/callback")
async def callback(
    code: Optional[str] = None,
    state: Optional[str] = None,
    error: Optional[str] = None,
) -> HTMLResponse:
    if error:
        return _callback_html(success=False, message=error)
    if not code or not state:
        return _callback_html(success=False, message="Missing code or state in callback.")

    try:
        payload = _state_serializer().loads(state, max_age=_STATE_TTL_SECONDS)
    except BadSignature:
        return _callback_html(success=False, message="Invalid or expired authorization state.")

    user_id = payload["user_id"]
    settings = get_settings()

    async with async_session() as db:
        user = await db.get(User, user_id)
        if user is None:
            return _callback_html(success=False, message="User not found.")

        client = fitbit_service.GoogleHealthClient()
        try:
            tokens = await client.exchange_code(
                code, redirect_uri=settings.google_health_redirect_uri
            )
        except Exception as exc:
            logger.exception("Google Health token exchange failed for user %s", user_id)
            return _callback_html(success=False, message=f"Token exchange failed: {exc}")

        user.fitbit_access_token = tokens.get("access_token")
        if tokens.get("refresh_token"):
            user.fitbit_refresh_token = tokens["refresh_token"]
        user.fitbit_token_expires_at = datetime.now(timezone.utc) + timedelta(
            seconds=int(tokens.get("expires_in", 3600))
        )
        user.fitbit_connected_at = datetime.now(timezone.utc)
        user.fitbit_disconnected_at = None
        user.fitbit_backfill_status = "pending"
        user.fitbit_backfill_progress = 0

        # Resolve the Google Health user id (webhook payloads reference it)
        try:
            identity_client = fitbit_service.GoogleHealthClient(
                access_token=user.fitbit_access_token
            )
            identity = await identity_client.get_identity()
            user.fitbit_health_user_id = identity.get("healthUserId")
        except Exception:
            logger.exception("Google Health getIdentity failed (non-fatal)")

        db.add(user)
        await db.commit()

    asyncio.create_task(_run_backfill_task(user_id, days=90))
    return _callback_html(success=True, message="Fitbit connected — pulling your last 90 days now.")


async def _run_backfill_task(user_id: str, days: int = 90) -> None:
    try:
        async with async_session() as db:
            user = await db.get(User, user_id)
            if user is None or not user.fitbit_refresh_token:
                return
            await fitbit_service.backfill_user(db, user, days=days)
            await db.commit()
    except Exception:
        logger.exception("Fitbit backfill background task failed for user %s", user_id)


def _callback_html(*, success: bool, message: str) -> HTMLResponse:
    deep_link = "stride://fitbit/connected" if success else "stride://fitbit/connected?error=1"
    title = "Fitbit connected" if success else "Couldn't connect"
    body_class = "ok" if success else "fail"
    html = f"""<!doctype html><html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>
  body{{font-family:-apple-system,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;background:#0b0b0b;color:#eee;text-align:center;padding:24px}}
  .ok h1{{color:#2bd96b}} .fail h1{{color:#ff4d4d}}
  a{{display:inline-block;margin-top:24px;padding:14px 28px;background:#FF2617;color:#fff;border-radius:12px;font-weight:600;text-decoration:none}}
</style></head>
<body class="{body_class}">
  <div>
    <h1>{title}</h1>
    <p>{message}</p>
    <a href="{deep_link}">Return to Stride</a>
    <script>setTimeout(()=>{{location.href='{deep_link}'}}, 800)</script>
  </div>
</body></html>"""
    return HTMLResponse(content=html)


# ── Webhook (Health API subscription pushes) ────────────────────────────────

@router.post("/webhook", status_code=204)
async def webhook(request: Request) -> Response:
    """
    Receive a Health API subscription notification. Notifications tell us WHO
    has new data, not the data itself — we respond by pulling the last 2 days
    for that user. Verified via the shared token we set on the subscription.
    """
    settings = get_settings()
    supplied = request.headers.get("X-Stride-Webhook-Token") or request.query_params.get("token")
    if not settings.google_health_webhook_token or supplied != settings.google_health_webhook_token:
        raise HTTPException(status_code=401, detail="Invalid webhook token")

    payload = await request.json()
    notifications = payload.get("notifications") or [payload]
    if not isinstance(notifications, list):
        notifications = [notifications]

    user_ids: set[str] = set()
    async with async_session() as db:
        for note in notifications:
            # Subscription payloads reference users as "users/{healthUserId}"
            user_ref = str(note.get("user") or "")
            health_user_id = user_ref.rsplit("/", 1)[-1] if user_ref else None
            if not health_user_id:
                continue
            result = await db.execute(
                select(User).where(User.fitbit_health_user_id == health_user_id)
            )
            user = result.scalar_one_or_none()
            if user and user.fitbit_refresh_token:
                user_ids.add(str(user.id))

    for user_id in user_ids:
        asyncio.create_task(_run_webhook_sync(user_id))
    return Response(status_code=204)


async def _run_webhook_sync(user_id: str) -> None:
    try:
        async with async_session() as db:
            user = await db.get(User, user_id)
            if user is None:
                return
            await fitbit_service.sync_user(db, user, days=2)
            await db.commit()
    except Exception:
        logger.exception("Fitbit webhook sync failed for user %s", user_id)


# ── Manual refresh + disconnect + status ────────────────────────────────────

@router.post("/refresh")
async def refresh(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """User-triggered force pull of the last 2 days."""
    if not current_user.fitbit_refresh_token:
        raise HTTPException(status_code=400, detail="Fitbit not connected")
    summary = await fitbit_service.sync_user(db, current_user, days=2)
    return {"ok": True, **summary}


@router.post("/disconnect")
async def disconnect(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Revoke tokens and stop syncing. Historical data is retained."""
    if current_user.fitbit_refresh_token:
        await fitbit_service.GoogleHealthClient().revoke(current_user.fitbit_refresh_token)

    current_user.fitbit_access_token = None
    current_user.fitbit_refresh_token = None
    current_user.fitbit_token_expires_at = None
    # Keep fitbit_health_user_id so reconnects under the same account are recognized
    current_user.fitbit_disconnected_at = datetime.now(timezone.utc)
    db.add(current_user)
    await db.flush()
    return {"ok": True}


class FitbitStatusResponse(BaseModel):
    connected: bool
    connected_at: Optional[datetime] = None
    disconnected_at: Optional[datetime] = None
    backfill_status: Optional[str] = None
    backfill_progress: int = 0


@router.get("/status", response_model=FitbitStatusResponse)
async def status(current_user: User = Depends(get_current_user)) -> FitbitStatusResponse:
    return FitbitStatusResponse(
        connected=bool(current_user.fitbit_refresh_token),
        connected_at=current_user.fitbit_connected_at,
        disconnected_at=current_user.fitbit_disconnected_at,
        backfill_status=current_user.fitbit_backfill_status,
        backfill_progress=current_user.fitbit_backfill_progress or 0,
    )
