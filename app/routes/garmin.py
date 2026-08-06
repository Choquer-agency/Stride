"""
Garmin Health API routes — OAuth, webhooks, refresh, disconnect, status.

Connect flow (PKCE):
  1. iOS taps "Connect Garmin" → opens GET /api/garmin/connect (in SFSafariView)
  2. We generate code_verifier + code_challenge + state token
  3. State is signed via itsdangerous so callback can recover the verifier
  4. Redirect to Garmin authorize URL
  5. User consents → Garmin redirects to GET /api/garmin/callback?code=...&state=...
  6. We verify state, exchange code → tokens, persist on User, kick off backfill
  7. Return an HTML page that deep-links back to the app: stride://garmin/connected

Webhooks are HMAC-signed (X-Garmin-Signature). We verify before any DB work.
Per the v2 plan §Phase 1, ingest is idempotent on Garmin's activity_id.
"""

import asyncio
import base64
import hashlib
import logging
import secrets
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import HTMLResponse, RedirectResponse
from itsdangerous import BadSignature, URLSafeTimedSerializer
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import async_session, get_db
from app.models.coaching_event import CoachingEvent, CoachingEventType, CoachingEventTriggerSource
from app.models.user import User
from app.services import garmin_service
from app.services.auth_service import decode_access_token, get_current_user
from app.services.post_run_check import run_post_run_check

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/garmin", tags=["garmin"])


# State token TTL (seconds) — user has 5 minutes to complete consent
_STATE_TTL_SECONDS = 300
_STATE_SALT = "garmin-oauth-state"


def _state_serializer() -> URLSafeTimedSerializer:
    settings = get_settings()
    secret = settings.admin_session_secret or settings.jwt_secret_key
    if not secret:
        raise RuntimeError("Need admin_session_secret or jwt_secret_key to sign Garmin OAuth state")
    return URLSafeTimedSerializer(secret, salt=_STATE_SALT)


def _generate_pkce_pair() -> tuple[str, str]:
    """Generate a (code_verifier, code_challenge) pair per RFC 7636."""
    verifier_bytes = secrets.token_urlsafe(64)[:64]
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier_bytes.encode("ascii")).digest()
    ).rstrip(b"=").decode("ascii")
    return verifier_bytes, challenge


# ── OAuth flow ──────────────────────────────────────────────────────────────

@router.get("/connect")
async def connect(
    request: Request,
    db: AsyncSession = Depends(get_db),
    token: Optional[str] = None,
) -> RedirectResponse:
    """
    Start the Garmin OAuth flow. Generates PKCE verifier + state token, then
    redirects the user's browser to Garmin's authorize endpoint.

    Auth: accepts JWT from either the Authorization Bearer header (preferred)
    or a ?token= query param (so SFSafariViewController on iOS can authenticate
    without carrying our auth headers).
    """
    settings = get_settings()
    if not settings.garmin_client_id:
        raise HTTPException(
            status_code=503,
            detail="Garmin integration not configured on server (GARMIN_CLIENT_ID missing).",
        )

    # Resolve user from either header or query param
    user: Optional[User] = None
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        try:
            user_id = decode_access_token(auth_header[len("Bearer "):])
            user = await db.get(User, user_id)
        except Exception:
            user = None
    if user is None and token:
        try:
            user_id = decode_access_token(token)
            user = await db.get(User, user_id)
        except Exception:
            user = None
    if user is None:
        raise HTTPException(status_code=401, detail="Auth required to connect Garmin")

    code_verifier, code_challenge = _generate_pkce_pair()
    state_payload = {
        "user_id": str(user.id),
        "code_verifier": code_verifier,
        "ts": datetime.now(timezone.utc).timestamp(),
    }
    signed_state = _state_serializer().dumps(state_payload)

    authorize_url = garmin_service.GarminClient.build_authorize_url(
        redirect_uri=settings.garmin_redirect_uri,
        state=signed_state,
        code_challenge=code_challenge,
    )
    return RedirectResponse(url=authorize_url, status_code=302)


@router.get("/callback")
async def callback(
    code: Optional[str] = None,
    state: Optional[str] = None,
    error: Optional[str] = None,
    error_description: Optional[str] = None,
) -> HTMLResponse:
    """
    OAuth callback. Verifies state, exchanges code for tokens, persists on User,
    and kicks off the 90-day backfill as a background task.

    Returns an HTML page that deep-links back into the app via stride://garmin/connected.
    """
    if error:
        return _callback_html(success=False, message=error_description or error)

    if not code or not state:
        return _callback_html(success=False, message="Missing code or state in callback.")

    try:
        payload = _state_serializer().loads(state, max_age=_STATE_TTL_SECONDS)
    except BadSignature:
        return _callback_html(success=False, message="Invalid or expired authorization state.")

    user_id = payload["user_id"]
    code_verifier = payload["code_verifier"]
    settings = get_settings()

    async with async_session() as db:
        user = await db.get(User, user_id)
        if user is None:
            return _callback_html(success=False, message="User not found.")

        # Exchange the auth code for tokens
        try:
            client = garmin_service.GarminClient()
            token_data = await client.exchange_code(
                code,
                redirect_uri=settings.garmin_redirect_uri,
                code_verifier=code_verifier,
            )
        except Exception as exc:
            logger.exception("Garmin token exchange failed for user %s", user_id)
            return _callback_html(success=False, message=f"Token exchange failed: {exc}")

        user.garmin_access_token = token_data.get("access_token")
        user.garmin_refresh_token = token_data.get("refresh_token")
        user.garmin_user_id = token_data.get("user_id") or token_data.get("garmin_user_id")
        user.garmin_connected_at = datetime.now(timezone.utc)
        user.garmin_disconnected_at = None
        user.garmin_backfill_status = "pending"
        user.garmin_backfill_progress = 0
        db.add(user)
        await db.flush()

    # Kick off 90-day backfill as a background task (separate session)
    asyncio.create_task(_run_backfill_task(user_id, days=90))
    return _callback_html(success=True, message="Garmin connected — pulling your last 90 days now.")


async def _run_backfill_task(user_id: str, days: int = 90) -> None:
    """Background backfill task — opens its own DB session."""
    try:
        async with async_session() as db:
            user = await db.get(User, user_id)
            if user is None or not user.garmin_access_token:
                logger.warning("Backfill task: user %s missing or disconnected", user_id)
                return
            await garmin_service.backfill_user(db, user, days=days)
            await db.commit()
    except Exception:
        logger.exception("Garmin backfill background task failed for user %s", user_id)


def _callback_html(*, success: bool, message: str) -> HTMLResponse:
    """Render a tiny success/failure page that deep-links back to the iOS app."""
    deep_link = "stride://garmin/connected" if success else "stride://garmin/connected?error=1"
    title = "Garmin connected" if success else "Couldn't connect"
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


# ── Webhooks (HMAC-verified, idempotent) ────────────────────────────────────

async def _resolve_webhook_user(db: AsyncSession, payload: dict) -> Optional[User]:
    """
    Find the Stride User for a webhook payload.
    Garmin webhooks identify the user via the userId field that we stored
    during OAuth callback as User.garmin_user_id.
    """
    garmin_user_id = (
        payload.get("user_id")
        or payload.get("userId")
        or payload.get("garmin_user_id")
    )
    if not garmin_user_id:
        return None

    from sqlalchemy import select
    result = await db.execute(
        select(User).where(User.garmin_user_id == str(garmin_user_id))
    )
    user = result.scalar_one_or_none()
    # Reject pushes for disconnected users (per plan: data retained, ingestion stopped)
    if user and user.garmin_disconnected_at and not user.garmin_access_token:
        return None
    return user


@router.post("/webhook/workout", status_code=204)
async def webhook_workout(
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> Response:
    """
    Receive a single activity push (or a batch).
    Verifies HMAC, ingests each activity (idempotent), kicks off post-run check
    (Phase 3 wires the LLM call — initially writes an info-level coaching event).
    """
    raw_body = await request.body()
    signature = request.headers.get("X-Garmin-Signature")
    if not garmin_service.verify_webhook_signature(raw_body, signature):
        raise HTTPException(status_code=401, detail="Invalid Garmin webhook signature")

    payload = await request.json()
    activities = payload.get("activities") or [payload]
    if not isinstance(activities, list):
        activities = [activities]

    for activity_payload in activities:
        user = await _resolve_webhook_user(db, activity_payload)
        if user is None:
            logger.info("Skipping webhook for unknown/disconnected user payload")
            continue
        try:
            row, _is_new, race_event = await garmin_service.ingest_workout(db, user, activity_payload)
        except Exception:
            logger.exception("ingest_workout failed for user=%s", user.id)
            continue

        # Phase 3: kick off the post-run check as a background task. We commit
        # the ingest immediately so the post-run-check task can read from a
        # consistent DB state in its own session.
        await db.commit()

        race_event_id = race_event.id if race_event is not None else None
        asyncio.create_task(
            run_post_run_check(
                user_id=user.id,
                workout_id=row.id,
                race_event_id=race_event_id,
            )
        )

    return Response(status_code=204)


@router.post("/webhook/daily-metrics", status_code=204)
async def webhook_daily_metrics(
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> Response:
    raw_body = await request.body()
    signature = request.headers.get("X-Garmin-Signature")
    if not garmin_service.verify_webhook_signature(raw_body, signature):
        raise HTTPException(status_code=401, detail="Invalid Garmin webhook signature")

    payload = await request.json()
    metrics = payload.get("dailies") or [payload]
    if not isinstance(metrics, list):
        metrics = [metrics]

    for m in metrics:
        user = await _resolve_webhook_user(db, m)
        if user is None:
            continue
        try:
            await garmin_service.ingest_daily_metric(db, user, m)
        except Exception:
            logger.exception("ingest_daily_metric failed for user=%s", user.id)

    return Response(status_code=204)


@router.post("/webhook/periodic-metrics", status_code=204)
async def webhook_periodic_metrics(
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> Response:
    raw_body = await request.body()
    signature = request.headers.get("X-Garmin-Signature")
    if not garmin_service.verify_webhook_signature(raw_body, signature):
        raise HTTPException(status_code=401, detail="Invalid Garmin webhook signature")

    payload = await request.json()
    metrics = payload.get("periodic") or [payload]
    if not isinstance(metrics, list):
        metrics = [metrics]

    for m in metrics:
        user = await _resolve_webhook_user(db, m)
        if user is None:
            continue
        try:
            await garmin_service.ingest_periodic_metric(db, user, m)
        except Exception:
            logger.exception("ingest_periodic_metric failed for user=%s", user.id)

    return Response(status_code=204)


# NOTE: Phase 1's `_log_post_run_info` stub was replaced by Phase 3's full
# `run_post_run_check` orchestrator (see app/services/post_run_check.py).
# The orchestrator writes the appropriate coaching_events row (POST_RUN_INFO,
# POST_RUN_CHECK, RED_FLAG, CONSOLIDATION, or POST_RACE) and handles all
# notification + adjustment logic.


# ── Manual refresh + disconnect + status ────────────────────────────────────

@router.post("/refresh")
async def refresh(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """User-triggered force pull of the last 24h. Useful when a webhook drops."""
    if not current_user.garmin_access_token:
        raise HTTPException(status_code=400, detail="Garmin not connected")
    summary = await garmin_service.backfill_user(db, current_user, days=2)
    return {"ok": True, **summary}


@router.post("/disconnect")
async def disconnect(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """
    Clear Garmin tokens. Historical data retained per plan (athlete can reconnect
    later and pick up from the disconnect time).
    """
    if current_user.garmin_access_token:
        try:
            await garmin_service.GarminClient().revoke(current_user.garmin_access_token)
        except Exception:
            logger.exception("Garmin revoke failed (non-fatal)")

    current_user.garmin_access_token = None
    current_user.garmin_refresh_token = None
    # Keep garmin_user_id so reconnect under the same Garmin account is recognized
    current_user.garmin_disconnected_at = datetime.now(timezone.utc)
    db.add(current_user)
    await db.flush()
    return {"ok": True}


class GarminStatusResponse(BaseModel):
    connected: bool
    connected_at: Optional[datetime] = None
    disconnected_at: Optional[datetime] = None
    backfill_status: Optional[str] = None
    backfill_progress: int = 0


@router.get("/status", response_model=GarminStatusResponse)
async def status(current_user: User = Depends(get_current_user)) -> GarminStatusResponse:
    return GarminStatusResponse(
        connected=bool(current_user.garmin_access_token),
        connected_at=current_user.garmin_connected_at,
        disconnected_at=current_user.garmin_disconnected_at,
        backfill_status=current_user.garmin_backfill_status,
        backfill_progress=current_user.garmin_backfill_progress or 0,
    )
