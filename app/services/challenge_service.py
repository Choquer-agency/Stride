"""Challenge service: weekly race generation, participation matching, leaderboards."""

import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import select, func, and_
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.challenge import Challenge, ChallengeParticipation
from app.models.run import Run
from app.models.user import User
from app.services.leaderboard_service import _fastest_consecutive_time, DISTANCE_CATEGORIES


# ── Auto-Generate Weekly Challenges ──────────────────────────────────────────


async def auto_generate_weekly_challenges(db: AsyncSession) -> None:
    """
    Create next week's 5K + 10K race challenges if they don't exist.
    Called on server startup. Idempotent via series_id + date check.
    """
    now = datetime.now(timezone.utc)

    # Find next Monday (or today if Monday)
    days_until_monday = (7 - now.weekday()) % 7
    if days_until_monday == 0 and now.hour >= 12:
        # If it's Monday afternoon, generate for next week
        days_until_monday = 7
    elif days_until_monday == 0:
        # Monday morning — generate for this week
        pass

    next_monday = (now + timedelta(days=days_until_monday)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    next_sunday = next_monday + timedelta(days=6, hours=23, minutes=59, seconds=59)

    # Also ensure current week exists
    current_monday = now - timedelta(days=now.weekday())
    current_monday = current_monday.replace(hour=0, minute=0, second=0, microsecond=0)
    current_sunday = current_monday + timedelta(days=6, hours=23, minutes=59, seconds=59)

    week_label_current = current_monday.strftime("%Y-W%W")
    week_label_next = next_monday.strftime("%Y-W%W")

    for week_label, monday, sunday in [
        (week_label_current, current_monday, current_sunday),
        (week_label_next, next_monday, next_sunday),
    ]:
        for category in ["5K", "10K"]:
            series_id = f"weekly_{category.lower()}_{week_label}"

            # Check if already exists
            existing = await db.execute(
                select(Challenge).where(Challenge.series_id == series_id)
            )
            if existing.scalar_one_or_none() is not None:
                continue

            month_name = monday.strftime("%b")
            day_start = monday.day
            day_end = sunday.day
            title = f"This Week's {category} — {month_name} {day_start}–{day_end}"

            challenge = Challenge(
                title=title,
                challenge_type="weekly_race",
                distance_category=category,
                starts_at=monday,
                ends_at=sunday,
                auto_generated=True,
                series_id=series_id,
            )
            db.add(challenge)

    await db.commit()


async def auto_generate_monthly_challenge(db: AsyncSession) -> None:
    """Create the current month's distance challenge if it doesn't exist."""
    now = datetime.now(timezone.utc)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    # Last day of month
    if now.month == 12:
        month_end = month_start.replace(year=now.year + 1, month=1) - timedelta(seconds=1)
    else:
        month_end = month_start.replace(month=now.month + 1) - timedelta(seconds=1)

    series_id = f"monthly_distance_{now.strftime('%Y-%m')}"

    existing = await db.execute(
        select(Challenge).where(Challenge.series_id == series_id)
    )
    if existing.scalar_one_or_none() is not None:
        return

    month_name = now.strftime("%B")
    challenge = Challenge(
        title=f"{month_name} Distance Challenge: Run 100km",
        challenge_type="monthly_distance",
        cumulative_target_km=100.0,
        starts_at=month_start,
        ends_at=month_end,
        auto_generated=True,
        series_id=series_id,
    )
    db.add(challenge)
    await db.commit()


# ── Challenge Participation Matching ─────────────────────────────────────────


async def check_challenge_participation(
    db: AsyncSession,
    user_id: uuid.UUID,
    run_id: uuid.UUID,
    distance_km: float,
    km_splits_json: Optional[str],
    completed_at: datetime,
    is_eligible: bool,
) -> None:
    """
    After a run is synced, check if it qualifies for any active challenges
    the user has joined. Only Bluetooth-verified runs count.
    """
    if not is_eligible:
        return

    # Get all active challenges the user has joined
    result = await db.execute(
        select(ChallengeParticipation, Challenge)
        .join(Challenge, ChallengeParticipation.challenge_id == Challenge.id)
        .where(
            ChallengeParticipation.user_id == user_id,
            Challenge.starts_at <= completed_at,
            Challenge.ends_at >= completed_at,
        )
    )

    for participation, challenge in result:
        if challenge.challenge_type == "weekly_race":
            # Race: check if run covers the distance and has a faster time
            target_km = DISTANCE_CATEGORIES.get(challenge.distance_category)
            if target_km is None or distance_km < target_km:
                continue

            if km_splits_json:
                time_seconds = _fastest_consecutive_time(km_splits_json, target_km)
                if time_seconds is not None:
                    if participation.best_time_seconds is None or time_seconds < participation.best_time_seconds:
                        participation.best_time_seconds = time_seconds
                        participation.best_run_id = run_id

        elif challenge.challenge_type == "monthly_distance":
            # Monthly: add distance
            participation.total_distance_km = (participation.total_distance_km or 0) + distance_km


# ── Challenge Queries ────────────────────────────────────────────────────────


async def get_challenges_list(
    db: AsyncSession,
    user_id: uuid.UUID,
    status_filter: str = "active",
    limit: int = 20,
    offset: int = 0,
) -> list[dict]:
    """Get challenges with user's participation status."""
    now = datetime.now(timezone.utc)

    if status_filter == "active":
        time_filter = and_(Challenge.starts_at <= now, Challenge.ends_at >= now)
    elif status_filter == "upcoming":
        time_filter = Challenge.starts_at > now
    elif status_filter == "past":
        time_filter = Challenge.ends_at < now
    else:
        time_filter = True

    # Get challenges
    challenges_result = await db.execute(
        select(Challenge)
        .where(time_filter)
        .order_by(Challenge.starts_at.desc())
        .limit(limit)
        .offset(offset)
    )
    challenges = challenges_result.scalars().all()

    # Get user's participations for these challenges
    challenge_ids = [c.id for c in challenges]
    if challenge_ids:
        parts_result = await db.execute(
            select(ChallengeParticipation)
            .where(
                ChallengeParticipation.user_id == user_id,
                ChallengeParticipation.challenge_id.in_(challenge_ids),
            )
        )
        participations = {p.challenge_id: p for p in parts_result.scalars().all()}
    else:
        participations = {}

    # Get participant counts
    if challenge_ids:
        counts_result = await db.execute(
            select(
                ChallengeParticipation.challenge_id,
                func.count(ChallengeParticipation.id).label("count"),
            )
            .where(ChallengeParticipation.challenge_id.in_(challenge_ids))
            .group_by(ChallengeParticipation.challenge_id)
        )
        counts = {row.challenge_id: row.count for row in counts_result}
    else:
        counts = {}

    results = []
    for c in challenges:
        part = participations.get(c.id)
        results.append({
            "id": str(c.id),
            "title": c.title,
            "challenge_type": c.challenge_type,
            "distance_category": c.distance_category,
            "cumulative_target_km": c.cumulative_target_km,
            "starts_at": c.starts_at.isoformat(),
            "ends_at": c.ends_at.isoformat(),
            "participant_count": counts.get(c.id, 0),
            "is_joined": part is not None,
            "your_best_time_seconds": part.best_time_seconds if part else None,
            "your_total_distance_km": part.total_distance_km if part else None,
        })

    return results


async def get_challenge_detail(
    db: AsyncSession,
    challenge_id: uuid.UUID,
    user_id: uuid.UUID,
    limit: int = 50,
    offset: int = 0,
) -> Optional[dict]:
    """Get challenge detail with leaderboard."""
    # Get challenge
    result = await db.execute(
        select(Challenge).where(Challenge.id == challenge_id)
    )
    challenge = result.scalar_one_or_none()
    if challenge is None:
        return None

    is_race = challenge.challenge_type == "weekly_race"

    # Build leaderboard
    if is_race:
        # Race: rank by fastest time
        lb_query = (
            select(
                ChallengeParticipation.user_id,
                ChallengeParticipation.best_time_seconds,
                User.display_name,
                User.name,
                User.profile_photo_base64,
            )
            .join(User, ChallengeParticipation.user_id == User.id)
            .where(
                ChallengeParticipation.challenge_id == challenge_id,
                ChallengeParticipation.best_time_seconds.isnot(None),
            )
            .order_by(ChallengeParticipation.best_time_seconds.asc())
        )
    else:
        # Monthly distance: rank by most km
        lb_query = (
            select(
                ChallengeParticipation.user_id,
                ChallengeParticipation.total_distance_km,
                User.display_name,
                User.name,
                User.profile_photo_base64,
            )
            .join(User, ChallengeParticipation.user_id == User.id)
            .where(
                ChallengeParticipation.challenge_id == challenge_id,
                ChallengeParticipation.total_distance_km > 0,
            )
            .order_by(ChallengeParticipation.total_distance_km.desc())
        )

    # Total participants
    count_result = await db.execute(
        select(func.count())
        .select_from(ChallengeParticipation)
        .where(ChallengeParticipation.challenge_id == challenge_id)
    )
    total_participants = count_result.scalar() or 0

    # Paginated leaderboard entries
    lb_result = await db.execute(lb_query.limit(limit).offset(offset))
    entries = []
    for idx, row in enumerate(lb_result):
        value = row.best_time_seconds if is_race else (row.total_distance_km or 0)
        entries.append({
            "rank": offset + idx + 1,
            "user_id": str(row.user_id),
            "display_name": row.display_name or row.name or "Runner",
            "profile_photo_base64": row.profile_photo_base64,
            "value": float(value) if value else 0,
        })

    # User's participation
    user_part_result = await db.execute(
        select(ChallengeParticipation).where(
            ChallengeParticipation.challenge_id == challenge_id,
            ChallengeParticipation.user_id == user_id,
        )
    )
    user_part = user_part_result.scalar_one_or_none()

    return {
        "id": str(challenge.id),
        "title": challenge.title,
        "challenge_type": challenge.challenge_type,
        "distance_category": challenge.distance_category,
        "cumulative_target_km": challenge.cumulative_target_km,
        "starts_at": challenge.starts_at.isoformat(),
        "ends_at": challenge.ends_at.isoformat(),
        "participant_count": total_participants,
        "is_joined": user_part is not None,
        "your_best_time_seconds": user_part.best_time_seconds if user_part else None,
        "your_total_distance_km": user_part.total_distance_km if user_part else None,
        "leaderboard": entries,
    }


async def join_challenge(
    db: AsyncSession,
    user_id: uuid.UUID,
    challenge_id: uuid.UUID,
) -> bool:
    """Join a challenge. Returns True if newly joined, False if already joined."""
    stmt = pg_insert(ChallengeParticipation).values(
        user_id=user_id,
        challenge_id=challenge_id,
    ).on_conflict_do_nothing(constraint="uq_user_challenge")

    result = await db.execute(stmt)
    await db.commit()
    return result.rowcount > 0
