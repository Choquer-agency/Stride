"""STRIDE Coach MCP server — full coaching access for Claude Desktop.

Talks directly to the Neon Postgres database (same bridge Claude Code uses):
- Read/edit the active training plan (phone picks up edits on Plan-tab open)
- Review, log, and correct runs (phone pulls & heals on Plan-tab open)
- Athlete context: profile, check-ins, weekly volumes

Run: venv/bin/python scripts/stride_coach_mcp.py   (stdio, for Claude Desktop)
"""

import datetime
import json
import os
import uuid

from dotenv import load_dotenv

load_dotenv("/Users/brycechoquer/Desktop/Stride v.2/.env")

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from mcp.server.mcpserver import MCPServer

UTC = datetime.timezone.utc

INSTRUCTIONS = """
You are the coaching brain for STRIDE, Bryce's personal AI running-coach app.
You have FULL access: read and edit his training plan, review/log/correct runs,
and give coaching, nutrition, and supplement advice grounded in his real data.

ATHLETE: Bryce Choquer — 31-year-old male, 6'1", ~190 lb. Training for the Maui
Marathon. Trains 80/20 by heart rate; estimated max HR 187.
HR bands: recovery 120–135, easy 130–147, long 135–150, tempo 147–162,
intervals/hills 163–172. Easy pace 6:00–6:30/km currently.

HOME GYM (never prescribe outside it): squat rack + barbell (kg plates),
adjustable dumbbells, flat bench, pull-up bar, landmine, plyo box, medicine
balls (lb — chest-height work only, NO overhead throws/slams: low ceiling),
Concept2 SkiErg (he loves it — warm-ups and finishers).

PLAN FORMAT CONTRACT (the iOS parser is strict — violating this breaks his app):
- Week headers must START a line: "WEEK N [LABEL] (Dates: ...)". Never write
  "week 15" mid-sentence in prose — spell it out ("week fifteen") instead.
- Day lines: "- Monday: <Title> — Total: X km at M:SS–M:SS/km (RPE n)".
- Titles use spaces around dashes ("Easy Run — Total: ..."); never hyphenate
  inside a title without spaces.
- Gym sessions are ONE line: "Gym (PM): <Focus> — <Exercise> <sets>×<reps> @
  <load>; <Exercise> ...". Loads in kg, "kg/hand", lb, or BW.
- Prefer replace_in_plan for small edits; update_plan replaces everything.

SYNC: plan edits and run changes land on Bryce's phone next time he opens the
Plan tab (a "Your coach updated your plan" card for plan edits; runs sync and
self-heal automatically). Always set a clear change_note on plan edits.

COACHING STYLE: honest, evidence-based, direct. Push back when he overreaches
(e.g. running easy days too fast). For nutrition/supplements give practical,
food-first advice; he's a runner building toward marathon volume.
"""

server = MCPServer(
    name="stride-coach",
    instructions=INSTRUCTIONS,
    version="1.0.0",
)

# Bryce is the default athlete; family members are addressable via the
# athlete_email parameter on every tool (see list_athletes).
DEFAULT_ATHLETE_EMAIL = "brycechoquer@me.com"

_engine = None


def engine():
    global _engine
    if _engine is None:
        _engine = create_async_engine(os.environ["DATABASE_URL"])
    return _engine


def _jsonable(row: dict) -> dict:
    out = {}
    for k, v in row.items():
        if isinstance(v, (datetime.datetime, datetime.date)):
            out[k] = v.isoformat()
        elif isinstance(v, uuid.UUID):
            out[k] = str(v)
        else:
            out[k] = v
    return out


async def _athlete(conn, athlete_email: str = ""):
    email = athlete_email or DEFAULT_ATHLETE_EMAIL
    row = (await conn.execute(text(
        "SELECT id, email, display_name, date_of_birth, gender, height_cm "
        "FROM users WHERE lower(email) = lower(:e)"), {"e": email})).mappings().fetchone()
    if row is None:
        raise RuntimeError(f"No athlete with email {email} — use list_athletes")
    return dict(row)


async def _active_plan(conn, athlete_email: str = ""):
    athlete = await _athlete(conn, athlete_email)
    row = (await conn.execute(text(
        "SELECT * FROM training_plans WHERE is_active = true AND user_id = :u "
        "ORDER BY updated_at DESC LIMIT 1"), {"u": athlete["id"]})).mappings().fetchone()
    if row is None:
        raise RuntimeError(f"No active training plan for {athlete['email']}")
    return dict(row)


@server.tool()
async def list_athletes() -> str:
    """Everyone on STRIDE with their active plan. Bryce is the default
    athlete for all tools; pass athlete_email to coach someone else."""
    async with engine().connect() as conn:
        rows = (await conn.execute(text(
            "SELECT u.email, u.display_name, u.created_at, p.race_name, "
            "(SELECT COUNT(*) FROM runs r WHERE r.user_id = u.id) AS runs "
            "FROM users u LEFT JOIN training_plans p "
            "ON p.user_id = u.id AND p.is_active = true "
            "ORDER BY u.created_at"))).mappings().fetchall()
    return json.dumps([_jsonable(dict(r)) for r in rows], indent=2, default=str)


@server.tool()
async def get_coaching_context(athlete_email: str = "") -> str:
    """Load full athlete context: profile, active plan metadata, onboarding
    answers, recent check-ins, and the last 4 weeks of training volume.
    Call this first in any coaching conversation. Defaults to Bryce; pass
    athlete_email for a family member."""
    async with engine().connect() as conn:
        plan = await _active_plan(conn, athlete_email)
        user = await _athlete(conn, athlete_email)
        checkins = (await conn.execute(text(
            "SELECT week_ending, status, answers FROM weekly_checkins "
            "WHERE user_id = :u ORDER BY week_ending DESC LIMIT 4"),
            {"u": plan["user_id"]})).mappings().fetchall()
        volumes = (await conn.execute(text(
            "SELECT date_trunc('week', completed_at)::date AS week, "
            "ROUND(SUM(distance_km)::numeric, 1) AS km, COUNT(*) AS runs "
            "FROM runs WHERE user_id = :u AND completed_at > now() - interval '5 weeks' "
            "GROUP BY 1 ORDER BY 1"), {"u": plan["user_id"]})).mappings().fetchall()

    return json.dumps({
        "athlete": _jsonable(user) if user else None,
        "plan": {k: v for k, v in _jsonable(plan).items() if k != "raw_plan_content"},
        "athlete_profile_from_onboarding": plan.get("athlete_profile"),
        "recent_checkins": [_jsonable(dict(c)) for c in checkins],
        "weekly_volume_last_5_weeks": [_jsonable(dict(v)) for v in volumes],
    }, indent=2, default=str)


@server.tool()
async def get_active_plan(athlete_email: str = "") -> str:
    """The full raw text of the active training plan (every week, every
    workout). This is the exact text the iOS app parses. Defaults to Bryce."""
    async with engine().connect() as conn:
        plan = await _active_plan(conn, athlete_email)
    return plan["raw_plan_content"]


@server.tool()
async def replace_in_plan(find: str, replace: str, change_note: str,
                          athlete_email: str = "") -> str:
    """Make a targeted plan edit: replace an exact text snippet with new text.
    Safest way to edit — the rest of the plan is untouched. `find` must match
    exactly once. Always give a clear change_note (shown to the athlete).
    Respect the plan format contract from the server instructions."""
    async with engine().begin() as conn:
        plan = await _active_plan(conn, athlete_email)
        content = plan["raw_plan_content"]
        count = content.count(find)
        if count == 0:
            return "ERROR: `find` text not found in the plan. Fetch get_active_plan and copy exactly."
        if count > 1:
            return f"ERROR: `find` matches {count} places — include more surrounding context to make it unique."
        await conn.execute(text(
            "UPDATE training_plans SET raw_plan_content = :c, source = 'server_edit', "
            "change_note = :n, updated_at = now() WHERE id = :i"),
            {"c": content.replace(find, replace),
             "n": change_note, "i": plan["id"]})
    return "Plan updated. Bryce gets a 'Your coach updated your plan' card on next Plan-tab open."


@server.tool()
async def update_plan(new_content: str, change_note: str,
                      athlete_email: str = "") -> str:
    """Replace the ENTIRE plan text. Use only for restructures too large for
    replace_in_plan. The content must fully follow the plan format contract
    (week headers starting lines, day-line format, single-line gym sessions)."""
    if "WEEK 1" not in new_content:
        return "ERROR: content has no 'WEEK 1' header — refusing (would break the phone parser)."
    async with engine().begin() as conn:
        plan = await _active_plan(conn, athlete_email)
        await conn.execute(text(
            "UPDATE training_plans SET raw_plan_content = :c, source = 'server_edit', "
            "change_note = :n, updated_at = now() WHERE id = :i"),
            {"c": new_content, "n": change_note, "i": plan["id"]})
    return "Full plan replaced. Bryce gets the update card on next Plan-tab open."


@server.tool()
async def list_runs(limit: int = 30, athlete_email: str = "") -> str:
    """Recent runs, newest first: date, distance, duration, pace, planned
    workout, completion score, notes. June–July 2026 'Stride Half Marathon'
    entries are demo data — ignore them for coaching."""
    async with engine().connect() as conn:
        athlete = await _athlete(conn, athlete_email)
        rows = (await conn.execute(text(
            "SELECT id, completed_at, distance_km, duration_seconds, avg_pace_sec_per_km, "
            "planned_workout_title, planned_distance_km, completion_score, week_number, "
            "plan_name, data_source, notes, feedback_rating "
            "FROM runs WHERE user_id = :u ORDER BY completed_at DESC LIMIT :l"),
            {"u": athlete["id"], "l": limit})).mappings().fetchall()
    return json.dumps([_jsonable(dict(r)) for r in rows], indent=2, default=str)


@server.tool()
async def log_run(
    date_iso: str,
    distance_km: float,
    duration_seconds: int,
    planned_workout_title: str = "",
    week_number: int = 0,
    completion_score: int = 0,
    notes: str = "",
    athlete_email: str = "",
) -> str:
    """Log a run Bryce reports (e.g. tracking failed or he ran watch-only).
    date_iso: completion time like '2026-08-23T18:30:00Z' (or date-only, logs
    at 10:00 local). Pace is computed. The phone syncs it on Plan-tab open and
    checks off the matching planned workout by title + calendar day."""
    when = datetime.datetime.fromisoformat(date_iso.replace("Z", "+00:00"))
    if when.tzinfo is None:
        when = when.replace(hour=17, minute=0, tzinfo=UTC)  # 10:00 PT
    pace = round(duration_seconds / distance_km, 1) if distance_km else 0
    async with engine().begin() as conn:
        plan = await _active_plan(conn, athlete_email)
        await conn.execute(text(
            "INSERT INTO runs (id, user_id, completed_at, distance_km, duration_seconds, "
            "avg_pace_sec_per_km, planned_workout_title, plan_name, week_number, "
            "completion_score, data_source, notes, is_leaderboard_eligible, synced_at) "
            "VALUES (:id, :u, :at, :d, :s, :p, :t, :pn, :w, :cs, 'manual', :n, false, now())"),
            {"id": str(uuid.uuid4()), "u": plan["user_id"], "at": when,
             "d": distance_km, "s": duration_seconds, "p": pace,
             "t": planned_workout_title or None, "pn": plan.get("race_name") or "Maui Marathon",
             "w": week_number or None, "cs": completion_score or None, "n": notes or None})
    return f"Run logged: {distance_km} km in {duration_seconds}s ({pace} s/km) on {when.isoformat()}."


@server.tool()
async def update_run(run_id: str, distance_km: float = 0, duration_seconds: int = 0,
                     completed_at_iso: str = "", completion_score: int = 0,
                     notes: str = "") -> str:
    """Correct an existing run (get the id from list_runs). Only non-zero /
    non-empty fields are changed. Pace recomputes when distance or duration
    change. The phone heals its local copy automatically."""
    sets, params = [], {"id": run_id}
    if distance_km:
        sets.append("distance_km = :d"); params["d"] = distance_km
    if duration_seconds:
        sets.append("duration_seconds = :s"); params["s"] = duration_seconds
    if completed_at_iso:
        when = datetime.datetime.fromisoformat(completed_at_iso.replace("Z", "+00:00"))
        sets.append("completed_at = :at"); params["at"] = when
    if completion_score:
        sets.append("completion_score = :cs"); params["cs"] = completion_score
    if notes:
        sets.append("notes = :n"); params["n"] = notes
    if not sets:
        return "Nothing to update."
    async with engine().begin() as conn:
        if distance_km or duration_seconds:
            row = (await conn.execute(text(
                "SELECT distance_km, duration_seconds FROM runs WHERE id = :id"),
                {"id": run_id})).fetchone()
            if row is None:
                return "ERROR: run not found."
            d = distance_km or row[0]
            s = duration_seconds or row[1]
            sets.append("avg_pace_sec_per_km = :p"); params["p"] = round(s / d, 1) if d else 0
        result = await conn.execute(text(
            f"UPDATE runs SET {', '.join(sets)} WHERE id = :id"), params)
    return "Run updated." if result.rowcount else "ERROR: run not found."


if __name__ == "__main__":
    server.run(transport="stdio")
