"""Athlete-only phone approval endpoints for externally proposed plan versions."""
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.coach_access import ExternalPlanProposal
from app.models.user import User
from app.services.auth_service import get_current_user
from app.services.external_plan_service import decide, mark_applied

router = APIRouter(prefix="/api/external-plans", tags=["external-plans"])


def _view(row: ExternalPlanProposal) -> dict:
    return {"id": str(row.id), "athlete_id": str(row.athlete_id),
            "expected_plan_id": str(row.expected_plan_id),
            "applied_plan_id": str(row.applied_plan_id) if row.applied_plan_id else None,
            "status": row.status, "reason": row.reason, "diff": row.diff,
            "created_at": row.created_at.isoformat() if row.created_at else None}


@router.get("/pending")
async def pending(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    rows = (await db.scalars(select(ExternalPlanProposal).where(
        ExternalPlanProposal.athlete_id == current_user.id,
        ExternalPlanProposal.status.in_(("proposed", "delivered", "accepted")))
        .order_by(ExternalPlanProposal.created_at))).all()
    return {"items": [_view(row) for row in rows]}


class Decision(BaseModel):
    proposal_id: UUID


class AppliedAck(Decision):
    applied_plan_id: UUID


@router.post("/accept")
async def accept(body: Decision, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    try:
        row = await decide(db, athlete_id=current_user.id, proposal_id=body.proposal_id, accept=True)
    except LookupError:
        raise HTTPException(404, "Proposal not found")
    except ValueError as exc:
        raise HTTPException(409, str(exc))
    return _view(row)


@router.post("/reject")
async def reject(body: Decision, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    try:
        row = await decide(db, athlete_id=current_user.id, proposal_id=body.proposal_id, accept=False)
    except LookupError:
        raise HTTPException(404, "Proposal not found")
    except ValueError as exc:
        raise HTTPException(409, str(exc))
    return _view(row)


@router.post("/applied")
async def applied(body: AppliedAck, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    try:
        row = await mark_applied(db, athlete_id=current_user.id,
                                 proposal_id=body.proposal_id, applied_plan_id=body.applied_plan_id)
    except LookupError:
        raise HTTPException(404, "Proposal not found")
    except ValueError as exc:
        raise HTTPException(409, str(exc))
    return _view(row)
