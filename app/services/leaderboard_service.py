"""Leaderboard service: PB computation, yearly distance, and best-time rankings."""

import json
import re
import uuid
from datetime import datetime, date, timezone
from typing import Optional

from sqlalchemy import select, func, extract, case, and_, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.run import Run
from app.models.personal_best import PersonalBest
from app.models.user import User
from app.services.social_service import log_activity


# Distance categories and their target km for PB computation
DISTANCE_CATEGORIES = {
    "5K": 5,
    "10K": 10,
    "HM": 21,
    "FM": 42,
    "50K": 50,
}

# Age group boundaries
AGE_GROUPS = {
    "18-29": (18, 29),
    "30-39": (30, 39),
    "40-49": (40, 49),
    "50-59": (50, 59),
    "60+": (60, 200),
}


def _parse_time_to_seconds(time_str: str) -> Optional[int]:
    """Parse a time string like '4:32' or '1:23:45' to total seconds."""
    parts = time_str.strip().split(":")
    try:
        if len(parts) == 2:
            return int(parts[0]) * 60 + int(parts[1])
        elif len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    except (ValueError, IndexError):
        pass
    return None


def _fastest_consecutive_time(km_splits_json: str, target_km: int) -> Optional[int]:
    """
    Compute fastest consecutive splits for a given distance from km splits JSON.
    Mirrors the iOS StatsViewModel.fastestConsecutiveTime algorithm.

    Each split has: { "kilometer": Int, "pace": "M:SS", "time": "M:SS" or "H:MM:SS" }
    where 'time' is the cumulative time at that kilometer mark.
    """
    try:
        splits = json.loads(km_splits_json)
    except (json.JSONDecodeError, TypeError):
        return None

    if len(splits) < target_km:
        return None

    # Sort by kilometer
    sorted_splits = sorted(splits, key=lambda s: s.get("kilometer", 0))

    # Convert cumulative times to seconds
    cumulative_seconds = []
    for split in sorted_splits:
        time_str = split.get("time", "")
        secs = _parse_time_to_seconds(time_str)
        if secs is None:
            return None
        cumulative_seconds.append(secs)

    if len(cumulative_seconds) < target_km:
        return None

    best_time = None
    for start_index in range(len(cumulative_seconds) - target_km + 1):
        end_index = start_index + target_km - 1
        if start_index == 0:
            window_time = cumulative_seconds[end_index]
        else:
            window_time = cumulative_seconds[end_index] - cumulative_seconds[start_index - 1]

        if window_time > 0 and (best_time is None or window_time < best_time):
            best_time = window_time

    return best_time


async def compute_personal_bests(
    db: AsyncSession, user_id: uuid.UUID, run_id: uuid.UUID,
    km_splits_json: Optional[str], completed_at: datetime, is_eligible: bool
) -> None:
    """
    After a run is synced, check if it sets any new personal bests.
    Only Bluetooth-verified (leaderboard-eligible) runs count.
    """
    if not is_eligible or not km_splits_json:
        return

    for category, target_km in DISTANCE_CATEGORIES.items():
        time_seconds = _fastest_consecutive_time(km_splits_json, target_km)
        if time_seconds is None:
            continue

        # Upsert: insert if no PB exists, or update if this time is faster
        stmt = pg_insert(PersonalBest).values(
            user_id=user_id,
            distance_category=category,
            time_seconds=time_seconds,
            achieved_at=completed_at,
            run_id=run_id,
        ).on_conflict_do_update(
            constraint="uq_user_distance_category",
            set_={
                "time_seconds": time_seconds,
                "achieved_at": completed_at,
                "run_id": run_id,
            },
            where=PersonalBest.time_seconds > time_seconds,
        )
        result = await db.execute(stmt)
        if result.rowcount > 0:
            await log_activity(
                db, user_id, "pb", run_id,
                {"category": category, "time_seconds": time_seconds},
            )


def _age_from_dob(dob_str: Optional[str], reference_date: date = None) -> Optional[int]:
    """Compute age from a DOB string 'YYYY-MM-DD'."""
    if not dob_str:
        return None
    try:
        dob = datetime.strptime(dob_str, "%Y-%m-%d").date()
        ref = reference_date or date.today()
        age = ref.year - dob.year - ((ref.month, ref.day) < (dob.month, dob.day))
        return age
    except ValueError:
        return None


def _age_group_filter(age_group: str):
    """Build a SQL filter expression for age group based on user DOB."""
    bounds = AGE_GROUPS.get(age_group)
    if not bounds:
        return None

    low, high = bounds
    today = date.today()
    # Born between (today - high years) and (today - low years)
    earliest_dob = today.replace(year=today.year - high - 1)
    latest_dob = today.replace(year=today.year - low)

    return and_(
        User.date_of_birth.isnot(None),
        User.date_of_birth >= earliest_dob.isoformat(),
        User.date_of_birth <= latest_dob.isoformat(),
    )


async def get_yearly_distance_leaderboard(
    db: AsyncSession,
    user_id: uuid.UUID,
    year: int,
    limit: int = 50,
    offset: int = 0,
    gender: Optional[str] = None,
    age_group: Optional[str] = None,
):
    """
    Yearly distance leaderboard: SUM(distance_km) for eligible runs grouped by user.
    Returns dict with entries, your_rank, your_value, total_participants.
    """
    # Base query: sum distance per user for eligible runs in the given year
    base_filters = [
        Run.is_leaderboard_eligible == True,
        extract("year", Run.completed_at) == year,
        User.leaderboard_opt_in == True,
    ]

    if gender:
        base_filters.append(User.gender == gender)
    if age_group:
        age_filter = _age_group_filter(age_group)
        if age_filter is not None:
            base_filters.append(age_filter)

    # Leaderboard query
    leaderboard_q = (
        select(
            User.id.label("user_id"),
            User.display_name,
            User.name,
            User.profile_photo_base64,
            func.sum(Run.distance_km).label("total_distance"),
        )
        .join(Run, Run.user_id == User.id)
        .where(*base_filters)
        .group_by(User.id, User.display_name, User.name, User.profile_photo_base64)
        .order_by(func.sum(Run.distance_km).desc())
    )

    # Total participants
    count_q = (
        select(func.count(func.distinct(Run.user_id)))
        .join(User, Run.user_id == User.id)
        .where(*base_filters)
    )
    total_result = await db.execute(count_q)
    total_participants = total_result.scalar() or 0

    # Paginated entries
    entries_result = await db.execute(leaderboard_q.limit(limit).offset(offset))
    entries = []
    for idx, row in enumerate(entries_result):
        entries.append({
            "rank": offset + idx + 1,
            "user_id": str(row.user_id),
            "display_name": row.display_name or row.name or "Runner",
            "profile_photo_base64": row.profile_photo_base64,
            "value": round(row.total_distance, 1),
        })

    # User's own rank (even if not opted in, they can see their own)
    user_rank = None
    user_value = None

    user_distance_q = (
        select(func.sum(Run.distance_km))
        .where(
            Run.user_id == user_id,
            Run.is_leaderboard_eligible == True,
            extract("year", Run.completed_at) == year,
        )
    )
    user_dist_result = await db.execute(user_distance_q)
    user_total = user_dist_result.scalar()

    if user_total and user_total > 0:
        user_value = round(user_total, 1)
        # Count how many users have more distance
        rank_q = (
            select(func.count(func.distinct(Run.user_id)))
            .join(User, Run.user_id == User.id)
            .where(
                Run.is_leaderboard_eligible == True,
                extract("year", Run.completed_at) == year,
                User.leaderboard_opt_in == True,
            )
            .group_by(Run.user_id)
            .having(func.sum(Run.distance_km) > user_total)
        )
        rank_result = await db.execute(select(func.count()).select_from(rank_q.subquery()))
        users_ahead = rank_result.scalar() or 0
        user_rank = users_ahead + 1

    return {
        "entries": entries,
        "your_rank": user_rank,
        "your_value": user_value,
        "total_participants": total_participants,
    }


async def get_best_time_leaderboard(
    db: AsyncSession,
    user_id: uuid.UUID,
    category: str,
    limit: int = 50,
    offset: int = 0,
    gender: Optional[str] = None,
    age_group: Optional[str] = None,
):
    """
    Best time leaderboard: fastest PB for a distance category.
    Returns dict with entries, your_rank, your_value, total_participants.
    """
    base_filters = [
        PersonalBest.distance_category == category,
        User.leaderboard_opt_in == True,
    ]

    if gender:
        base_filters.append(User.gender == gender)
    if age_group:
        age_filter = _age_group_filter(age_group)
        if age_filter is not None:
            base_filters.append(age_filter)

    # Leaderboard query (fastest = lowest time_seconds)
    leaderboard_q = (
        select(
            User.id.label("user_id"),
            User.display_name,
            User.name,
            User.profile_photo_base64,
            PersonalBest.time_seconds,
        )
        .join(PersonalBest, PersonalBest.user_id == User.id)
        .where(*base_filters)
        .order_by(PersonalBest.time_seconds.asc())
    )

    # Total participants
    count_q = (
        select(func.count())
        .select_from(PersonalBest)
        .join(User, PersonalBest.user_id == User.id)
        .where(*base_filters)
    )
    total_result = await db.execute(count_q)
    total_participants = total_result.scalar() or 0

    # Paginated entries
    entries_result = await db.execute(leaderboard_q.limit(limit).offset(offset))
    entries = []
    for idx, row in enumerate(entries_result):
        entries.append({
            "rank": offset + idx + 1,
            "user_id": str(row.user_id),
            "display_name": row.display_name or row.name or "Runner",
            "profile_photo_base64": row.profile_photo_base64,
            "value": row.time_seconds,
        })

    # User's own rank
    user_rank = None
    user_value = None

    user_pb_q = (
        select(PersonalBest.time_seconds)
        .where(
            PersonalBest.user_id == user_id,
            PersonalBest.distance_category == category,
        )
    )
    user_pb_result = await db.execute(user_pb_q)
    user_time = user_pb_result.scalar()

    if user_time:
        user_value = user_time
        rank_q = (
            select(func.count())
            .select_from(PersonalBest)
            .join(User, PersonalBest.user_id == User.id)
            .where(
                PersonalBest.distance_category == category,
                PersonalBest.time_seconds < user_time,
                User.leaderboard_opt_in == True,
            )
        )
        rank_result = await db.execute(rank_q)
        users_ahead = rank_result.scalar() or 0
        user_rank = users_ahead + 1

    return {
        "entries": entries,
        "your_rank": user_rank,
        "your_value": user_value,
        "total_participants": total_participants,
    }
