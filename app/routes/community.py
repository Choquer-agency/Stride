from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi import HTTPException, Path

from app.database import get_db
from app.models.user import User
from app.models.achievement import AchievementDefinition, UserAchievement
from app.models.streak import UserStreak
from app.models.community_schemas import (
    LeaderboardResponse,
    AchievementDefinitionResponse,
    UserAchievementResponse,
    AchievementMarkNotifiedRequest,
    UserStreakResponse,
    ChallengeResponse,
    ChallengeDetailResponse,
    EventResponse,
    EventDetailResponse,
    EventRegistrationResponse,
)
from app.services.auth_service import get_current_user
from app.services.leaderboard_service import (
    get_yearly_distance_leaderboard,
    get_best_time_leaderboard,
)
from app.services.challenge_service import (
    get_challenges_list,
    get_challenge_detail,
    join_challenge,
)
from app.services.event_service import (
    get_event_list_for_user,
    get_event_detail,
    register_for_event,
    unregister_from_event,
)

router = APIRouter(prefix="/api/community", tags=["community"])


@router.get("/leaderboards/yearly-distance", response_model=LeaderboardResponse)
async def yearly_distance_leaderboard(
    year: int = Query(default=None, description="Year to query (defaults to current)"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    gender: str | None = Query(None, description="Filter by gender: male, female"),
    age_group: str | None = Query(None, description="Filter by age group: 18-29, 30-39, 40-49, 50-59, 60+"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Yearly total distance leaderboard (Bluetooth-verified runs only)."""
    if year is None:
        year = date.today().year

    result = await get_yearly_distance_leaderboard(
        db=db,
        user_id=current_user.id,
        year=year,
        limit=limit,
        offset=offset,
        gender=gender,
        age_group=age_group,
    )
    return LeaderboardResponse(**result)


@router.get("/leaderboards/best-time", response_model=LeaderboardResponse)
async def best_time_leaderboard(
    category: str = Query(..., description="Distance category: 5K, 10K, HM, FM, 50K"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    gender: str | None = Query(None, description="Filter by gender: male, female"),
    age_group: str | None = Query(None, description="Filter by age group: 18-29, 30-39, 40-49, 50-59, 60+"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Best time leaderboard for a distance category (from personal bests)."""
    result = await get_best_time_leaderboard(
        db=db,
        user_id=current_user.id,
        category=category,
        limit=limit,
        offset=offset,
        gender=gender,
        age_group=age_group,
    )
    return LeaderboardResponse(**result)


# ── Achievements ─────────────────────────────────────────────────────────────


@router.get("/achievements", response_model=list[AchievementDefinitionResponse])
async def get_achievements(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get all achievement definitions."""
    result = await db.execute(
        select(AchievementDefinition).order_by(AchievementDefinition.sort_order)
    )
    return [AchievementDefinitionResponse.model_validate(d) for d in result.scalars().all()]


@router.get("/achievements/mine", response_model=list[UserAchievementResponse])
async def get_my_achievements(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get the current user's unlocked achievements with definition details."""
    result = await db.execute(
        select(
            UserAchievement.achievement_id,
            UserAchievement.unlocked_at,
            UserAchievement.run_id,
            AchievementDefinition.category,
            AchievementDefinition.title,
            AchievementDefinition.description,
            AchievementDefinition.icon,
            AchievementDefinition.tier,
        )
        .join(AchievementDefinition, UserAchievement.achievement_id == AchievementDefinition.id)
        .where(UserAchievement.user_id == current_user.id)
        .order_by(UserAchievement.unlocked_at.desc())
    )
    return [
        UserAchievementResponse(
            achievement_id=row.achievement_id,
            unlocked_at=row.unlocked_at,
            run_id=row.run_id,
            category=row.category,
            title=row.title,
            description=row.description,
            icon=row.icon,
            tier=row.tier,
        )
        for row in result
    ]


@router.get("/achievements/unnotified", response_model=list[UserAchievementResponse])
async def get_unnotified_achievements(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get achievements the user hasn't been notified about yet."""
    result = await db.execute(
        select(
            UserAchievement.achievement_id,
            UserAchievement.unlocked_at,
            UserAchievement.run_id,
            AchievementDefinition.category,
            AchievementDefinition.title,
            AchievementDefinition.description,
            AchievementDefinition.icon,
            AchievementDefinition.tier,
        )
        .join(AchievementDefinition, UserAchievement.achievement_id == AchievementDefinition.id)
        .where(
            UserAchievement.user_id == current_user.id,
            UserAchievement.notified == "false",
        )
        .order_by(UserAchievement.unlocked_at.desc())
    )
    return [
        UserAchievementResponse(
            achievement_id=row.achievement_id,
            unlocked_at=row.unlocked_at,
            run_id=row.run_id,
            category=row.category,
            title=row.title,
            description=row.description,
            icon=row.icon,
            tier=row.tier,
        )
        for row in result
    ]


@router.post("/achievements/mark-notified")
async def mark_achievements_notified(
    request: AchievementMarkNotifiedRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Mark achievements as notified (user has seen the celebration)."""
    if request.achievement_ids:
        await db.execute(
            update(UserAchievement)
            .where(
                UserAchievement.user_id == current_user.id,
                UserAchievement.achievement_id.in_(request.achievement_ids),
            )
            .values(notified="true")
        )
        await db.commit()
    return {"marked": len(request.achievement_ids)}


@router.get("/streak", response_model=UserStreakResponse)
async def get_streak(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get the current user's streak info."""
    result = await db.execute(
        select(UserStreak).where(UserStreak.user_id == current_user.id)
    )
    streak = result.scalar_one_or_none()
    if streak is None:
        return UserStreakResponse(current_streak_days=0, longest_streak_days=0)
    return UserStreakResponse(
        current_streak_days=streak.current_streak_days,
        longest_streak_days=streak.longest_streak_days,
        last_run_date=streak.last_run_date,
    )


# ── Challenges ───────────────────────────────────────────────────────────────


@router.get("/challenges", response_model=list[ChallengeResponse])
async def list_challenges(
    status: str = Query("active", description="Filter: active, upcoming, past"),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List challenges filtered by status."""
    results = await get_challenges_list(
        db=db, user_id=current_user.id,
        status_filter=status, limit=limit, offset=offset,
    )
    return [ChallengeResponse(**r) for r in results]


@router.get("/challenges/{challenge_id}", response_model=ChallengeDetailResponse)
async def challenge_detail(
    challenge_id: str = Path(...),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get challenge detail with leaderboard."""
    import uuid as _uuid
    try:
        cid = _uuid.UUID(challenge_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid challenge ID")

    result = await get_challenge_detail(
        db=db, challenge_id=cid, user_id=current_user.id,
        limit=limit, offset=offset,
    )
    if result is None:
        raise HTTPException(status_code=404, detail="Challenge not found")
    return ChallengeDetailResponse(**result)


@router.post("/challenges/{challenge_id}/join")
async def join_challenge_endpoint(
    challenge_id: str = Path(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Join a challenge."""
    import uuid as _uuid
    try:
        cid = _uuid.UUID(challenge_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid challenge ID")

    newly_joined = await join_challenge(db=db, user_id=current_user.id, challenge_id=cid)
    return {"joined": newly_joined}


@router.get("/challenges/history", response_model=list[ChallengeResponse])
async def challenge_history(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get past challenges."""
    results = await get_challenges_list(
        db=db, user_id=current_user.id,
        status_filter="past", limit=limit, offset=offset,
    )
    return [ChallengeResponse(**r) for r in results]


# ── Events ──────────────────────────────────────────────────────────────────


@router.get("/events", response_model=list[EventResponse])
async def list_events(
    status: str = Query("active", description="Filter: active, upcoming, past"),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List events filtered by status."""
    results = await get_event_list_for_user(
        db=db, user_id=current_user.id,
        status_filter=status, limit=limit, offset=offset,
    )
    return [EventResponse(**r) for r in results]


@router.get("/events/{event_id}", response_model=EventDetailResponse)
async def event_detail(
    event_id: str = Path(...),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get event detail with leaderboard."""
    import uuid as _uuid
    try:
        eid = _uuid.UUID(event_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid event ID")

    result = await get_event_detail(
        db=db, event_id=eid, user_id=current_user.id,
        limit=limit, offset=offset,
    )
    if result is None:
        raise HTTPException(status_code=404, detail="Event not found")
    return EventDetailResponse(**result)


@router.post("/events/{event_id}/register", response_model=EventRegistrationResponse)
async def register_event(
    event_id: str = Path(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Register for an event."""
    import uuid as _uuid
    try:
        eid = _uuid.UUID(event_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid event ID")

    result = await register_for_event(db=db, user_id=current_user.id, event_id=eid)
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])
    return EventRegistrationResponse(**result)


@router.delete("/events/{event_id}/register")
async def unregister_event(
    event_id: str = Path(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Unregister from an event."""
    import uuid as _uuid
    try:
        eid = _uuid.UUID(event_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid event ID")

    removed = await unregister_from_event(db=db, user_id=current_user.id, event_id=eid)
    return {"unregistered": removed}
