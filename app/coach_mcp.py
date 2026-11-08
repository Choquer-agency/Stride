"""Athlete-scoped, proposal-only Streamable HTTP MCP server for Grok Bot."""
import contextvars
import hashlib
import json
import re
from datetime import datetime, timedelta, timezone
from uuid import UUID

from mcp.server.mcpserver import MCPServer
from sqlalchemy import func, select

from app.database import async_session
from app.models.coach_access import CoachAccessAudit, CoachAthleteGrant, CoachCredential, ExternalPlanProposal
from app.models.run import Run
from app.models.training_plan import TrainingPlanRecord
from app.models.user import User
from app.services import plan_store, push_service
from app.services.external_plan_service import propose, validate_plan_text

_caller = contextvars.ContextVar("coach_credential_id", default=None)
server = MCPServer(name="stride-coach", version="1.0.0",
    instructions="Read only authorized athletes. Always identify an athlete ID and plan version before proposing. Changes require confirmation on the athlete's phone.")


async def _grant(db, athlete_id: UUID, *, proposal=False):
    credential_id = _caller.get()
    if credential_id is None:
        raise PermissionError("Authentication required")
    credential = await db.get(CoachCredential, credential_id)
    grant = await db.scalar(select(CoachAthleteGrant).where(
        CoachAthleteGrant.credential_id == credential_id,
        CoachAthleteGrant.athlete_id == athlete_id,
        CoachAthleteGrant.revoked_at.is_(None)))
    if credential is None or credential.revoked_at is not None or grant is None:
        raise PermissionError("Athlete not authorized")
    if proposal and not (credential.can_propose and grant.can_propose):
        raise PermissionError("Proposal scope required")
    if not proposal and not (credential.can_read and grant.can_read):
        raise PermissionError("Read scope required")
    db.add(CoachAccessAudit(credential_id=credential_id, athlete_id=athlete_id,
        action="proposal_grant_checked" if proposal else "read_grant_checked"))
    await db.commit()
    return credential


@server.tool()
async def list_athletes() -> list[dict]:
    """List stable IDs and names of athletes explicitly granted to this connector."""
    async with async_session() as db:
        rows = (await db.execute(select(User, CoachAthleteGrant).join(
            CoachAthleteGrant, CoachAthleteGrant.athlete_id == User.id).where(
            CoachAthleteGrant.credential_id == _caller.get(),
            CoachAthleteGrant.revoked_at.is_(None), CoachAthleteGrant.can_read.is_(True)))).all()
        result = []
        for user, grant in rows:
            await _grant(db, user.id)
            result.append({"athlete_id": str(user.id), "name": user.display_name or user.name,
                           "email": user.email, "timezone": user.timezone_name,
                           "can_propose": grant.can_propose})
        return result


@server.tool()
async def read_active_plan(athlete_id: str) -> dict:
    """Read one authorized athlete's active plan and immutable version ID."""
    uid = UUID(athlete_id)
    async with async_session() as db:
        await _grant(db, uid)
        user, plan = await db.get(User, uid), await plan_store.get_active(db, uid)
        if plan is None:
            return {"athlete_id": athlete_id, "plan": None}
        return {"athlete_id": athlete_id, "timezone": user.timezone_name,
                "version": str(plan.id), "source": plan.source,
                "start_date": str(plan.start_date), "race_date": str(plan.race_date),
                "updated_at": plan.updated_at.isoformat(), "units": "km, seconds/km",
                "raw_plan_content": plan.raw_plan_content}


@server.tool()
async def read_planned_workouts(athlete_id: str, from_date: str, through_date: str) -> list[dict]:
    """Read dated plan lines in an inclusive YYYY-MM-DD interval of at most 90 days."""
    from datetime import date
    uid, first, last = UUID(athlete_id), date.fromisoformat(from_date), date.fromisoformat(through_date)
    if not 0 <= (last-first).days <= 90:
        raise ValueError("Date range must be 0–90 days")
    async with async_session() as db:
        await _grant(db, uid)
        user, plan = await db.get(User, uid), await plan_store.get_active(db, uid)
        if not plan or not user.timezone_name:
            raise ValueError("Active plan and configured athlete timezone required")
        return [{**row, "version": str(plan.id), "timezone": user.timezone_name,
                 "units": "km, seconds/km"} for row in validate_plan_text(
                     plan.raw_plan_content, plan.start_date, user.timezone_name)
                 if first.isoformat() <= row["date"] <= last.isoformat()]


@server.tool()
async def read_recent_runs(athlete_id: str, limit: int = 10) -> list[dict]:
    """Read up to 30 recent completed runs, with distance and pace units."""
    uid = UUID(athlete_id)
    if not 1 <= limit <= 30:
        raise ValueError("limit must be 1–30")
    async with async_session() as db:
        await _grant(db, uid)
        rows = (await db.scalars(select(Run).where(Run.user_id == uid)
            .order_by(Run.completed_at.desc()).limit(limit))).all()
        return [{"completed_at": r.completed_at.isoformat(), "distance_km": r.distance_km,
                 "duration_seconds": r.duration_seconds,
                 "avg_pace_seconds_per_km": r.avg_pace_sec_per_km,
                 "timezone": (await db.get(User, uid)).timezone_name,
                 "source": r.data_source} for r in rows]


@server.tool()
async def read_pending_proposals(athlete_id: str) -> list[dict]:
    """Read pending external proposal IDs and reasons for one authorized athlete."""
    uid = UUID(athlete_id)
    async with async_session() as db:
        await _grant(db, uid)
        rows = (await db.scalars(select(ExternalPlanProposal).where(
            ExternalPlanProposal.athlete_id == uid,
            ExternalPlanProposal.status.in_(("proposed", "delivered", "accepted"))))).all()
        return [{"proposal_id": str(r.id), "status": r.status, "reason": r.reason,
                 "expected_version": str(r.expected_plan_id)} for r in rows]


@server.tool()
async def proposal_status(athlete_id: str, proposal_id: str) -> dict:
    """Read proposed, delivered, rejected or applied status; never infer athlete."""
    uid, pid = UUID(athlete_id), UUID(proposal_id)
    async with async_session() as db:
        await _grant(db, uid)
        row = await db.get(ExternalPlanProposal, pid)
        if row is None or row.athlete_id != uid:
            raise LookupError("Proposal not found")
        return {"proposal_id": proposal_id, "status": row.status,
                "before_version": str(row.expected_plan_id),
                "after_version": str(row.applied_plan_id) if row.applied_plan_id else None,
                "delivered_at": row.delivered_at.isoformat() if row.delivered_at else None}


@server.tool()
async def propose_plan_change(athlete_id: str, expected_version: str, new_plan_text: str,
                              reason: str, idempotency_key: str) -> dict:
    """Create a reviewable proposal only. Phone approval is required to apply it."""
    uid, version = UUID(athlete_id), UUID(expected_version)
    async with async_session() as db:
        await _grant(db, uid, proposal=True)
        user = await db.get(User, uid)
        if not user.timezone_name:
            raise ValueError("Athlete timezone must be configured first")
        row = await propose(db, credential_id=_caller.get(), athlete_id=uid,
            expected_plan_id=version, after_text=new_plan_text, reason=reason,
            idempotency_key=idempotency_key, timezone_name=user.timezone_name)
        await db.commit()
        proposal_id = row.id
    # Delivery failure leaves the proposal pending and the plan untouched.
    try:
        async with async_session() as db:
            user = await db.get(User, uid)
            delivered, _ = await push_service.send_push(db, user,
                title="Review a proposed plan change", body=reason[:100],
                deep_link="stride://coach/plan", notification_type="plan_proposal")
            if delivered:
                row = await db.get(ExternalPlanProposal, proposal_id)
                row.status = "delivered"
                row.delivered_at = datetime.now(timezone.utc)
                db.add(CoachAccessAudit(credential_id=_caller.get(), athlete_id=uid,
                    proposal_id=proposal_id, action="delivered", before_plan_id=version))
            await db.commit()
    except Exception:
        delivered = False
    return {"proposal_id": str(proposal_id), "status": "delivered" if delivered else "proposed",
            "approval": "athlete_phone_required", "before_version": str(version),
            "diff": row.diff}


class ProtectedMCP:
    """Bearer API key gate at the HTTP boundary; credentials remain server-side."""
    def __init__(self, path: str = "/mcp"):
        self.inner = server.streamable_http_app(streamable_http_path=path,
            json_response=True, stateless_http=True, host="0.0.0.0")

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.inner(scope, receive, send)
        headers = {k.lower(): v for k, v in scope.get("headers", [])}
        auth = headers.get(b"authorization", b"").decode("ascii", errors="ignore")
        token = auth[7:] if auth.startswith("Bearer ") else ""
        if not re.fullmatch(r"stride_[A-Za-z0-9_-]{32,128}", token):
            return await self._deny(send, 401)
        digest = hashlib.sha256(token.encode()).hexdigest()
        async with async_session() as db:
            # Serialize requests for one key before counting. Without the row
            # lock, parallel workers can all observe the same count and exceed
            # the configured limit.
            cred = await db.scalar(select(CoachCredential).where(
                CoachCredential.token_hash == digest,
                CoachCredential.revoked_at.is_(None)).with_for_update())
            if cred is None:
                return await self._deny(send, 401)
            # DB-backed per-credential request limit works across instances.
            count = await db.scalar(select(func.count(CoachAccessAudit.id)).where(
                CoachAccessAudit.credential_id == cred.id,
                CoachAccessAudit.action == "request",
                CoachAccessAudit.occurred_at > datetime.now(timezone.utc) - timedelta(minutes=1)))
            if count >= 60:
                return await self._deny(send, 429)
            db.add(CoachAccessAudit(credential_id=cred.id, action="request"))
            await db.commit()
        marker = _caller.set(cred.id)
        try:
            await self.inner(scope, receive, send)
        finally:
            _caller.reset(marker)

    @staticmethod
    async def _deny(send, status):
        body = json.dumps({"error": "unauthorized" if status == 401 else "rate_limited"}).encode()
        await send({"type": "http.response.start", "status": status,
                    "headers": [(b"content-type", b"application/json"),
                                (b"www-authenticate", b'Bearer realm="stride-coach"')]
                    if status == 401 else [(b"content-type", b"application/json")]})
        await send({"type": "http.response.body", "body": body})


# Run as a separate service: uvicorn app.coach_mcp:asgi_app --host 0.0.0.0 --port 8001
# Its lifespan is forwarded to the SDK's Streamable HTTP session manager.
asgi_app = ProtectedMCP()
mounted_app = ProtectedMCP(path="/")
