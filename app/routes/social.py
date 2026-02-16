import uuid as _uuid

from fastapi import APIRouter, Depends, Query, Path, HTTPException, Body
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.models.community_schemas import (
    UserSearchResult,
    UserProfileResponse,
    ActivityFeedItem,
    TeamResponse,
    TeamDetailResponse,
    TeamCreateRequest,
    TeamJoinRequest,
)
from app.services.auth_service import get_current_user
from app.services.social_service import (
    follow_user,
    unfollow_user,
    get_followers,
    get_following,
    get_user_profile,
    search_users,
    get_activity_feed,
    create_team,
    join_team,
    leave_team,
    get_team_detail,
    get_user_teams,
)

router = APIRouter(prefix="/api/community", tags=["social"])


# ── User Search ──────────────────────────────────────────────────────────────


@router.get("/users/search", response_model=list[UserSearchResult])
async def search_users_endpoint(
    q: str = Query("", min_length=0, description="Search query"),
    limit: int = Query(20, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Search users by display name."""
    results = await search_users(db=db, query=q, current_user_id=current_user.id, limit=limit)
    return [UserSearchResult(**r) for r in results]


# ── User Profile ─────────────────────────────────────────────────────────────


@router.get("/users/{user_id}", response_model=UserProfileResponse)
async def get_user_profile_endpoint(
    user_id: str = Path(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a user's public profile."""
    try:
        uid = _uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid user ID")

    result = await get_user_profile(db=db, user_id=uid, current_user_id=current_user.id)
    if result is None:
        raise HTTPException(status_code=404, detail="User not found")
    return UserProfileResponse(**result)


# ── Follow / Unfollow ────────────────────────────────────────────────────────


@router.post("/users/{user_id}/follow")
async def follow_user_endpoint(
    user_id: str = Path(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Follow a user."""
    try:
        uid = _uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid user ID")

    if uid == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot follow yourself")

    followed = await follow_user(db=db, follower_id=current_user.id, following_id=uid)
    return {"followed": followed}


@router.delete("/users/{user_id}/follow")
async def unfollow_user_endpoint(
    user_id: str = Path(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Unfollow a user."""
    try:
        uid = _uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid user ID")

    unfollowed = await unfollow_user(db=db, follower_id=current_user.id, following_id=uid)
    return {"unfollowed": unfollowed}


# ── Followers / Following ────────────────────────────────────────────────────


@router.get("/users/{user_id}/followers", response_model=list[UserSearchResult])
async def get_followers_endpoint(
    user_id: str = Path(...),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a user's followers."""
    try:
        uid = _uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid user ID")

    results = await get_followers(
        db=db, user_id=uid, current_user_id=current_user.id,
        limit=limit, offset=offset,
    )
    return [UserSearchResult(**r) for r in results]


@router.get("/users/{user_id}/following", response_model=list[UserSearchResult])
async def get_following_endpoint(
    user_id: str = Path(...),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get users that a user follows."""
    try:
        uid = _uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid user ID")

    results = await get_following(
        db=db, user_id=uid, current_user_id=current_user.id,
        limit=limit, offset=offset,
    )
    return [UserSearchResult(**r) for r in results]


# ── Activity Feed ────────────────────────────────────────────────────────────


@router.get("/feed", response_model=list[ActivityFeedItem])
async def get_feed(
    following_only: bool = Query(True, description="Only show followed users"),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get the activity feed."""
    results = await get_activity_feed(
        db=db, user_id=current_user.id,
        following_only=following_only, limit=limit, offset=offset,
    )
    return [ActivityFeedItem(**r) for r in results]


# ── Teams ─────────────────────────────────────────────────────────────────────


@router.post("/teams", response_model=TeamResponse)
async def create_team_endpoint(
    request: TeamCreateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new team."""
    result = await create_team(
        db=db, user_id=current_user.id,
        name=request.name, description=request.description,
    )
    return TeamResponse(**result)


@router.post("/teams/join", response_model=TeamResponse)
async def join_team_endpoint(
    request: TeamJoinRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Join a team by invite code."""
    result = await join_team(db=db, user_id=current_user.id, invite_code=request.invite_code)
    if result is None:
        raise HTTPException(status_code=404, detail="Invalid invite code")
    if "error" in result:
        raise HTTPException(status_code=400, detail=result["error"])
    return TeamResponse(**result)


@router.get("/teams", response_model=list[TeamResponse])
async def get_my_teams(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get teams the current user belongs to."""
    results = await get_user_teams(db=db, user_id=current_user.id)
    return [TeamResponse(**r) for r in results]


@router.get("/teams/{team_id}", response_model=TeamDetailResponse)
async def get_team_detail_endpoint(
    team_id: str = Path(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get team detail with members and leaderboard."""
    try:
        tid = _uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid team ID")

    result = await get_team_detail(db=db, team_id=tid, user_id=current_user.id)
    if result is None:
        raise HTTPException(status_code=404, detail="Team not found")
    return TeamDetailResponse(**result)


@router.delete("/teams/{team_id}/leave")
async def leave_team_endpoint(
    team_id: str = Path(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Leave a team."""
    try:
        tid = _uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid team ID")

    left = await leave_team(db=db, user_id=current_user.id, team_id=tid)
    if not left:
        raise HTTPException(status_code=404, detail="Not a member of this team")
    return {"left": True}
