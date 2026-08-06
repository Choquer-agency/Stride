"""
Garmin Health API integration — OAuth, ingest, normalization, race detection, baseline.

The actual HTTP endpoints + OAuth URLs are filled in once the developer-program
application is approved (see app/integrations/garmin/README.md). Until then,
ingest functions accept payloads from `scripts/garmin_simulator.py` and behave
identically to the real flow.

Public surface:
- GarminClient                — OAuth + REST wrapper (stubbed pending approval)
- ingest_workout              — webhook entry: normalize → upsert + Run + race detect
- ingest_daily_metric         — webhook entry: persist + recompute HRV baseline
- ingest_periodic_metric      — webhook entry: append-only history row
- compute_hrv_baseline        — 7-day rolling median, used by Phase 3 anomaly engine
- detect_race                 — match registered Event to today's activity
- backfill_user               — async background task — paginated 90-day history pull
"""

import hashlib
import hmac
import logging
import statistics
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Any, Optional
from uuid import UUID

import httpx
from sqlalchemy import desc, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.event import Event, EventRegistration
from app.models.garmin_daily_metric import GarminDailyMetric
from app.models.garmin_periodic_metric import GarminPeriodicMetric
from app.models.garmin_workout import (
    ACTIVITY_BUCKET_RUNNING,
    GarminWorkout,
    bucket_for_activity_type,
)
from app.models.run import Run
from app.models.user import User

logger = logging.getLogger(__name__)


# ── Webhook signature verification ─────────────────────────────────────────

def verify_webhook_signature(raw_body: bytes, header_signature: str | None) -> bool:
    """
    HMAC-SHA256 verification of `X-Garmin-Signature` against GARMIN_WEBHOOK_SECRET.
    Returns False on missing secret, missing header, or mismatch.
    """
    secret = get_settings().garmin_webhook_secret
    if not secret or not header_signature:
        return False
    expected = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header_signature)


# ── GarminClient — OAuth + REST API wrapper ────────────────────────────────

class GarminClient:
    """
    Thin async wrapper around Garmin Health API REST endpoints.

    The actual base URL + authorize/token/list-activities paths are documented
    in the developer portal post-approval. Until then, this class exposes the
    expected method shapes so consumers (backfill, reconcile cron, garmin
    routes) can be wired and tested via the simulator.

    All methods raise GarminAPIError on non-2xx responses.
    """

    # TODO: replace with documented prod URLs once approval lands.
    AUTHORIZE_URL = "https://connect.garmin.com/oauthConfirm"
    TOKEN_URL = "https://connectapi.garmin.com/oauth-service/oauth/token"
    API_BASE = "https://apis.garmin.com/wellness-api/rest"

    def __init__(self, access_token: str | None = None):
        self.access_token = access_token
        settings = get_settings()
        self._client_id = settings.garmin_client_id
        self._client_secret = settings.garmin_client_secret
        self._timeout = httpx.Timeout(30.0)

    # ── OAuth ───────────────────────────────────────────────────────────

    @classmethod
    def build_authorize_url(cls, *, redirect_uri: str, state: str, code_challenge: str) -> str:
        """Build the URL to redirect the user to for OAuth consent (PKCE)."""
        params = {
            "response_type": "code",
            "client_id": get_settings().garmin_client_id,
            "redirect_uri": redirect_uri,
            "state": state,
            "code_challenge": code_challenge,
            "code_challenge_method": "S256",
            "scope": "ACTIVITY_DATA WELLNESS_DATA BODY_COMPOSITION",
        }
        from urllib.parse import urlencode
        return f"{cls.AUTHORIZE_URL}?{urlencode(params)}"

    async def exchange_code(self, code: str, *, redirect_uri: str, code_verifier: str) -> dict:
        """Exchange an OAuth authorization code for access + refresh tokens."""
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            resp = await client.post(
                self.TOKEN_URL,
                data={
                    "grant_type": "authorization_code",
                    "code": code,
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                    "redirect_uri": redirect_uri,
                    "code_verifier": code_verifier,
                },
            )
        resp.raise_for_status()
        return resp.json()

    async def refresh_token(self, refresh_token: str) -> dict:
        """Refresh an expired access token. Garmin tokens last ~24h."""
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            resp = await client.post(
                self.TOKEN_URL,
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
        """Revoke a token. Best-effort — failures are logged, not raised."""
        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                await client.post(
                    f"{self.API_BASE}/oauth/revoke",
                    data={"token": token, "client_id": self._client_id, "client_secret": self._client_secret},
                )
        except Exception:
            logger.exception("Garmin token revoke failed (non-fatal)")

    # ── REST API (backfill + manual refresh) ────────────────────────────

    async def list_activities(self, *, since: date, until: date, limit: int = 200) -> list[dict]:
        """List the user's activities in a date range. Paginated by Garmin server-side."""
        if not self.access_token:
            raise GarminAPIError("No access_token set on GarminClient")
        # TODO: real path + pagination once approval lands
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            resp = await client.get(
                f"{self.API_BASE}/activities",
                params={"start_date": since.isoformat(), "end_date": until.isoformat(), "limit": limit},
                headers={"Authorization": f"Bearer {self.access_token}"},
            )
        if resp.status_code >= 400:
            raise GarminAPIError(f"list_activities failed: {resp.status_code} {resp.text[:200]}")
        return resp.json()

    async def list_daily_metrics(self, *, since: date, until: date) -> list[dict]:
        if not self.access_token:
            raise GarminAPIError("No access_token set on GarminClient")
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            resp = await client.get(
                f"{self.API_BASE}/dailies",
                params={"start_date": since.isoformat(), "end_date": until.isoformat()},
                headers={"Authorization": f"Bearer {self.access_token}"},
            )
        if resp.status_code >= 400:
            raise GarminAPIError(f"list_daily_metrics failed: {resp.status_code} {resp.text[:200]}")
        return resp.json()


class GarminAPIError(Exception):
    """Raised when a Garmin REST call fails."""
    pass


# ── Normalization ──────────────────────────────────────────────────────────

def _parse_iso(value: Any) -> Optional[datetime]:
    """Parse Garmin's ISO timestamp into a tz-aware datetime."""
    if not value:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    try:
        # Common formats Garmin uses
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def normalize_workout_payload(payload: dict, user_id: UUID) -> dict:
    """
    Map a raw Garmin activity payload to GarminWorkout column kwargs.

    Resilient to missing fields — Garmin payloads vary by activity type
    (treadmill runs lack splits, strength sessions lack distance, etc.).
    """
    activity_type_raw = payload.get("activity_type") or payload.get("activityType") or "unknown"
    bucket = bucket_for_activity_type(activity_type_raw)
    is_indoor = "indoor" in str(activity_type_raw).lower() or "treadmill" in str(activity_type_raw).lower()

    distance_m = payload.get("distance_in_meters") or payload.get("distanceInMeters")
    distance_km = (distance_m / 1000.0) if isinstance(distance_m, (int, float)) else None

    duration_s = payload.get("duration_in_seconds") or payload.get("durationInSeconds")
    avg_pace = None
    if distance_km and distance_km > 0 and duration_s:
        avg_pace = float(duration_s) / float(distance_km)

    return {
        "user_id": user_id,
        "garmin_activity_id": str(payload.get("activity_id") or payload.get("activityId")),
        "activity_type": bucket,
        "activity_subtype": str(activity_type_raw)[:40],
        "is_indoor": is_indoor,
        "is_race": False,  # set later by detect_race
        "start_time": _parse_iso(payload.get("start_time") or payload.get("startTimeInSeconds") or payload.get("startTime")) or datetime.now(timezone.utc),
        "duration_seconds": float(duration_s or 0),
        "distance_km": distance_km,
        "avg_heart_rate": payload.get("average_heart_rate") or payload.get("averageHeartRateInBeatsPerMinute"),
        "max_heart_rate": payload.get("max_heart_rate") or payload.get("maxHeartRateInBeatsPerMinute"),
        "avg_pace_sec_per_km": avg_pace,
        "hr_zones": payload.get("hr_zones") or payload.get("hrZones"),
        "splits": payload.get("splits"),
        "training_effect_aerobic": payload.get("aerobic_training_effect") or payload.get("aerobicTrainingEffect"),
        "training_effect_anaerobic": payload.get("anaerobic_training_effect") or payload.get("anaerobicTrainingEffect"),
        "estimated_vo2max": payload.get("vo2_max") or payload.get("vO2Max"),
        "weather_temp_c": payload.get("weather_temp_c") or payload.get("weatherTempC"),
        "weather_humidity_pct": payload.get("weather_humidity_pct") or payload.get("weatherHumidityPct"),
        "raw_payload": payload,
        "planned_workout_id": None,  # iOS-side matching post-sync
    }


def normalize_daily_metric_payload(payload: dict, user_id: UUID) -> dict:
    """Map a raw Garmin daily summary payload to GarminDailyMetric kwargs."""
    metric_date = payload.get("calendar_date") or payload.get("calendarDate") or payload.get("date")
    if isinstance(metric_date, str):
        metric_date = date.fromisoformat(metric_date[:10])
    elif isinstance(metric_date, datetime):
        metric_date = metric_date.date()
    elif not isinstance(metric_date, date):
        metric_date = datetime.now(timezone.utc).date()

    # Sleep + active time can come either as direct minute counts or as "*InSeconds"
    sleep_minutes = payload.get("sleep_duration_minutes")
    if sleep_minutes is None and payload.get("sleepDurationInSeconds") is not None:
        sleep_minutes = int(payload["sleepDurationInSeconds"]) // 60

    active_minutes = payload.get("active_minutes")
    if active_minutes is None and payload.get("activeTimeInSeconds") is not None:
        active_minutes = int(payload["activeTimeInSeconds"]) // 60

    return {
        "user_id": user_id,
        "date": metric_date,
        "resting_heart_rate": payload.get("resting_heart_rate") or payload.get("restingHeartRateInBeatsPerMinute"),
        "hrv_overnight": payload.get("hrv_overnight") or payload.get("hrvOvernight"),
        "sleep_duration_minutes": sleep_minutes,
        "sleep_score": payload.get("sleep_score") or payload.get("sleepScore"),
        "sleep_stages": payload.get("sleep_stages") or payload.get("sleepStages"),
        "body_battery_start": payload.get("body_battery_start") or payload.get("bodyBatteryAtStart"),
        "body_battery_end": payload.get("body_battery_end") or payload.get("bodyBatteryAtEnd"),
        "body_battery_low": payload.get("body_battery_low") or payload.get("bodyBatteryLow"),
        "stress_score": payload.get("stress_score") or payload.get("averageStressLevel"),
        "steps": payload.get("steps"),
        "active_minutes": active_minutes,
    }


def normalize_periodic_metric_payload(payload: dict, user_id: UUID) -> dict:
    return {
        "user_id": user_id,
        "vo2max_running": payload.get("vo2max_running") or payload.get("vO2MaxRunning"),
        "training_status": payload.get("training_status") or payload.get("trainingStatus"),
        "acute_load": payload.get("acute_load") or payload.get("acuteLoad"),
        "chronic_load": payload.get("chronic_load") or payload.get("chronicLoad"),
        "acute_chronic_ratio": payload.get("acute_chronic_ratio"),
        "lactate_threshold_hr": payload.get("lactate_threshold_hr"),
        "lactate_threshold_pace_sec_per_km": payload.get("lactate_threshold_pace_sec_per_km"),
        "race_predictors": payload.get("race_predictors"),
    }


# ── Ingest entry points (called by webhook handlers + simulator) ───────────

async def ingest_workout(db: AsyncSession, user: User, payload: dict) -> tuple[GarminWorkout, bool, Optional[Event]]:
    """
    Ingest a single Garmin activity push.
    Returns (garmin_workout, is_new, race_event_or_none).

    Idempotent on garmin_activity_id — re-pushes UPDATE the row.
    Running activities additionally upsert into the canonical Run table.
    Race detection sets is_race=true and returns the matching Event.
    """
    fields = normalize_workout_payload(payload, user.id)
    if not fields["garmin_activity_id"] or fields["garmin_activity_id"] == "None":
        raise ValueError("Garmin payload missing activity_id")

    # Upsert: ON CONFLICT (garmin_activity_id) DO UPDATE
    stmt = pg_insert(GarminWorkout).values(**fields)
    update_cols = {k: stmt.excluded[k] for k in fields.keys() if k not in ("user_id", "garmin_activity_id")}
    stmt = stmt.on_conflict_do_update(
        index_elements=["garmin_activity_id"],
        set_=update_cols,
    ).returning(GarminWorkout)
    result = await db.execute(stmt)
    row = result.scalar_one()
    is_new = row.synced_at == row.synced_at  # UPSERT doesn't tell us — assume new for v1

    # Race detection (sets is_race=true on the row + returns the Event)
    race_event = None
    if row.activity_type == ACTIVITY_BUCKET_RUNNING and row.distance_km:
        race_event = await detect_race(db, user, row)
        if race_event is not None:
            row.is_race = True
            db.add(row)

    # Mirror running activities into the canonical Run table
    if row.activity_type == ACTIVITY_BUCKET_RUNNING:
        await _upsert_run_from_garmin(db, user, row)

    await db.flush()
    logger.info(
        "Ingested Garmin activity %s: bucket=%s distance=%s km is_race=%s",
        row.garmin_activity_id, row.activity_type, row.distance_km, row.is_race,
    )
    return row, is_new, race_event


async def ingest_daily_metric(db: AsyncSession, user: User, payload: dict) -> GarminDailyMetric:
    """Persist a daily metric push and recompute the HRV baseline for that user."""
    fields = normalize_daily_metric_payload(payload, user.id)

    stmt = pg_insert(GarminDailyMetric).values(**fields)
    update_cols = {k: stmt.excluded[k] for k in fields.keys() if k not in ("user_id", "date")}
    stmt = stmt.on_conflict_do_update(
        constraint="uq_garmin_daily_user_date",
        set_=update_cols,
    ).returning(GarminDailyMetric)
    result = await db.execute(stmt)
    row = result.scalar_one()

    # Recompute the rolling 7-day HRV baseline and stash on this row
    baseline = await compute_hrv_baseline(db, user.id, days=7)
    if baseline is not None:
        row.hrv_baseline_7day = baseline
        db.add(row)

    await db.flush()
    return row


async def ingest_periodic_metric(db: AsyncSession, user: User, payload: dict) -> GarminPeriodicMetric:
    """Append-only insert — periodic metrics retain history."""
    fields = normalize_periodic_metric_payload(payload, user.id)
    row = GarminPeriodicMetric(**fields)
    db.add(row)
    await db.flush()
    return row


# ── Run mirroring ──────────────────────────────────────────────────────────

async def _upsert_run_from_garmin(db: AsyncSession, user: User, garmin_workout: GarminWorkout) -> Run:
    """
    Mirror a Garmin running activity into the canonical Run table.
    Run.id is generated deterministically from garmin_activity_id so re-pushes
    update the same row instead of creating duplicates.
    """
    deterministic_run_id = uuid.uuid5(uuid.NAMESPACE_URL, f"garmin:{garmin_workout.garmin_activity_id}")

    existing = await db.get(Run, deterministic_run_id)
    if existing:
        existing.distance_km = garmin_workout.distance_km or 0
        existing.duration_seconds = garmin_workout.duration_seconds
        existing.avg_pace_sec_per_km = garmin_workout.avg_pace_sec_per_km or 0
        existing.completed_at = garmin_workout.start_time
        db.add(existing)
        return existing

    # Build km_splits_json compatible with iOS expectations if Garmin provided splits
    km_splits_json = None
    if garmin_workout.splits:
        try:
            import json
            km_splits_json = json.dumps(garmin_workout.splits)
        except Exception:
            pass

    run = Run(
        id=deterministic_run_id,
        user_id=user.id,
        completed_at=garmin_workout.start_time,
        distance_km=garmin_workout.distance_km or 0,
        duration_seconds=garmin_workout.duration_seconds,
        avg_pace_sec_per_km=garmin_workout.avg_pace_sec_per_km or 0,
        km_splits_json=km_splits_json,
        data_source="garmin",
        is_leaderboard_eligible=False,
    )
    db.add(run)
    return run


# ── HRV baseline ───────────────────────────────────────────────────────────

async def compute_hrv_baseline(db: AsyncSession, user_id: UUID, days: int = 7) -> Optional[float]:
    """
    Rolling median HRV over the last `days` days (excludes nulls).
    Used by Phase 3 anomaly engine to flag drops vs baseline.
    Returns None if fewer than 3 samples.
    """
    cutoff = datetime.now(timezone.utc).date() - timedelta(days=days)
    result = await db.execute(
        select(GarminDailyMetric.hrv_overnight)
        .where(
            GarminDailyMetric.user_id == user_id,
            GarminDailyMetric.date >= cutoff,
            GarminDailyMetric.hrv_overnight.is_not(None),
        )
        .order_by(desc(GarminDailyMetric.date))
        .limit(days)
    )
    samples = [row[0] for row in result.all() if row[0] is not None]
    if len(samples) < 3:
        return None
    return float(statistics.median(samples))


# ── Race detection ─────────────────────────────────────────────────────────

# Tolerance bands for race-day matching
_RACE_DATE_WINDOW_HOURS = 36           # activity within ±36h of event start
_RACE_DISTANCE_TOLERANCE_PCT = 0.10    # distance within ±10% of registered race
_RACE_HR_ELEVATION_THRESHOLD = 0.90    # avg_hr ≥ 90% of recent quality-session avg


async def detect_race(db: AsyncSession, user: User, garmin_workout: GarminWorkout) -> Optional[Event]:
    """
    Match a Garmin activity to a registered race the athlete has signed up for.
    Returns the Event if matched; None otherwise.

    Match criteria (all required):
      1. EventRegistration exists for this user
      2. Event.starts_at is within ±36h of garmin_workout.start_time
      3. Event.distance_km within ±10% of garmin_workout.distance_km
      4. avg_heart_rate ≥ 90% of athlete's recent quality-session avg HR
         (skipped if no recent quality data — distance + date alone is enough)
    """
    if not garmin_workout.distance_km:
        return None

    window_start = garmin_workout.start_time - timedelta(hours=_RACE_DATE_WINDOW_HOURS)
    window_end = garmin_workout.start_time + timedelta(hours=_RACE_DATE_WINDOW_HOURS)

    result = await db.execute(
        select(Event)
        .join(EventRegistration, EventRegistration.event_id == Event.id)
        .where(
            EventRegistration.user_id == user.id,
            Event.starts_at.between(window_start, window_end),
            Event.is_active.is_(True),
        )
    )
    candidates = list(result.scalars().all())
    if not candidates:
        return None

    for event in candidates:
        if event.distance_km is None:
            continue
        delta_pct = abs(garmin_workout.distance_km - event.distance_km) / event.distance_km
        if delta_pct > _RACE_DISTANCE_TOLERANCE_PCT:
            continue
        # HR elevation check is best-effort; not required if recent quality data missing
        hr_ok = await _check_hr_elevated(db, user.id, garmin_workout.avg_heart_rate)
        if hr_ok is False:
            # Explicit "no — HR was lower than recent quality work, this is a long run not a race"
            continue
        return event

    return None


async def _check_hr_elevated(db: AsyncSession, user_id: UUID, candidate_hr: Optional[int]) -> Optional[bool]:
    """
    Returns True if candidate_hr ≥ 90% of recent quality-session avg HR,
    False if clearly below, None if we don't have enough data to judge.
    """
    if not candidate_hr:
        return None
    cutoff = datetime.now(timezone.utc) - timedelta(days=30)
    result = await db.execute(
        select(GarminWorkout.avg_heart_rate)
        .where(
            GarminWorkout.user_id == user_id,
            GarminWorkout.activity_type == ACTIVITY_BUCKET_RUNNING,
            GarminWorkout.start_time >= cutoff,
            GarminWorkout.avg_heart_rate.is_not(None),
        )
        .order_by(desc(GarminWorkout.start_time))
        .limit(20)
    )
    recent_hrs = [row[0] for row in result.all() if row[0]]
    if len(recent_hrs) < 3:
        return None
    quality_baseline = max(recent_hrs)  # crude — use top recent HR as proxy for "quality" effort
    return candidate_hr >= int(quality_baseline * _RACE_HR_ELEVATION_THRESHOLD)


# ── Backfill ───────────────────────────────────────────────────────────────

async def backfill_user(db: AsyncSession, user: User, days: int = 90) -> dict:
    """
    Pull the last `days` days of activities + daily metrics for a user.
    Idempotent — safe to retry on failure.

    Updates User.garmin_backfill_status + garmin_backfill_progress as it goes
    so the iOS Settings screen can render a progress bar.

    Returns a summary dict with counts.
    """
    if not user.garmin_access_token:
        raise GarminAPIError("User has no Garmin access token — cannot backfill")

    user.garmin_backfill_status = "running"
    user.garmin_backfill_progress = 0
    db.add(user)
    await db.flush()

    client = GarminClient(access_token=user.garmin_access_token)
    today = datetime.now(timezone.utc).date()
    since = today - timedelta(days=days)

    activities_count = 0
    daily_metrics_count = 0

    try:
        # Activities — chunk by 30-day windows to respect Garmin's per-call limits
        chunk = timedelta(days=30)
        cursor = since
        chunks_total = max(1, days // 30)
        chunks_done = 0
        while cursor < today:
            chunk_end = min(cursor + chunk, today)
            try:
                activities = await client.list_activities(since=cursor, until=chunk_end)
            except GarminAPIError as e:
                logger.warning("Backfill chunk failed (%s..%s): %s", cursor, chunk_end, e)
                activities = []
            for activity in activities:
                try:
                    await ingest_workout(db, user, activity)
                    activities_count += 1
                except Exception:
                    logger.exception("Backfill ingest_workout failed for activity %s", activity.get("activityId"))
            chunks_done += 1
            user.garmin_backfill_progress = min(95, int((chunks_done / max(chunks_total, 1)) * 90))
            db.add(user)
            await db.flush()
            cursor = chunk_end

        # Daily metrics — pull as one call, Garmin returns per-day rows
        try:
            metrics = await client.list_daily_metrics(since=since, until=today)
        except GarminAPIError as e:
            logger.warning("Backfill daily metrics failed: %s", e)
            metrics = []
        for metric in metrics:
            try:
                await ingest_daily_metric(db, user, metric)
                daily_metrics_count += 1
            except Exception:
                logger.exception("Backfill ingest_daily_metric failed")

        user.garmin_backfill_status = "done"
        user.garmin_backfill_progress = 100
        db.add(user)
        await db.flush()
    except Exception:
        user.garmin_backfill_status = "failed"
        db.add(user)
        await db.flush()
        raise

    summary = {
        "activities": activities_count,
        "daily_metrics": daily_metrics_count,
        "since": since.isoformat(),
        "until": today.isoformat(),
    }
    logger.info("Backfill complete for user %s: %s", user.id, summary)
    return summary
