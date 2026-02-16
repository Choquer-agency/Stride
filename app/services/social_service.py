"""Social service: follows, profiles, activity feed, teams."""

import json
import secrets
import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select, func, and_, delete
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.social import Follow, Team, TeamMember, ActivityLog
from app.models.run import Run
from app.models.user import User


# ── Follows ──────────────────────────────────────────────────────────────────


async def follow_user(db: AsyncSession, follower_id: uuid.UUID, following_id: uuid.UUID) -> bool:
    """Follow a user. Returns True if newly followed. Prevents self-follow."""
    if follower_id == following_id:
        return False

    stmt = pg_insert(Follow).values(
        follower_id=follower_id,
        following_id=following_id,
    ).on_conflict_do_nothing(constraint="uq_follower_following")

    result = await db.execute(stmt)
    if result.rowcount > 0:
        await log_activity(db, follower_id, "follow", following_id, {"followed_user_id": str(following_id)})
        await db.commit()
        return True
    return False


async def unfollow_user(db: AsyncSession, follower_id: uuid.UUID, following_id: uuid.UUID) -> bool:
    """Unfollow a user. Returns True if was following."""
    result = await db.execute(
        delete(Follow).where(
            Follow.follower_id == follower_id,
            Follow.following_id == following_id,
        )
    )
    await db.commit()
    return result.rowcount > 0


async def get_followers(
    db: AsyncSession, user_id: uuid.UUID, current_user_id: uuid.UUID,
    limit: int = 20, offset: int = 0,
) -> list[dict]:
    """Get a user's followers with is_following flag for the current user."""
    # Subquery: does current_user follow each follower?
    following_sq = (
        select(Follow.following_id)
        .where(Follow.follower_id == current_user_id)
        .correlate(None)
        .scalar_subquery()
    )

    result = await db.execute(
        select(
            User.id,
            User.display_name,
            User.name,
            User.profile_photo_base64,
            User.bio,
            Follow.created_at,
        )
        .join(Follow, Follow.follower_id == User.id)
        .where(Follow.following_id == user_id)
        .order_by(Follow.created_at.desc())
        .limit(limit)
        .offset(offset)
    )

    # Get set of users current_user follows for is_following flag
    following_result = await db.execute(
        select(Follow.following_id).where(Follow.follower_id == current_user_id)
    )
    following_set = set(following_result.scalars().all())

    return [
        {
            "id": str(row.id),
            "display_name": row.display_name or row.name or "Runner",
            "profile_photo_base64": row.profile_photo_base64,
            "bio": row.bio,
            "is_following": row.id in following_set,
        }
        for row in result
    ]


async def get_following(
    db: AsyncSession, user_id: uuid.UUID, current_user_id: uuid.UUID,
    limit: int = 20, offset: int = 0,
) -> list[dict]:
    """Get users that a user follows, with is_following flag for current user."""
    result = await db.execute(
        select(
            User.id,
            User.display_name,
            User.name,
            User.profile_photo_base64,
            User.bio,
            Follow.created_at,
        )
        .join(Follow, Follow.following_id == User.id)
        .where(Follow.follower_id == user_id)
        .order_by(Follow.created_at.desc())
        .limit(limit)
        .offset(offset)
    )

    # Get set of users current_user follows
    following_result = await db.execute(
        select(Follow.following_id).where(Follow.follower_id == current_user_id)
    )
    following_set = set(following_result.scalars().all())

    return [
        {
            "id": str(row.id),
            "display_name": row.display_name or row.name or "Runner",
            "profile_photo_base64": row.profile_photo_base64,
            "bio": row.bio,
            "is_following": row.id in following_set,
        }
        for row in result
    ]


# ── Profiles & Search ────────────────────────────────────────────────────────


async def get_user_profile(
    db: AsyncSession, user_id: uuid.UUID, current_user_id: uuid.UUID,
) -> Optional[dict]:
    """Get a user's public profile with stats."""
    user_result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = user_result.scalar_one_or_none()
    if user is None:
        return None

    # Follower count
    follower_count_result = await db.execute(
        select(func.count()).select_from(Follow).where(Follow.following_id == user_id)
    )
    follower_count = follower_count_result.scalar() or 0

    # Following count
    following_count_result = await db.execute(
        select(func.count()).select_from(Follow).where(Follow.follower_id == user_id)
    )
    following_count = following_count_result.scalar() or 0

    # Total distance & runs
    stats_result = await db.execute(
        select(
            func.coalesce(func.sum(Run.distance_km), 0.0).label("total_distance_km"),
            func.count(Run.id).label("total_runs"),
        )
        .where(Run.user_id == user_id)
    )
    stats = stats_result.one()

    # Is current user following this user?
    is_following_result = await db.execute(
        select(Follow.id).where(
            Follow.follower_id == current_user_id,
            Follow.following_id == user_id,
        )
    )
    is_following = is_following_result.scalar_one_or_none() is not None

    # Recent activities (last 10)
    activities = await _get_user_activities(db, user_id, limit=10)

    return {
        "id": str(user.id),
        "display_name": user.display_name or user.name or "Runner",
        "profile_photo_base64": user.profile_photo_base64,
        "bio": user.bio,
        "is_following": is_following,
        "follower_count": follower_count,
        "following_count": following_count,
        "total_distance_km": round(float(stats.total_distance_km), 1),
        "total_runs": stats.total_runs,
        "recent_activities": activities,
    }


async def search_users(
    db: AsyncSession, query: str, current_user_id: uuid.UUID, limit: int = 20,
) -> list[dict]:
    """Search users by display_name (ILIKE). Only shows users with completed profiles."""
    if not query or len(query.strip()) < 2:
        return []

    search_pattern = f"%{query.strip()}%"

    result = await db.execute(
        select(User)
        .where(
            User.has_completed_profile == True,
            User.display_name.ilike(search_pattern),
        )
        .order_by(User.display_name)
        .limit(limit)
    )
    users = result.scalars().all()

    # Get set of users current_user follows
    following_result = await db.execute(
        select(Follow.following_id).where(Follow.follower_id == current_user_id)
    )
    following_set = set(following_result.scalars().all())

    return [
        {
            "id": str(u.id),
            "display_name": u.display_name or u.name or "Runner",
            "profile_photo_base64": u.profile_photo_base64,
            "bio": u.bio,
            "is_following": u.id in following_set,
        }
        for u in users
    ]


# ── Activity Feed ─────────────────────────────────────────────────────────────


async def _get_user_activities(
    db: AsyncSession, user_id: uuid.UUID, limit: int = 10,
) -> list[dict]:
    """Get recent activities for a single user."""
    result = await db.execute(
        select(ActivityLog)
        .where(ActivityLog.user_id == user_id)
        .order_by(ActivityLog.created_at.desc())
        .limit(limit)
    )
    activities = result.scalars().all()

    return [
        {
            "id": str(a.id),
            "user_id": str(a.user_id),
            "activity_type": a.activity_type,
            "activity_data": json.loads(a.activity_data) if a.activity_data else {},
            "created_at": a.created_at.isoformat(),
        }
        for a in activities
    ]


async def get_activity_feed(
    db: AsyncSession, user_id: uuid.UUID,
    following_only: bool = True, limit: int = 20, offset: int = 0,
) -> list[dict]:
    """Get activity feed. If following_only, only show followed users' activities."""
    query = (
        select(
            ActivityLog.id,
            ActivityLog.user_id,
            ActivityLog.activity_type,
            ActivityLog.activity_data,
            ActivityLog.created_at,
            User.display_name,
            User.name,
            User.profile_photo_base64,
        )
        .join(User, ActivityLog.user_id == User.id)
    )

    if following_only:
        # Get activities from people the user follows
        followed_sq = (
            select(Follow.following_id)
            .where(Follow.follower_id == user_id)
        )
        query = query.where(ActivityLog.user_id.in_(followed_sq))
    else:
        # Everyone (exclude private — only show users with completed profiles)
        query = query.where(User.has_completed_profile == True)

    query = query.order_by(ActivityLog.created_at.desc()).limit(limit).offset(offset)
    result = await db.execute(query)

    return [
        {
            "id": str(row.id),
            "user_id": str(row.user_id),
            "display_name": row.display_name or row.name or "Runner",
            "profile_photo_base64": row.profile_photo_base64,
            "activity_type": row.activity_type,
            "activity_data": json.loads(row.activity_data) if row.activity_data else {},
            "created_at": row.created_at.isoformat(),
        }
        for row in result
    ]


async def log_activity(
    db: AsyncSession, user_id: uuid.UUID,
    activity_type: str, reference_id: Optional[uuid.UUID],
    activity_data: Optional[dict],
) -> None:
    """Log a social activity."""
    activity = ActivityLog(
        user_id=user_id,
        activity_type=activity_type,
        reference_id=reference_id,
        activity_data=json.dumps(activity_data) if activity_data else None,
    )
    db.add(activity)


# ── Teams ─────────────────────────────────────────────────────────────────────


async def create_team(
    db: AsyncSession, user_id: uuid.UUID, name: str, description: Optional[str],
) -> dict:
    """Create a team. The creator becomes the owner."""
    invite_code = secrets.token_urlsafe(6)[:8].upper()

    team = Team(
        name=name,
        description=description,
        invite_code=invite_code,
        created_by=user_id,
    )
    db.add(team)
    await db.flush()

    member = TeamMember(
        team_id=team.id,
        user_id=user_id,
        role="owner",
    )
    db.add(member)
    await db.commit()

    return {
        "id": str(team.id),
        "name": team.name,
        "description": team.description,
        "photo_url": team.photo_url,
        "invite_code": team.invite_code,
        "member_count": 1,
        "is_member": True,
    }


async def join_team(
    db: AsyncSession, user_id: uuid.UUID, invite_code: str,
) -> Optional[dict]:
    """Join a team by invite code. Returns team info or None if not found."""
    team_result = await db.execute(
        select(Team).where(Team.invite_code == invite_code.upper().strip())
    )
    team = team_result.scalar_one_or_none()
    if team is None:
        return None

    # Check capacity
    count_result = await db.execute(
        select(func.count()).select_from(TeamMember).where(TeamMember.team_id == team.id)
    )
    current_count = count_result.scalar() or 0
    if current_count >= team.max_members:
        return {"error": "Team is full"}

    # Upsert member
    stmt = pg_insert(TeamMember).values(
        team_id=team.id,
        user_id=user_id,
        role="member",
    ).on_conflict_do_nothing(constraint="uq_team_user")

    await db.execute(stmt)
    await db.commit()

    return {
        "id": str(team.id),
        "name": team.name,
        "description": team.description,
        "photo_url": team.photo_url,
        "invite_code": team.invite_code,
        "member_count": current_count + 1,
        "is_member": True,
    }


async def leave_team(
    db: AsyncSession, user_id: uuid.UUID, team_id: uuid.UUID,
) -> bool:
    """Leave a team. If owner leaves, promote next member. Delete if empty."""
    # Check membership
    member_result = await db.execute(
        select(TeamMember).where(
            TeamMember.team_id == team_id,
            TeamMember.user_id == user_id,
        )
    )
    member = member_result.scalar_one_or_none()
    if member is None:
        return False

    was_owner = member.role == "owner"
    await db.delete(member)

    # Check remaining members
    remaining_result = await db.execute(
        select(TeamMember)
        .where(TeamMember.team_id == team_id)
        .order_by(TeamMember.joined_at.asc())
    )
    remaining = remaining_result.scalars().all()

    if not remaining:
        # Delete empty team
        team_result = await db.execute(select(Team).where(Team.id == team_id))
        team = team_result.scalar_one_or_none()
        if team:
            await db.delete(team)
    elif was_owner:
        # Promote the earliest member
        remaining[0].role = "owner"

    await db.commit()
    return True


async def get_team_detail(
    db: AsyncSession, team_id: uuid.UUID, user_id: uuid.UUID,
) -> Optional[dict]:
    """Get team detail with members and distance leaderboard."""
    team_result = await db.execute(select(Team).where(Team.id == team_id))
    team = team_result.scalar_one_or_none()
    if team is None:
        return None

    # Check membership
    membership_result = await db.execute(
        select(TeamMember).where(
            TeamMember.team_id == team_id,
            TeamMember.user_id == user_id,
        )
    )
    is_member = membership_result.scalar_one_or_none() is not None

    # Get members with stats
    members_result = await db.execute(
        select(
            TeamMember.user_id,
            TeamMember.role,
            User.display_name,
            User.name,
            User.profile_photo_base64,
            func.coalesce(func.sum(Run.distance_km), 0.0).label("total_distance_km"),
        )
        .join(User, TeamMember.user_id == User.id)
        .outerjoin(Run, Run.user_id == TeamMember.user_id)
        .where(TeamMember.team_id == team_id)
        .group_by(TeamMember.user_id, TeamMember.role, User.display_name, User.name, User.profile_photo_base64)
        .order_by(func.coalesce(func.sum(Run.distance_km), 0.0).desc())
    )

    members = []
    for row in members_result:
        members.append({
            "user_id": str(row.user_id),
            "display_name": row.display_name or row.name or "Runner",
            "profile_photo_base64": row.profile_photo_base64,
            "role": row.role,
            "total_distance_km": round(float(row.total_distance_km), 1),
        })

    return {
        "id": str(team.id),
        "name": team.name,
        "description": team.description,
        "photo_url": team.photo_url,
        "invite_code": team.invite_code if is_member else None,
        "member_count": len(members),
        "is_member": is_member,
        "members": members,
        "leaderboard": members,  # Already sorted by distance
    }


async def get_user_teams(
    db: AsyncSession, user_id: uuid.UUID,
) -> list[dict]:
    """Get teams the user belongs to."""
    result = await db.execute(
        select(Team, TeamMember.role)
        .join(TeamMember, TeamMember.team_id == Team.id)
        .where(TeamMember.user_id == user_id)
        .order_by(Team.created_at.desc())
    )

    teams = []
    for team, role in result:
        # Member count
        count_result = await db.execute(
            select(func.count()).select_from(TeamMember).where(TeamMember.team_id == team.id)
        )
        member_count = count_result.scalar() or 0

        teams.append({
            "id": str(team.id),
            "name": team.name,
            "description": team.description,
            "photo_url": team.photo_url,
            "invite_code": team.invite_code,
            "member_count": member_count,
            "is_member": True,
        })

    return teams
