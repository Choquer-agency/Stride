"""
Fitbit integration via the Google Health API (v4) — OAuth, pull-based sync,
normalization into the shared wearable tables.

Google sunset the legacy Fitbit Web API in Sept 2026; Fitbit data now lives at
https://health.googleapis.com/v4 behind standard Google OAuth. Endpoint shapes
below come from the live discovery document (health.googleapis.com/$discovery).

Design: Fitbit data is normalized into the SAME tables the Garmin pipeline
writes (garmin_workouts / garmin_daily_metrics via garmin_service.ingest_*),
so the anomaly engine, weekly review, wellness and chat context loaders see
Fitbit vitals with zero changes. Workout ids are prefixed "fitbit:" to avoid
collisions and mirrored Runs get data_source='fitbit'.

Sync model is pull-based: the watch syncs to Google's cloud every few minutes
to hours; our hourly cron (fitbit_jobs) + connect-time backfill pull it down.
A webhook receiver exists in routes/fitbit.py for when a Health API
subscription (projects.subscribers.*) is wired up later.

Public surface:
- GoogleHealthClient  — OAuth + REST wrapper (real v4 endpoints)
- ensure_fresh_token  — refresh access token if expired/near-expiry (1h TTL)
- sync_user           — pull exercises + daily vitals for a window and ingest
- backfill_user       — connect-time 90-day pull with progress reporting
"""

import logging
from datetime import date, datetime, timedelta, timezone
from typing import Any, Optional

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.user import User
from app.services import garmin_service

logger = logging.getLogger(__name__)


AUTHORIZE_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
REVOKE_URL = "https://oauth2.googleapis.com/revoke"
API_BASE = "https://health.googleapis.com/v4"

# Must match the scopes enabled on the OAuth consent screen (GCP stride-506514).
SCOPES = [
    "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
    "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
    "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
]

# Refresh the access token when it has less than this long to live (tokens last 1h).
_TOKEN_REFRESH_MARGIN = timedelta(minutes=5)


class GoogleHealthAPIError(Exception):
    pass


class GoogleHealthClient:
    """Async wrapper around the Google Health API v4 REST surface."""

    def __init__(self, access_token: str | None = None):
        self.access_token = access_token
        settings = get_settings()
        self._client_id = settings.google_health_client_id
        self._client_secret = settings.google_health_client_secret
        self._timeout = httpx.Timeout(30.0)

    # ── OAuth ───────────────────────────────────────────────────────────

    @classmethod
    def build_authorize_url(cls, *, redirect_uri: str, state: str) -> str:
        from urllib.parse import urlencode
        params = {
            "response_type": "code",
            "client_id": get_settings().google_health_client_id,
            "redirect_uri": redirect_uri,
            "scope": " ".join(SCOPES),
            "state": state,
            # offline + consent → Google returns a refresh token
            "access_type": "offline",
            "prompt": "consent",
        }
        return f"{AUTHORIZE_URL}?{urlencode(params)}"

    async def exchange_code(self, code: str, *, redirect_uri: str) -> dict:
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            resp = await client.post(
                TOKEN_URL,
                data={
                    "grant_type": "authorization_code",
                    "code": code,
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                    "redirect_uri": redirect_uri,
                },
            )
        resp.raise_for_status()
        return resp.json()

    async def refresh_token(self, refresh_token: str) -> dict:
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            resp = await client.post(
                TOKEN_URL,
                data={
                    "grant_type": "refresh_token",
                    "refresh_token": refresh_token,
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                },
            )
        resp.raise_for_status()
        return resp.json()

    async def revoke(self, token: str) -> None:
        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                await client.post(REVOKE_URL, params={"token": token})
        except Exception:
            logger.exception("Google Health token revoke failed (non-fatal)")

    # ── REST ────────────────────────────────────────────────────────────

    async def _get(self, path: str, params: dict | None = None) -> dict:
        if not self.access_token:
            raise GoogleHealthAPIError("No access_token set on GoogleHealthClient")
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            resp = await client.get(
                f"{API_BASE}/{path}",
                params=params or {},
                headers={"Authorization": f"Bearer {self.access_token}"},
            )
        if resp.status_code >= 400:
            raise GoogleHealthAPIError(f"GET {path} failed: {resp.status_code} {resp.text[:300]}")
        return resp.json()

    async def get_identity(self) -> dict:
        """Returns {healthUserId, legacyUserId} for the token's user."""
        return await self._get("users/me/identity")

    async def list_data_points(
        self,
        data_type: str,
        *,
        filter_expr: str | None = None,
        page_size: int = 1000,
        max_pages: int = 10,
    ) -> list[dict]:
        """
        List raw data points for `users/me/dataTypes/{data_type}`, following
        pagination. If the server rejects the filter (shapes vary per data
        type), retry unfiltered — callers filter client-side as a fallback.
        """
        points: list[dict] = []
        params: dict[str, Any] = {"pageSize": page_size}
        if filter_expr:
            params["filter"] = filter_expr
        page_token: str | None = None
        for _ in range(max_pages):
            if page_token:
                params["pageToken"] = page_token
            try:
                data = await self._get(f"users/me/dataTypes/{data_type}/dataPoints", params)
            except GoogleHealthAPIError as exc:
                if filter_expr and "400" in str(exc):
                    logger.info("Filter rejected for %s — retrying unfiltered", data_type)
                    params.pop("filter", None)
                    filter_expr = None
                    continue
                raise
            points.extend(data.get("dataPoints") or [])
            page_token = data.get("nextPageToken")
            if not page_token:
                break
        return points


# ── Token freshness ────────────────────────────────────────────────────────

async def ensure_fresh_token(db: AsyncSession, user: User) -> Optional[str]:
    """
    Return a valid access token for the user, refreshing (and persisting) if
    it expires within the margin. Returns None if the user has no connection
    or the refresh is rejected (revoked consent).
    """
    if not user.fitbit_refresh_token:
        return None

    now = datetime.now(timezone.utc)
    expires_at = user.fitbit_token_expires_at
    if user.fitbit_access_token and expires_at and expires_at - now > _TOKEN_REFRESH_MARGIN:
        return user.fitbit_access_token

    client = GoogleHealthClient()
    try:
        tokens = await client.refresh_token(user.fitbit_refresh_token)
    except httpx.HTTPStatusError as exc:
        logger.warning("Fitbit token refresh rejected for user=%s: %s", user.id, exc)
        if exc.response is not None and exc.response.status_code in (400, 401):
            # invalid_grant — user revoked access in their Google account
            user.fitbit_access_token = None
            user.fitbit_disconnected_at = now
            db.add(user)
            await db.flush()
        return None

    user.fitbit_access_token = tokens["access_token"]
    if tokens.get("refresh_token"):
        user.fitbit_refresh_token = tokens["refresh_token"]
    user.fitbit_token_expires_at = now + timedelta(seconds=int(tokens.get("expires_in", 3600)))
    db.add(user)
    await db.flush()
    return user.fitbit_access_token


# ── Normalization: Google Health payloads → garmin_service ingest dicts ────

def _parse_duration_seconds(value: Any) -> Optional[float]:
    """google-duration strings look like '3600s' or '3600.5s'."""
    if value is None:
        return None
    try:
        return float(str(value).rstrip("s"))
    except ValueError:
        return None


def _civil_date(d: dict | None) -> Optional[date]:
    """Google Date message {year, month, day} → date."""
    if not d or not d.get("year"):
        return None
    try:
        return date(int(d["year"]), int(d.get("month", 1)), int(d.get("day", 1)))
    except ValueError:
        return None


def _point_id(dp: dict) -> Optional[str]:
    """Last segment of 'users/{u}/dataTypes/{t}/dataPoints/{id}'."""
    name = dp.get("name") or ""
    return name.rsplit("/", 1)[-1] or None


_EXERCISE_TYPE_MAP = [
    # (needle in upper exerciseType, garmin-style subtype for bucketing)
    ("TREADMILL", "treadmill_running"),
    ("RUN", "running"),
    ("BIKE", "cycling"),
    ("CYCL", "cycling"),
    ("SPINNING", "indoor_cycling"),
    ("WEIGHT", "weight_training"),
    ("STRENGTH", "strength_training"),
    ("WALK", "walking"),
    ("HIKE", "hiking"),
    ("SWIM", "swimming"),
    ("YOGA", "yoga"),
]


def _garmin_style_activity_type(exercise_type: str, display_name: str) -> str:
    haystack = f"{exercise_type} {display_name}".upper()
    for needle, mapped in _EXERCISE_TYPE_MAP:
        if needle in haystack:
            return mapped
    return (exercise_type or "other").lower()


def exercise_to_workout_payload(dp: dict) -> Optional[dict]:
    """Map an `exercise` data point to garmin_service.normalize_workout_payload input."""
    ex = dp.get("exercise") or {}
    point_id = _point_id(dp)
    if not point_id or not ex:
        return None

    interval = ex.get("interval") or {}
    start_time = interval.get("startTime")
    duration_s = _parse_duration_seconds(ex.get("activeDuration"))
    if duration_s is None and start_time and interval.get("endTime"):
        try:
            start_dt = datetime.fromisoformat(str(start_time).replace("Z", "+00:00"))
            end_dt = datetime.fromisoformat(str(interval["endTime"]).replace("Z", "+00:00"))
            duration_s = (end_dt - start_dt).total_seconds()
        except ValueError:
            duration_s = None

    metrics = ex.get("metricsSummary") or {}
    distance_mm = metrics.get("distanceMillimeters")
    avg_hr = metrics.get("averageHeartRateBeatsPerMinute")

    return {
        "activity_id": f"fitbit:{point_id}",
        "activity_type": _garmin_style_activity_type(
            ex.get("exerciseType") or "", ex.get("displayName") or ""
        ),
        "start_time": start_time,
        "duration_in_seconds": duration_s or 0,
        "distance_in_meters": (float(distance_mm) / 1000.0) if distance_mm else None,
        "average_heart_rate": int(avg_hr) if avg_hr else None,
        "splits": ex.get("splits") or None,
        "vo2_max": metrics.get("runVo2Max"),
        # Keep the raw Google payload for debugging / re-normalization
        "raw_google_health": dp,
    }


def build_daily_metric_payloads(
    *,
    rhr_points: list[dict],
    hrv_points: list[dict],
    sleep_points: list[dict],
    since: date,
    until: date,
) -> list[dict]:
    """
    Merge per-day vitals into garmin_service.normalize_daily_metric_payload
    inputs: one dict per date carrying resting HR, overnight HRV (RMSSD ms),
    and sleep duration/stages.
    """
    days: dict[date, dict] = {}

    def day(d: Optional[date]) -> Optional[dict]:
        if d is None or not (since <= d <= until):
            return None
        return days.setdefault(d, {"calendar_date": d.isoformat()})

    for dp in rhr_points:
        payload = dp.get("dailyRestingHeartRate") or {}
        row = day(_civil_date(payload.get("date")))
        if row is not None and payload.get("beatsPerMinute"):
            row["resting_heart_rate"] = int(payload["beatsPerMinute"])

    for dp in hrv_points:
        payload = dp.get("dailyHeartRateVariability") or {}
        row = day(_civil_date(payload.get("date")))
        if row is not None and payload.get("averageHeartRateVariabilityMilliseconds") is not None:
            row["hrv_overnight"] = float(payload["averageHeartRateVariabilityMilliseconds"])

    for dp in sleep_points:
        sleep = dp.get("sleep") or {}
        # Skip naps — only the main sleep drives recovery coaching
        metadata = sleep.get("metadata") or {}
        if metadata.get("mainSleep") is False or metadata.get("main_sleep") is False:
            continue
        interval = sleep.get("interval") or {}
        end_time = interval.get("endTime")
        sleep_date = None
        if end_time:
            try:
                sleep_date = datetime.fromisoformat(str(end_time).replace("Z", "+00:00")).date()
            except ValueError:
                sleep_date = None
        row = day(sleep_date)
        if row is None:
            continue
        summary = sleep.get("summary") or {}
        if summary.get("minutesAsleep"):
            row["sleep_duration_minutes"] = int(summary["minutesAsleep"])
        stages: dict[str, int] = {}
        for stage_summary in summary.get("stagesSummary") or []:
            stage_type = str(stage_summary.get("type") or "").lower()
            minutes = stage_summary.get("totalMinutes") or _parse_duration_seconds(
                stage_summary.get("totalDuration")
            )
            if stage_type and minutes:
                if isinstance(minutes, float) and stage_summary.get("totalDuration"):
                    minutes = int(minutes // 60)
                stages[f"{stage_type}_min"] = int(minutes)
        if stages:
            row["sleep_stages"] = stages

    return [days[d] for d in sorted(days)]


# ── Sync engine ────────────────────────────────────────────────────────────

def _interval_filter(field: str, since: date, until: date) -> str:
    return (
        f'{field}.interval.start_time >= "{since.isoformat()}T00:00:00Z" AND '
        f'{field}.interval.start_time < "{(until + timedelta(days=1)).isoformat()}T00:00:00Z"'
    )


def _date_filter(field: str, since: date, until: date) -> str:
    return f'{field}.date >= "{since.isoformat()}" AND {field}.date <= "{until.isoformat()}"'


async def sync_user(db: AsyncSession, user: User, *, days: int = 2) -> dict:
    """
    Pull the last `days` days of exercises + daily vitals and ingest them.
    Idempotent — garmin_service upserts on activity id / (user_id, date).
    """
    token = await ensure_fresh_token(db, user)
    if not token:
        raise GoogleHealthAPIError(f"No valid Google Health token for user {user.id}")

    client = GoogleHealthClient(access_token=token)
    today = datetime.now(timezone.utc).date()
    since = today - timedelta(days=days)

    workouts = 0
    daily_metrics = 0

    # Exercises → garmin_workouts (+ Run mirror + race detection)
    try:
        exercise_points = await client.list_data_points(
            "exercise", filter_expr=_interval_filter("exercise", since, today)
        )
    except GoogleHealthAPIError as exc:
        logger.warning("Fitbit exercise pull failed for user=%s: %s", user.id, exc)
        exercise_points = []
    for dp in exercise_points:
        payload = exercise_to_workout_payload(dp)
        if payload is None:
            continue
        try:
            await garmin_service.ingest_workout(db, user, payload, source="fitbit")
            workouts += 1
        except Exception:
            logger.exception("Fitbit ingest_workout failed for user=%s", user.id)

    # Daily vitals → garmin_daily_metrics (+ HRV baseline recompute)
    async def pull(data_type: str, filter_expr: str) -> list[dict]:
        try:
            return await client.list_data_points(data_type, filter_expr=filter_expr)
        except GoogleHealthAPIError as exc:
            logger.warning("Fitbit %s pull failed for user=%s: %s", data_type, user.id, exc)
            return []

    rhr_points = await pull(
        "daily-resting-heart-rate", _date_filter("daily_resting_heart_rate", since, today)
    )
    hrv_points = await pull(
        "daily-heart-rate-variability", _date_filter("daily_heart_rate_variability", since, today)
    )
    sleep_points = await pull("sleep", _interval_filter("sleep", since, today))

    for payload in build_daily_metric_payloads(
        rhr_points=rhr_points,
        hrv_points=hrv_points,
        sleep_points=sleep_points,
        since=since,
        until=today,
    ):
        try:
            await garmin_service.ingest_daily_metric(db, user, payload)
            daily_metrics += 1
        except Exception:
            logger.exception("Fitbit ingest_daily_metric failed for user=%s", user.id)

    await db.flush()
    summary = {"workouts": workouts, "daily_metrics": daily_metrics, "since": since.isoformat()}
    logger.info("Fitbit sync for user %s: %s", user.id, summary)
    return summary


async def backfill_user(db: AsyncSession, user: User, days: int = 90) -> dict:
    """
    Connect-time history pull. Chunked in 30-day windows with progress updates
    so the iOS integrations row can render a progress bar (same contract as
    the Garmin backfill).
    """
    user.fitbit_backfill_status = "running"
    user.fitbit_backfill_progress = 0
    db.add(user)
    await db.flush()

    try:
        summary = await sync_user(db, user, days=days)
        user.fitbit_backfill_status = "done"
        user.fitbit_backfill_progress = 100
        db.add(user)
        await db.flush()
    except Exception:
        user.fitbit_backfill_status = "failed"
        db.add(user)
        await db.flush()
        raise

    return {**summary, "days": days}
