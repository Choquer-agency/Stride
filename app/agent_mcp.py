"""Shared Stride coaching tools, served over HTTP and local stdio."""

import asyncio
import datetime as dt
import json
import uuid
from typing import Any

from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from sqlalchemy import text

from app.database import engine
from app.services.agent_plan_edit import replace_in_active_plan, update_active_plan
from app.services.run_webhook import deliver_run_webhook, _route_summary

DEFAULT_ATHLETE_EMAIL = "brycechoquer@me.com"
UTC = dt.timezone.utc

INSTRUCTIONS = """Use list_athletes to select an athlete by email. Every athlete-specific tool
defaults to Bryce when athlete_email is omitted. Read get_coaching_context and
get_active_plan before editing. Plan text uses line-start WEEK 1, WEEK 2, etc.,
with day lines such as '- Monday: Easy Run - Total: 8 km'. Keep gym sessions on
one line. Prefer replace_in_plan for small changes. update_plan replaces the
entire active plan. Both edits set source=server_edit and trigger the existing
phone card, 'Your coach updated your plan'; the athlete taps Apply. Give a clear
change_note. Times are UTC unless explicitly labeled otherwise."""

server = MCPServer(name="stride-coach", instructions=INSTRUCTIONS, version="2.0.0")


def _jsonable(value: Any) -> Any:
    if isinstance(value, (dt.datetime, dt.date, uuid.UUID)):
        return str(value)
    if isinstance(value, dict):
        return {k: _jsonable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_jsonable(v) for v in value]
    return value


def _dump(value: Any) -> str:
    return json.dumps(_jsonable(value), default=str)


def _limit(limit: int, maximum: int = 100) -> int:
    if not 1 <= limit <= maximum:
        raise ValueError(f"limit must be between 1 and {maximum}")
    return limit


def _date(value: str, name: str) -> dt.date | None:
    try:
        return dt.date.fromisoformat(value) if value else None
    except ValueError as exc:
        raise ValueError(f"{name} must be YYYY-MM-DD") from exc


def _range(from_date: str, through_date: str) -> tuple[dt.date | None, dt.date | None]:
    first, last = _date(from_date, "from_date"), _date(through_date, "through_date")
    if first and last and first > last:
        raise ValueError("from_date must be on or before through_date")
    return first, last


async def _athlete(conn, athlete_email: str = "") -> dict:
    email = athlete_email or DEFAULT_ATHLETE_EMAIL
    row = (await conn.execute(text(
        "SELECT id, email, display_name, date_of_birth, gender, height_cm, created_at "
        "FROM users WHERE lower(email) = lower(:email)"
    ), {"email": email})).mappings().first()
    if row is None:
        raise ValueError(f"No athlete with email {email}; use list_athletes")
    return dict(row)


async def _active_plan(conn, athlete_email: str = "", *, lock: bool = False) -> dict:
    athlete = await _athlete(conn, athlete_email)
    if lock:
        await conn.execute(text("SELECT id FROM users WHERE id = :uid FOR UPDATE"),
                           {"uid": athlete["id"]})
    suffix = " FOR UPDATE" if lock else ""
    row = (await conn.execute(text(
        "SELECT * FROM training_plans WHERE user_id = :uid AND is_active = true "
        "ORDER BY updated_at DESC LIMIT 1" + suffix
    ), {"uid": athlete["id"]})).mappings().first()
    if row is None:
        raise ValueError(f"No active training plan for {athlete['email']}")
    return dict(row)


async def _rows(conn, query: str, params: dict) -> list[dict]:
    result = await conn.execute(text(query), params)
    return [_jsonable(dict(row)) for row in result.mappings().all()]


def _samples(raw: str | None, max_samples: int, full_fidelity: bool) -> dict:
    try:
        samples = json.loads(raw) if raw else []
    except (ValueError, TypeError):
        return {"hr_samples": [], "hr_samples_error": "Invalid stored HR JSON"}
    if not isinstance(samples, list):
        return {"hr_samples": [], "hr_samples_error": "Invalid stored HR format"}
    if len(samples) > 50_000:
        raise ValueError("Stored HR series exceeds the 50000 sample safety limit")
    if full_fidelity or len(samples) <= max_samples:
        selected = samples
    else:
        # Evenly cover the complete run, including its first and last samples.
        selected = [samples[round(i * (len(samples) - 1) / (max_samples - 1))]
                    for i in range(max_samples)]
    return {"hr_samples": selected, "hr_sample_count": len(samples),
            "hr_samples_returned": len(selected)}


def _elapsed_seconds(time: str) -> int:
    try:
        parts = time.split(":")
        if len(parts) == 1:
            seconds = int(parts[0])
        elif len(parts) == 2 and len(parts[1]) == 2 and 0 <= int(parts[1]) < 60:
            seconds = int(parts[0]) * 60 + int(parts[1])
        else:
            raise ValueError("Invalid mm:ss")
    except ValueError as exc:
        raise ValueError("time must be nonnegative seconds or mm:ss") from exc
    if seconds < 0:
        raise ValueError("time must be nonnegative")
    return seconds


@server.tool()
async def list_athletes() -> str:
    """List all Stride athletes with email, display name, race, and run count.
    Use the email as athlete_email in every athlete-specific tool. Bryce is the default."""
    async with engine.connect() as conn:
        return _dump(await _rows(conn,
            "SELECT u.email, u.display_name, u.created_at, p.race_name, "
            "(SELECT count(*) FROM runs r WHERE r.user_id = u.id) AS runs "
            "FROM users u LEFT JOIN training_plans p ON p.user_id = u.id AND p.is_active = true "
            "ORDER BY u.created_at LIMIT 1000", {}))


@server.tool()
async def get_coaching_context(athlete_email: str = "") -> str:
    """Start here. Read profile, active plan metadata, onboarding answers, four
    recent weekly check-ins, and five weeks of run volume. Select by athlete_email."""
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        plan = await _active_plan(conn, athlete_email)
        checkins = await _rows(conn, "SELECT week_ending, status, answers FROM weekly_checkins "
            "WHERE user_id = :uid ORDER BY week_ending DESC LIMIT 4", {"uid": athlete["id"]})
        volumes = await _rows(conn, "SELECT date_trunc('week', completed_at)::date AS week, "
            "round(sum(distance_km)::numeric, 1) AS km, count(*) AS runs FROM runs "
            "WHERE user_id = :uid AND completed_at > now() - interval '5 weeks' "
            "GROUP BY 1 ORDER BY 1", {"uid": athlete["id"]})
    return _dump({"athlete": athlete,
                  "plan": {k: v for k, v in plan.items() if k != "raw_plan_content"},
                  "athlete_profile_from_onboarding": plan.get("athlete_profile"),
                  "recent_checkins": checkins, "weekly_volume_last_5_weeks": volumes})


@server.tool()
async def get_active_plan(athlete_email: str = "") -> str:
    """Read the full active plan text exactly as the phone parses it. Defaults to
    Bryce; pass athlete_email from list_athletes for another athlete."""
    async with engine.connect() as conn:
        return (await _active_plan(conn, athlete_email))["raw_plan_content"]


@server.tool()
async def replace_in_plan(find: str, replace: str, change_note: str,
                          athlete_email: str = "") -> str:
    """Replace one exact snippet in the selected athlete's active plan. find must
    match once. Preserve WEEK headings and day lines. change_note is shown to the
    athlete. The phone then shows 'Your coach updated your plan' and an Apply button."""
    try:
        async with engine.begin() as conn:
            plan = await _active_plan(conn, athlete_email, lock=True)
            await replace_in_active_plan(conn, plan, find, replace, change_note)
    except ValueError as exc:
        raise ToolError(str(exc)) from exc
    return "Plan updated. The athlete will see the Apply card on the next plan sync."


@server.tool()
async def update_plan(new_content: str, change_note: str, athlete_email: str = "") -> str:
    """Replace the ENTIRE active plan for athlete_email (Bryce by default).
    Include the complete plan, starting with a line-start WEEK 1 header, consecutive
    WEEK numbers, and day lines like '- Monday: Easy Run - Total: 8 km'. Put each
    gym session on one line. Invalid format is rejected. The phone shows 'Your
    coach updated your plan' and the athlete taps Apply. change_note is required."""
    try:
        async with engine.begin() as conn:
            plan = await _active_plan(conn, athlete_email, lock=True)
            await update_active_plan(conn, plan, new_content, change_note)
    except ValueError as exc:
        raise ToolError(str(exc)) from exc
    return "Full plan replaced. The athlete will see the Apply card on the next plan sync."


@server.tool()
async def list_runs(limit: int = 30, athlete_email: str = "", from_date: str = "",
                    through_date: str = "") -> str:
    """List runs newest first with summary, notes, and matched plan workout.
    Filter by athlete_email and inclusive YYYY-MM-DD dates. Limit 1-100.
    Use get_run for splits, shoe, and HR samples."""
    first, last = _range(from_date, through_date)
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = await _rows(conn,
            "SELECT r.id, r.completed_at, r.distance_km, r.duration_seconds, "
            "r.avg_pace_sec_per_km, r.avg_heart_rate, r.max_heart_rate, "
            "r.planned_workout_title, r.planned_workout_type, r.planned_distance_km, "
            "r.completion_score, r.week_number, r.plan_name, r.data_source, "
            "r.notes, r.feedback_rating, s.name AS shoe_name "
            "FROM runs r LEFT JOIN shoes s ON s.id = r.shoe_id "
            "WHERE r.user_id = :uid AND (CAST(:first AS date) IS NULL OR r.completed_at >= CAST(:first AS date)) "
            "AND (CAST(:last AS date) IS NULL OR r.completed_at < CAST(:last AS date) + interval '1 day') "
            "ORDER BY r.completed_at DESC LIMIT :limit",
            {"uid": athlete["id"], "first": first, "last": last, "limit": _limit(limit)})
    return _dump(rows)


@server.tool()
async def get_run(run_id: str, athlete_email: str = "", max_hr_samples: int = 200,
                  full_fidelity: bool = False) -> str:
    """Read one run by ID with km splits, HR samples, shoe, notes, and matched
    workout, elevation gain/loss, route summary, treadmill speed and incline,
    cadence, power, and weather. Defaults to 200 evenly spaced HR and elevation
    samples. Set full_fidelity=true for every stored sample and GPS point."""
    if not 2 <= max_hr_samples <= 5000:
        raise ValueError("max_hr_samples must be between 2 and 5000")
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = await _rows(conn,
            "SELECT r.*, s.name AS shoe_name, s.is_retired AS shoe_retired "
            "FROM runs r LEFT JOIN shoes s ON s.id = r.shoe_id "
            "WHERE r.id = :id AND r.user_id = :uid",
            {"id": uuid.UUID(run_id), "uid": athlete["id"]})
    if not rows:
        raise ValueError("Run not found for this athlete")
    row = rows[0]
    raw_hr = row.pop("hr_samples_json", None)
    raw_splits = row.pop("km_splits_json", None)
    metrics = row.pop("metrics_json", None) or {}
    route = metrics.pop("route_points", None)
    row["route_summary"] = _route_summary(route)
    if full_fidelity:
        row["route_points"] = route
    profile = metrics.get("elevation_profile")
    if isinstance(profile, list) and not full_fidelity and len(profile) > max_hr_samples:
        metrics["elevation_profile"] = [profile[round(i * (len(profile) - 1) / (max_hr_samples - 1))]
                                        for i in range(max_hr_samples)]
    row["metrics"] = metrics
    try:
        row["km_splits"] = json.loads(raw_splits) if raw_splits else []
    except ValueError:
        row["km_splits"] = []
        row["km_splits_error"] = "Invalid stored split JSON"
    row.update(_samples(raw_hr, max_hr_samples, full_fidelity))
    return _dump(row)


@server.tool()
async def hr_at(run_id: str, time: str, athlete_email: str = "") -> str:
    """Get the nearest HR sample at a run elapsed time. time is seconds such as
    '840' or mm:ss such as '14:00'. Use a run ID from list_runs. Select the
    athlete by email; only that athlete's run can be read."""
    seconds = _elapsed_seconds(time)
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = await _rows(conn, "SELECT hr_samples_json FROM runs WHERE id = :id AND user_id = :uid",
                           {"id": uuid.UUID(run_id), "uid": athlete["id"]})
    if not rows:
        raise ValueError("Run not found for this athlete")
    samples = _samples(rows[0]["hr_samples_json"], 200, True)["hr_samples"]
    if not samples:
        raise ValueError("Run has no HR samples")
    nearest = min(samples, key=lambda sample: abs(sample["t"] - seconds))
    return _dump({"requested_seconds": seconds, "sample": nearest})


@server.tool()
async def elevation_at(run_id: str, time: str, athlete_email: str = "") -> str:
    """Get the nearest elevation sample for a run at elapsed seconds or mm:ss.
    Reads the stored elevation profile, or GPS route altitude when available.
    Select the run's athlete by email; other athletes' runs are not accessible."""
    seconds = _elapsed_seconds(time)
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = await _rows(conn, "SELECT metrics_json FROM runs WHERE id = :id AND user_id = :uid",
                           {"id": uuid.UUID(run_id), "uid": athlete["id"]})
    if not rows:
        raise ValueError("Run not found for this athlete")
    metrics = rows[0]["metrics_json"] or {}
    profile = metrics.get("elevation_profile") or [
        {"t": point.get("timestamp"), "elevation_m": point.get("altitude")}
        for point in (metrics.get("route_points") or []) if isinstance(point, dict)
    ]
    samples = [point for point in profile if isinstance(point, dict)
               and point.get("t") is not None and point.get("elevation_m") is not None]
    if not samples:
        raise ValueError("Run has no elevation samples")
    nearest = min(samples, key=lambda sample: abs(float(sample["t"]) - seconds))
    return _dump({"requested_seconds": seconds, "sample": nearest})


@server.tool()
async def log_run(date_iso: str, distance_km: float, duration_seconds: int,
                  planned_workout_title: str = "", week_number: int = 0,
                  completion_score: int = 0, notes: str = "", athlete_email: str = "") -> str:
    """Log a manual run for athlete_email (Bryce by default). date_iso is an
    ISO timestamp or YYYY-MM-DD. The phone syncs the run and checks off a
    matching planned workout by title and day. Give distance in km and duration
    in seconds."""
    if distance_km <= 0 or duration_seconds <= 0:
        raise ValueError("distance_km and duration_seconds must be positive")
    when = dt.datetime.fromisoformat(date_iso.replace("Z", "+00:00"))
    if when.tzinfo is None:
        when = when.replace(hour=17, minute=0, tzinfo=UTC)
    pace = round(duration_seconds / distance_km, 1)
    new_run_id = uuid.uuid4()
    async with engine.begin() as conn:
        plan = await _active_plan(conn, athlete_email)
        await conn.execute(text(
            "INSERT INTO runs (id, user_id, completed_at, distance_km, duration_seconds, "
            "avg_pace_sec_per_km, planned_workout_title, plan_name, week_number, "
            "completion_score, data_source, notes, is_leaderboard_eligible, synced_at) "
            "VALUES (:id, :uid, :at, :d, :s, :p, :title, :plan, :week, :score, "
            "'manual', :notes, false, now())"),
            {"id": new_run_id, "uid": plan["user_id"], "at": when, "d": distance_km,
             "s": duration_seconds, "p": pace, "title": planned_workout_title or None,
             "plan": plan.get("race_name"), "week": week_number or None,
             "score": completion_score or None, "notes": notes or None})
    asyncio.create_task(deliver_run_webhook(new_run_id, plan["user_id"], "run.completed"))
    return f"Run logged: {distance_km} km in {duration_seconds}s on {when.isoformat()}."


@server.tool()
async def update_run(run_id: str, distance_km: float = 0, duration_seconds: int = 0,
                     completed_at_iso: str = "", completion_score: int = 0,
                     notes: str = "", athlete_email: str = "") -> str:
    """Correct a run selected by run_id and athlete_email (Bryce by default).
    Only positive/nonempty fields change. Pace recalculates when distance or
    duration changes. The phone heals its local copy on sync."""
    if distance_km < 0 or duration_seconds < 0:
        raise ValueError("distance and duration cannot be negative")
    sets, params = [], {"id": uuid.UUID(run_id)}
    if distance_km:
        sets.append("distance_km = :d"); params["d"] = distance_km
    if duration_seconds:
        sets.append("duration_seconds = :s"); params["s"] = duration_seconds
    if completed_at_iso:
        sets.append("completed_at = :at")
        params["at"] = dt.datetime.fromisoformat(completed_at_iso.replace("Z", "+00:00"))
    if completion_score:
        sets.append("completion_score = :score"); params["score"] = completion_score
    if notes:
        sets.append("notes = :notes"); params["notes"] = notes
    if not sets:
        return "Nothing to update."
    async with engine.begin() as conn:
        athlete = await _athlete(conn, athlete_email)
        params["uid"] = athlete["id"]
        row = (await conn.execute(text("SELECT distance_km, duration_seconds FROM runs "
                                      "WHERE id = :id AND user_id = :uid FOR UPDATE"), params)).first()
        if row is None:
            raise ValueError("Run not found for this athlete")
        if distance_km or duration_seconds:
            d, duration = distance_km or row[0], duration_seconds or row[1]
            sets.append("avg_pace_sec_per_km = :pace")
            params["pace"] = round(duration / d, 1)
        result = await conn.execute(text(f"UPDATE runs SET {', '.join(sets)} WHERE id = :id AND user_id = :uid"), params)
    if result.rowcount:
        asyncio.create_task(deliver_run_webhook(uuid.UUID(run_id), athlete["id"], "run.updated"))
    return "Run updated."


@server.tool()
async def list_garmin_workouts(athlete_email: str = "", from_date: str = "",
                               through_date: str = "", limit: int = 30) -> str:
    """List Garmin activities with type, date, duration, distance, pace, HR,
    training effect, VO2max, and weather. Filter by athlete email and inclusive
    YYYY-MM-DD dates. Limit 1-100; get_garmin_workout has full splits and zones."""
    first, last = _range(from_date, through_date)
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = await _rows(conn,
            "SELECT id, garmin_activity_id, activity_type, activity_subtype, is_indoor, is_race, "
            "start_time, duration_seconds, distance_km, avg_pace_sec_per_km, "
            "avg_heart_rate, max_heart_rate, training_effect_aerobic, "
            "training_effect_anaerobic, estimated_vo2max, weather_temp_c, "
            "weather_humidity_pct, planned_workout_id "
            "FROM garmin_workouts WHERE user_id = :uid "
            "AND (CAST(:first AS date) IS NULL OR start_time >= CAST(:first AS date)) "
            "AND (CAST(:last AS date) IS NULL OR start_time < CAST(:last AS date) + interval '1 day') "
            "ORDER BY start_time DESC LIMIT :limit",
            {"uid": athlete["id"], "first": first, "last": last, "limit": _limit(limit)})
    return _dump(rows)


@server.tool()
async def get_garmin_workout(workout_id: str, athlete_email: str = "") -> str:
    """Read a Garmin activity by Stride workout ID. Includes all stored splits
    (elevation, HR, cadence), HR zone seconds, training effect, VO2max, weather,
    and matched plan workout ID. Raw provider payload is omitted."""
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = await _rows(conn, "SELECT id, garmin_activity_id, activity_type, activity_subtype, "
            "is_indoor, is_race, start_time, duration_seconds, distance_km, "
            "avg_pace_sec_per_km, avg_heart_rate, max_heart_rate, hr_zones, splits, "
            "training_effect_aerobic, training_effect_anaerobic, estimated_vo2max, "
            "weather_temp_c, weather_humidity_pct, planned_workout_id, synced_at "
            "FROM garmin_workouts WHERE id = :id AND user_id = :uid",
            {"id": uuid.UUID(workout_id), "uid": athlete["id"]})
    if not rows:
        raise ValueError("Garmin workout not found for this athlete")
    return _dump(rows[0])


@server.tool()
async def list_weekly_checkins(athlete_email: str = "", limit: int = 12) -> str:
    """Read weekly coaching check-ins, questions, submitted answers, and status.
    Select the athlete by email. Newest first; limit 1-52."""
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = await _rows(conn, "SELECT id, week_ending, status, invited_at, submitted_at, "
            "questions, answers FROM weekly_checkins WHERE user_id = :uid "
            "ORDER BY week_ending DESC LIMIT :limit",
            {"uid": athlete["id"], "limit": _limit(limit, 52)})
    return _dump(rows)


@server.tool()
async def list_wellness(athlete_email: str = "", from_date: str = "",
                        through_date: str = "", limit: int = 30) -> str:
    """Read subjective wellness entries: sleep, soreness, motivation, stress,
    energy, sore areas, and notes. Select by athlete email and optional inclusive
    YYYY-MM-DD dates. Newest first; limit 1-100."""
    first, last = _range(from_date, through_date)
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = await _rows(conn, "SELECT id, date, entry_method, sleep_quality, soreness, "
            "motivation, stress, energy, soreness_areas, notes, submitted_at "
            "FROM wellness_checkins WHERE user_id = :uid "
            "AND (CAST(:first AS date) IS NULL OR date >= CAST(:first AS date)) "
            "AND (CAST(:last AS date) IS NULL OR date <= CAST(:last AS date)) "
            "ORDER BY date DESC, submitted_at DESC LIMIT :limit",
            {"uid": athlete["id"], "first": first, "last": last, "limit": _limit(limit)})
    return _dump(rows)


@server.tool()
async def list_garmin_daily_metrics(athlete_email: str = "", limit: int = 30) -> str:
    """Read Garmin daily recovery data: HRV, resting HR, sleep, body battery,
    stress, steps, and active minutes. Newest first; limit 1-100."""
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = await _rows(conn, "SELECT date, resting_heart_rate, hrv_overnight, "
            "hrv_baseline_7day, sleep_duration_minutes, sleep_score, sleep_stages, "
            "body_battery_start, body_battery_end, body_battery_low, stress_score, "
            "steps, active_minutes FROM garmin_daily_metrics WHERE user_id = :uid "
            "ORDER BY date DESC LIMIT :limit", {"uid": athlete["id"], "limit": _limit(limit)})
    return _dump(rows)


@server.tool()
async def list_garmin_periodic_metrics(athlete_email: str = "", limit: int = 12) -> str:
    """Read Garmin VO2max trend, training status and load, lactate threshold,
    and race predictors. Newest first; limit 1-52."""
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = await _rows(conn, "SELECT fetched_at, vo2max_running, training_status, "
            "acute_load, chronic_load, acute_chronic_ratio, lactate_threshold_hr, "
            "lactate_threshold_pace_sec_per_km, race_predictors "
            "FROM garmin_periodic_metrics WHERE user_id = :uid "
            "ORDER BY fetched_at DESC LIMIT :limit",
            {"uid": athlete["id"], "limit": _limit(limit, 52)})
    return _dump(rows)


@server.tool()
async def list_plan_history(athlete_email: str = "", limit: int = 20,
                            include_content: bool = False) -> str:
    """Read prior and active training plan versions, source, race metadata,
    change notes, and timestamps. Set include_content=true for complete text of
    each returned version. Select by email; newest first; limit 1-50 for
    metadata or 1-5 when including content."""
    _limit(limit, 5 if include_content else 50)
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = await _rows(conn, "SELECT id, created_at, updated_at, is_active, source, "
            "race_type, race_date, race_name, goal_time, start_date, fitness_level, "
            "change_note, raw_plan_content FROM training_plans WHERE user_id = :uid "
            "ORDER BY updated_at DESC LIMIT :limit",
            {"uid": athlete["id"], "limit": _limit(limit, 50)})
    if not include_content:
        for row in rows:
            row["content_length"] = len(row.pop("raw_plan_content") or "")
    return _dump(rows)


@server.tool()
async def list_plan_adjustments(athlete_email: str = "", limit: int = 30) -> str:
    """Read existing coaching adjustment proposals and their status, summary,
    structured diff, application, or rejection. These are historical records;
    update_plan and replace_in_plan use the phone's active-plan Apply flow."""
    async with engine.connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = await _rows(conn, "SELECT id, training_plan_id, proposed_at, expires_at, "
            "status, trigger_event_id, summary_text, structured_diff, "
            "affected_workout_ids, applied_at, applied_diff_actual, rejection_reason "
            "FROM plan_adjustments WHERE user_id = :uid "
            "ORDER BY proposed_at DESC LIMIT :limit",
            {"uid": athlete["id"], "limit": _limit(limit)})
    return _dump(rows)
