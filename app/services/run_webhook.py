"""Per-athlete run webhooks queued only after a successful database commit."""

import asyncio
import copy
import hashlib
import ipaddress
import json
import logging
import re
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit
from uuid import UUID

import httpx
from sqlalchemy import event, select, update
from sqlalchemy.orm import Session

from app.database import async_session
from app.models.run import Run
from app.models.user import User

logger = logging.getLogger(__name__)
PAYLOAD_LIMIT = 500_000
DEDUPE_WINDOW = timedelta(minutes=10)
_QUEUE_KEY = "stride_run_webhook_events"
_HEADER = re.compile(r"^[A-Za-z0-9!#$%&'*+.^_`|~-]{1,100}$")


def validate_webhook_config(url: str, header: str = "Authorization") -> None:
    parsed = urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise ValueError("Webhook URL must be a public HTTPS URL without credentials or a fragment")
    if parsed.hostname.lower() in {"localhost", "127.0.0.1", "::1"}:
        raise ValueError("Webhook URL cannot target localhost")
    try:
        address = ipaddress.ip_address(parsed.hostname)
    except ValueError:
        address = None
    if address is not None and not address.is_global:
        raise ValueError("Webhook URL must use a public address")
    if not _HEADER.fullmatch(header):
        raise ValueError("Webhook key header is invalid")


def queue_run_webhook(db, run_id: UUID, user_id: UUID, event_name: str) -> None:
    """Register a run event on the transaction; delivery starts after commit."""
    if event_name not in {"run.completed", "run.updated"}:
        raise ValueError("Unknown run webhook event")
    events = db.info.setdefault(_QUEUE_KEY, {})
    key = (run_id, user_id)
    # A run inserted and updated in one transaction is still a completion.
    events[key] = "run.completed" if events.get(key) == "run.completed" else event_name


@event.listens_for(Session, "after_commit")
def _on_commit(session: Session) -> None:
    events = session.info.pop(_QUEUE_KEY, {})
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        logger.warning("Run webhook skipped: no running event loop")
        return
    for (run_id, user_id), event_name in events.items():
        loop.create_task(deliver_run_webhook(run_id, user_id, event_name))


@event.listens_for(Session, "after_rollback")
def _on_rollback(session: Session) -> None:
    session.info.pop(_QUEUE_KEY, None)


def _parse_list(raw: str | None) -> list:
    if not raw:
        return []
    try:
        value = json.loads(raw)
        return value if isinstance(value, list) else []
    except (ValueError, TypeError):
        return []


def _hr_every_five_seconds(raw: str | None) -> list:
    selected = []
    last_bucket = None
    for sample in _parse_list(raw):
        if not isinstance(sample, dict):
            continue
        try:
            bucket = int(float(sample["t"]) // 5)
        except (KeyError, TypeError, ValueError, OverflowError):
            continue
        if bucket != last_bucket:
            selected.append(sample)
            last_bucket = bucket
    return selected


def _route_summary(points: object) -> dict | None:
    if not isinstance(points, list) or not points:
        return None
    first, last = points[0], points[-1]
    if not isinstance(first, dict) or not isinstance(last, dict):
        return {"point_count": len(points)}
    return {
        "point_count": len(points),
        "start": {"latitude": first.get("latitude"), "longitude": first.get("longitude")},
        "finish": {"latitude": last.get("latitude"), "longitude": last.get("longitude")},
    }


def _encoded(payload: dict) -> bytes:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str, allow_nan=False).encode("utf-8")


def build_payload(run: Run, user: User, event_name: str) -> dict:
    metrics = copy.deepcopy(run.metrics_json or {})
    route = metrics.get("route_points")
    data = {
        "splits": metrics.get("splits") or _parse_list(run.km_splits_json),
        "treadmill": metrics.get("treadmill"),
        "elevation_profile": metrics.get("elevation_profile"),
        "hr_samples": _hr_every_five_seconds(run.hr_samples_json),
        "cadence_samples": metrics.get("cadence_samples"),
        "power_samples": metrics.get("power_samples"),
        "weather": metrics.get("weather"),
        "route_summary": _route_summary(route),
    }
    payload = {
        "event": event_name,
        "run_id": str(run.id),
        "athlete_email": user.email,
        "athlete_display_name": user.display_name or user.name or user.email,
        "source": run.data_source,
        "completed_at": (run.completed_at if run.completed_at.tzinfo else
                         run.completed_at.replace(tzinfo=timezone.utc)).isoformat(),
        "distance_km": run.distance_km,
        "duration_s": run.duration_seconds,
        "avg_pace_sec_per_km": run.avg_pace_sec_per_km,
        "avg_heart_rate": run.avg_heart_rate,
        "max_heart_rate": run.max_heart_rate,
        "elevation_gain_m": run.elevation_gain_m,
        "elevation_loss_m": run.elevation_loss_m,
        "matched_planned_workout": {
            "title": run.planned_workout_title,
            "type": run.planned_workout_type,
            "planned_distance_km": run.planned_distance_km,
            "week_number": run.week_number,
        },
        "data": data,
    }

    # Keep the detailed record in the database. Only the outgoing copy is cut.
    arrays = [(data, "hr_samples"), (data, "elevation_profile"), (data, "splits"),
              (data, "cadence_samples"), (data, "power_samples")]
    treadmill = data.get("treadmill")
    if isinstance(treadmill, dict):
        arrays += [(treadmill, "speed_samples"), (treadmill, "incline_samples")]
    while len(_encoded(payload)) > PAYLOAD_LIMIT:
        candidates = [(len(_encoded(parent[key])), parent, key) for parent, key in arrays
                      if isinstance(parent.get(key), list) and len(parent[key]) > 1]
        if not candidates:
            # An unusually large scalar or nested provider field should not escape the cap.
            data["weather"] = None
            data["treadmill"] = None
            data["route_summary"] = None
            if len(_encoded(payload)) > PAYLOAD_LIMIT:
                raise ValueError("Run webhook payload cannot be reduced below 500 KB")
            break
        _, parent, key = max(candidates, key=lambda item: item[0])
        parent[key] = parent[key][::2]
        data["truncated_for_webhook"] = True
    return payload


def _run_fingerprint(run: Run) -> str:
    fields = {column.name: getattr(run, column.name) for column in Run.__table__.columns
              if column.name not in {"synced_at", "webhook_claimed_at", "webhook_payload_hash"}}
    return hashlib.sha256(_encoded(fields)).hexdigest()


async def deliver_run_webhook(run_id: UUID, user_id: UUID, event_name: str) -> None:
    """Claim, send with retries, and release a failed claim for later retry."""
    try:
        async with async_session() as db:
            result = await db.execute(select(Run, User).join(User, Run.user_id == User.id).where(
                Run.id == run_id, Run.user_id == user_id))
            pair = result.first()
            if pair is None:
                return
            run, user = pair
            if not user.run_webhook_url or not user.run_webhook_key:
                return
            validate_webhook_config(user.run_webhook_url, user.run_webhook_key_header or "Authorization")
            payload = build_payload(run, user, event_name)
            content_hash = _run_fingerprint(run)
            cutoff = datetime.now(timezone.utc) - DEDUPE_WINDOW
            claim = await db.execute(update(Run).where(
                Run.id == run_id, Run.user_id == user_id,
                (Run.webhook_payload_hash.is_distinct_from(content_hash)) |
                (Run.webhook_claimed_at.is_(None)) |
                (Run.webhook_claimed_at <= cutoff),
            ).values(webhook_claimed_at=datetime.now(timezone.utc),
                     webhook_payload_hash=content_hash).returning(Run.id))
            if claim.scalar_one_or_none() is None:
                return
            await db.commit()
            url = user.run_webhook_url
            headers = {user.run_webhook_key_header or "Authorization": f"Bearer {user.run_webhook_key}"}

        for attempt in range(3):
            try:
                async with httpx.AsyncClient(timeout=5.0, follow_redirects=False, trust_env=False) as client:
                    response = await client.post(url, json=payload, headers=headers)
                if 200 <= response.status_code < 300:
                    logger.info("Run webhook delivered run=%s athlete=%s status=%s", run_id, user_id, response.status_code)
                    return
                status = response.status_code
            except httpx.HTTPError:
                status = "network_error"
            if attempt < 2:
                await asyncio.sleep(0.5 * (2 ** attempt))

        logger.warning("Run webhook failed run=%s athlete=%s status=%s after 3 attempts", run_id, user_id, status)
        async with async_session() as db:
            await db.execute(update(Run).where(
                Run.id == run_id, Run.user_id == user_id,
                Run.webhook_payload_hash == content_hash,
            ).values(webhook_claimed_at=None))
            await db.commit()
    except Exception:
        # The run is committed already. Nothing here may propagate to sync or ingest.
        logger.exception("Run webhook task failed run=%s athlete=%s", run_id, user_id)
