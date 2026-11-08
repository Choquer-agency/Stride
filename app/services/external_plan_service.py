"""Versioned external proposals. Only the athlete's authenticated phone may apply one."""
import difflib
import re
from datetime import date, datetime, timezone
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.coach_access import CoachAccessAudit, CoachCredential, ExternalPlanProposal
from app.models.training_plan import TrainingPlanRecord
from app.models.user import User
from app.services import plan_store

_WEEK = re.compile(r"^\s*WEEK\s+(\d+)\b", re.I)
_DAY = re.compile(r"^[\s\-•*]*?(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\s*(?:[:–\-—―‒]\s*)?", re.I)
_KM = re.compile(r"\b(?:Total:\s*)?(\d+(?:\.\d+)?)\s*km\b", re.I)


def validate_plan_text(content: str, start: date, timezone_name: str) -> list[dict]:
    """Validate the week/day grammar used by iOS PlanParser and derive local dates.

    This deliberately rejects formats we cannot map unambiguously. The phone
    remains the final parser; the server will not silently guess workout dates.
    """
    if not isinstance(content, str) or not 20 <= len(content) <= 200_000:
        raise ValueError("Plan text must be 20–200000 characters")
    try:
        ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError as exc:
        raise ValueError("Invalid athlete timezone") from exc
    monday = start.fromordinal(start.toordinal() - start.weekday())
    weeks, rows, current = set(), [], None
    for line in content.splitlines():
        week = _WEEK.match(line)
        if week:
            number = int(week.group(1))
            if number < 1 or number > 104 or number in weeks or (weeks and number != max(weeks) + 1):
                raise ValueError("Week numbers must be consecutive and unique")
            weeks.add(number)
            current = number
            continue
        day = _DAY.match(line)
        if day:
            if current is None:
                raise ValueError("Workout appears before a WEEK heading")
            weekday = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday").index(day.group(1).lower())
            scheduled = monday.fromordinal(monday.toordinal() + (current - 1) * 7 + weekday)
            if scheduled < start:
                continue  # Same first-week skip rule as PlanParser.
            if not line[day.end():].strip():
                raise ValueError("Workout line has no content")
            rows.append({"date": scheduled.isoformat(), "week": current, "text": line.strip()})
    if not weeks or not rows or min(weeks) != 1:
        raise ValueError("Plan requires WEEK 1 and dated workout lines")
    if any(week not in {row["week"] for row in rows} for week in weeks):
        raise ValueError("Every week must have a dated workout line")
    return rows


def plan_impact(before: list[dict], after: list[dict]) -> dict:
    """Visible review summary; never redistributes or increases load itself."""
    def totals(rows):
        result = {}
        for row in rows:
            match = _KM.search(row["text"])
            if match:
                result[row["week"]] = round(result.get(row["week"], 0) + float(match.group(1)), 2)
        return result
    old, new = totals(before), totals(after)
    return {"workouts_before": len(before), "workouts_after": len(after),
            "weekly_km_changes": [{"week": week, "before_km": old.get(week, 0),
                                   "after_km": new.get(week, 0)}
                                  for week in sorted(old.keys() | new.keys())
                                  if old.get(week, 0) != new.get(week, 0)]}


async def propose(db: AsyncSession, *, credential_id: UUID, athlete_id: UUID,
                  expected_plan_id: UUID, after_text: str, reason: str,
                  idempotency_key: str, timezone_name: str) -> ExternalPlanProposal:
    if not 10 <= len(reason.strip()) <= 1000 or not 8 <= len(idempotency_key) <= 100:
        raise ValueError("Reason or idempotency key is invalid")
    # Serializes reuse of a credential's idempotency keys across workers.
    await db.scalar(select(CoachCredential).where(CoachCredential.id == credential_id).with_for_update())
    existing = await db.scalar(select(ExternalPlanProposal).where(
        ExternalPlanProposal.credential_id == credential_id,
        ExternalPlanProposal.idempotency_key == idempotency_key))
    if existing:
        if existing.athlete_id != athlete_id or existing.expected_plan_id != expected_plan_id or existing.after_text != after_text:
            raise ValueError("Idempotency key reused with different content")
        return existing
    plan = await plan_store.get_active(db, athlete_id)
    if plan is None or plan.id != expected_plan_id:
        raise ValueError("Plan version changed; read it again")
    if plan.start_date is None:
        raise ValueError("Plan has no start date")
    new_rows = validate_plan_text(after_text, plan.start_date, timezone_name)
    old_rows = validate_plan_text(plan.raw_plan_content, plan.start_date, timezone_name)
    today = datetime.now(ZoneInfo(timezone_name)).date().isoformat()
    if [row for row in old_rows if row["date"] < today] != [row for row in new_rows if row["date"] < today]:
        raise ValueError("Past workouts cannot be changed by an external proposal")
    if after_text == plan.raw_plan_content:
        raise ValueError("Proposal makes no change")
    diff = list(difflib.unified_diff(plan.raw_plan_content.splitlines(), after_text.splitlines(),
                                      fromfile="current", tofile="proposed", lineterm=""))
    if len(diff) > 4000:
        raise ValueError("Diff too large to review")
    row = ExternalPlanProposal(credential_id=credential_id, athlete_id=athlete_id,
        expected_plan_id=plan.id, idempotency_key=idempotency_key, reason=reason.strip(),
        before_text=plan.raw_plan_content, after_text=after_text,
        diff={"unified": diff, "timezone": timezone_name,
              "impact": plan_impact(old_rows, new_rows)})
    db.add(row)
    await db.flush()
    db.add(CoachAccessAudit(credential_id=credential_id, athlete_id=athlete_id,
        proposal_id=row.id, action="proposed", before_plan_id=plan.id))
    return row


async def decide(db: AsyncSession, *, athlete_id: UUID, proposal_id: UUID,
                 accept: bool) -> ExternalPlanProposal:
    # Serialize all plan writes for this athlete, including concurrent taps.
    await db.scalar(select(User).where(User.id == athlete_id).with_for_update())
    row = await db.scalar(select(ExternalPlanProposal).where(
        ExternalPlanProposal.id == proposal_id,
        ExternalPlanProposal.athlete_id == athlete_id).with_for_update())
    if row is None:
        raise LookupError("Proposal not found")
    if row.status in (("accepted", "applied") if accept else ("rejected",)):
        return row  # Duplicate phone request is idempotent.
    if row.status not in ("proposed", "delivered"):
        raise ValueError("Proposal already resolved")
    active = await plan_store.get_active(db, athlete_id)
    if active is None or active.id != row.expected_plan_id or active.raw_plan_content != row.before_text:
        raise ValueError("Plan version changed; proposal must be recreated")
    row.decided_at = datetime.now(timezone.utc)
    if accept:
        validate_plan_text(row.after_text, active.start_date, row.diff["timezone"])
        new = await plan_store.save_plan(db, athlete_id, row.after_text, source="server_edit",
            race_type=active.race_type, race_date=active.race_date, race_name=active.race_name,
            goal_time=active.goal_time, custom_distance_km=active.custom_distance_km,
            start_date=active.start_date, fitness_level=active.fitness_level,
            client_plan_id=active.client_plan_id, athlete_profile=active.athlete_profile,
            change_note=row.reason)
        row.applied_plan_id = new.id
        row.status = "accepted"
    else:
        row.status = "rejected"
    db.add(CoachAccessAudit(credential_id=row.credential_id, athlete_id=athlete_id,
        proposal_id=row.id, action=row.status, before_plan_id=active.id,
        after_plan_id=row.applied_plan_id))
    await db.flush()
    return row


async def mark_applied(db: AsyncSession, *, athlete_id: UUID, proposal_id: UUID,
                       applied_plan_id: UUID) -> ExternalPlanProposal:
    row = await db.scalar(select(ExternalPlanProposal).where(
        ExternalPlanProposal.id == proposal_id,
        ExternalPlanProposal.athlete_id == athlete_id).with_for_update())
    if row is None:
        raise LookupError("Proposal not found")
    if row.status == "applied" and row.applied_plan_id == applied_plan_id:
        return row
    if row.status != "accepted" or row.applied_plan_id != applied_plan_id:
        raise ValueError("Accepted plan version does not match")
    active = await plan_store.get_active(db, athlete_id)
    if active is None or active.id != applied_plan_id:
        raise ValueError("Applied plan is no longer active")
    row.status = "applied"
    row.applied_at = datetime.now(timezone.utc)
    db.add(CoachAccessAudit(credential_id=row.credential_id, athlete_id=athlete_id,
        proposal_id=row.id, action="applied", before_plan_id=row.expected_plan_id,
        after_plan_id=applied_plan_id))
    await db.flush()
    return row
