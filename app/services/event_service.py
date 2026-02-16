"""Event service: CRUD, registration, participation matching, leaderboards."""

import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select, func, and_, delete
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.event import Event, EventRegistration
from app.models.run import Run
from app.models.user import User
from app.services.leaderboard_service import _fastest_consecutive_time, DISTANCE_CATEGORIES


# ── CRUD ────────────────────────────────────────────────────────────────────


async def create_event(db: AsyncSession, **kwargs) -> Event:
    """Create a new event."""
    event = Event(**kwargs)
    db.add(event)
    await db.commit()
    await db.refresh(event)
    return event


async def update_event(db: AsyncSession, event_id: uuid.UUID, **kwargs) -> Optional[Event]:
    """Update an existing event."""
    result = await db.execute(select(Event).where(Event.id == event_id))
    event = result.scalar_one_or_none()
    if event is None:
        return None

    for key, value in kwargs.items():
        if hasattr(event, key):
            setattr(event, key, value)

    await db.commit()
    await db.refresh(event)
    return event


async def delete_event(db: AsyncSession, event_id: uuid.UUID) -> bool:
    """Delete an event and its registrations."""
    await db.execute(
        delete(EventRegistration).where(EventRegistration.event_id == event_id)
    )
    result = await db.execute(delete(Event).where(Event.id == event_id))
    await db.commit()
    return result.rowcount > 0


async def list_events(
    db: AsyncSession,
    status_filter: str = "active",
    limit: int = 50,
    offset: int = 0,
) -> list[Event]:
    """List events filtered by status."""
    now = datetime.now(timezone.utc)

    query = select(Event).where(Event.is_active == True)

    if status_filter == "active":
        query = query.where(Event.starts_at <= now, Event.ends_at >= now)
    elif status_filter == "upcoming":
        query = query.where(Event.starts_at > now)
    elif status_filter == "past":
        query = query.where(Event.ends_at < now)

    query = query.order_by(Event.starts_at.desc()).limit(limit).offset(offset)
    result = await db.execute(query)
    return list(result.scalars().all())


async def list_all_events(
    db: AsyncSession,
    status_filter: str = "all",
    limit: int = 50,
    offset: int = 0,
) -> list[Event]:
    """List all events (admin view, includes inactive)."""
    now = datetime.now(timezone.utc)
    query = select(Event)

    if status_filter == "active":
        query = query.where(Event.starts_at <= now, Event.ends_at >= now)
    elif status_filter == "upcoming":
        query = query.where(Event.starts_at > now)
    elif status_filter == "past":
        query = query.where(Event.ends_at < now)

    query = query.order_by(Event.created_at.desc()).limit(limit).offset(offset)
    result = await db.execute(query)
    return list(result.scalars().all())


# ── Registration ────────────────────────────────────────────────────────────


async def register_for_event(
    db: AsyncSession,
    user_id: uuid.UUID,
    event_id: uuid.UUID,
) -> dict:
    """Register a user for an event. Returns status dict."""
    # Check event exists and is open for registration
    result = await db.execute(select(Event).where(Event.id == event_id))
    event = result.scalar_one_or_none()
    if event is None:
        return {"error": "Event not found"}

    now = datetime.now(timezone.utc)

    # Check registration window
    if event.registration_closes_at and now > event.registration_closes_at:
        return {"error": "Registration has closed"}
    if event.registration_opens_at and now < event.registration_opens_at:
        return {"error": "Registration has not opened yet"}

    # Check capacity
    if event.max_participants:
        count_result = await db.execute(
            select(func.count()).select_from(EventRegistration)
            .where(EventRegistration.event_id == event_id)
        )
        current_count = count_result.scalar() or 0
        if current_count >= event.max_participants:
            return {"error": "Event is full"}

    # Upsert registration
    stmt = pg_insert(EventRegistration).values(
        user_id=user_id,
        event_id=event_id,
    ).on_conflict_do_nothing(constraint="uq_user_event")

    result = await db.execute(stmt)
    await db.commit()

    return {"registered": result.rowcount > 0}


async def unregister_from_event(
    db: AsyncSession,
    user_id: uuid.UUID,
    event_id: uuid.UUID,
) -> bool:
    """Unregister a user from an event."""
    result = await db.execute(
        delete(EventRegistration).where(
            EventRegistration.user_id == user_id,
            EventRegistration.event_id == event_id,
        )
    )
    await db.commit()
    return result.rowcount > 0


# ── Participation Matching ──────────────────────────────────────────────────


async def check_event_participation(
    db: AsyncSession,
    user_id: uuid.UUID,
    run_id: uuid.UUID,
    distance_km: float,
    km_splits_json: Optional[str],
    completed_at: datetime,
    is_eligible: bool,
) -> None:
    """After a run is synced, check if it qualifies for any registered events."""
    if not is_eligible:
        return

    result = await db.execute(
        select(EventRegistration, Event)
        .join(Event, EventRegistration.event_id == Event.id)
        .where(
            EventRegistration.user_id == user_id,
            EventRegistration.status == "registered",
            Event.starts_at <= completed_at,
            Event.ends_at >= completed_at,
        )
    )

    for registration, event in result:
        if event.event_type == "race" or event.event_type == "virtual_race":
            # Race: check for fastest time over distance
            target_km = event.distance_km
            if target_km and distance_km >= target_km:
                int_target = int(target_km)
                if km_splits_json:
                    time_seconds = _fastest_consecutive_time(km_splits_json, int_target)
                    if time_seconds is not None:
                        if registration.best_time_seconds is None or time_seconds < registration.best_time_seconds:
                            registration.best_time_seconds = time_seconds
                            registration.best_run_id = run_id

        elif event.event_type == "group_run":
            # Group run: cumulative distance
            registration.total_distance_km = (registration.total_distance_km or 0) + distance_km


# ── Queries ─────────────────────────────────────────────────────────────────


async def get_event_list_for_user(
    db: AsyncSession,
    user_id: uuid.UUID,
    status_filter: str = "active",
    limit: int = 20,
    offset: int = 0,
) -> list[dict]:
    """Get events with user's registration status."""
    now = datetime.now(timezone.utc)

    query = select(Event).where(Event.is_active == True)

    if status_filter == "active":
        query = query.where(Event.starts_at <= now, Event.ends_at >= now)
    elif status_filter == "upcoming":
        query = query.where(Event.starts_at > now)
    elif status_filter == "past":
        query = query.where(Event.ends_at < now)

    query = query.order_by(Event.starts_at.desc()).limit(limit).offset(offset)
    events_result = await db.execute(query)
    events = events_result.scalars().all()

    event_ids = [e.id for e in events]

    # Get user registrations
    registrations = {}
    if event_ids:
        reg_result = await db.execute(
            select(EventRegistration)
            .where(
                EventRegistration.user_id == user_id,
                EventRegistration.event_id.in_(event_ids),
            )
        )
        registrations = {r.event_id: r for r in reg_result.scalars().all()}

    # Get participant counts
    counts = {}
    if event_ids:
        counts_result = await db.execute(
            select(
                EventRegistration.event_id,
                func.count(EventRegistration.id).label("count"),
            )
            .where(EventRegistration.event_id.in_(event_ids))
            .group_by(EventRegistration.event_id)
        )
        counts = {row.event_id: row.count for row in counts_result}

    results = []
    for e in events:
        reg = registrations.get(e.id)
        results.append({
            "id": str(e.id),
            "title": e.title,
            "description": e.description,
            "event_type": e.event_type,
            "distance_category": e.distance_category,
            "distance_km": e.distance_km,
            "starts_at": e.starts_at.isoformat(),
            "ends_at": e.ends_at.isoformat(),
            "registration_opens_at": e.registration_opens_at.isoformat() if e.registration_opens_at else None,
            "registration_closes_at": e.registration_closes_at.isoformat() if e.registration_closes_at else None,
            "max_participants": e.max_participants,
            "sponsor_name": e.sponsor_name,
            "sponsor_logo_url": e.sponsor_logo_url,
            "banner_image_url": e.banner_image_url,
            "primary_color": e.primary_color,
            "accent_color": e.accent_color,
            "is_featured": e.is_featured,
            "participant_count": counts.get(e.id, 0),
            "is_registered": reg is not None,
            "your_best_time_seconds": reg.best_time_seconds if reg else None,
            "your_total_distance_km": reg.total_distance_km if reg else None,
        })

    return results


async def get_event_detail(
    db: AsyncSession,
    event_id: uuid.UUID,
    user_id: uuid.UUID,
    limit: int = 50,
    offset: int = 0,
) -> Optional[dict]:
    """Get event detail with leaderboard."""
    result = await db.execute(select(Event).where(Event.id == event_id))
    event = result.scalar_one_or_none()
    if event is None:
        return None

    is_race = event.event_type in ("race", "virtual_race")

    # Build leaderboard
    if is_race:
        lb_query = (
            select(
                EventRegistration.user_id,
                EventRegistration.best_time_seconds,
                User.display_name,
                User.name,
                User.profile_photo_base64,
            )
            .join(User, EventRegistration.user_id == User.id)
            .where(
                EventRegistration.event_id == event_id,
                EventRegistration.best_time_seconds.isnot(None),
            )
            .order_by(EventRegistration.best_time_seconds.asc())
        )
    else:
        lb_query = (
            select(
                EventRegistration.user_id,
                EventRegistration.total_distance_km,
                User.display_name,
                User.name,
                User.profile_photo_base64,
            )
            .join(User, EventRegistration.user_id == User.id)
            .where(
                EventRegistration.event_id == event_id,
                EventRegistration.total_distance_km > 0,
            )
            .order_by(EventRegistration.total_distance_km.desc())
        )

    # Total participants
    count_result = await db.execute(
        select(func.count())
        .select_from(EventRegistration)
        .where(EventRegistration.event_id == event_id)
    )
    total_participants = count_result.scalar() or 0

    # Paginated leaderboard
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

    # User's registration
    user_reg_result = await db.execute(
        select(EventRegistration).where(
            EventRegistration.event_id == event_id,
            EventRegistration.user_id == user_id,
        )
    )
    user_reg = user_reg_result.scalar_one_or_none()

    return {
        "id": str(event.id),
        "title": event.title,
        "description": event.description,
        "event_type": event.event_type,
        "distance_category": event.distance_category,
        "distance_km": event.distance_km,
        "starts_at": event.starts_at.isoformat(),
        "ends_at": event.ends_at.isoformat(),
        "registration_opens_at": event.registration_opens_at.isoformat() if event.registration_opens_at else None,
        "registration_closes_at": event.registration_closes_at.isoformat() if event.registration_closes_at else None,
        "max_participants": event.max_participants,
        "sponsor_name": event.sponsor_name,
        "sponsor_logo_url": event.sponsor_logo_url,
        "banner_image_url": event.banner_image_url,
        "primary_color": event.primary_color,
        "accent_color": event.accent_color,
        "is_featured": event.is_featured,
        "participant_count": total_participants,
        "is_registered": user_reg is not None,
        "your_best_time_seconds": user_reg.best_time_seconds if user_reg else None,
        "your_total_distance_km": user_reg.total_distance_km if user_reg else None,
        "leaderboard": entries,
    }


async def get_event_registrations(
    db: AsyncSession,
    event_id: uuid.UUID,
    limit: int = 100,
    offset: int = 0,
) -> list[dict]:
    """Get event registrations for admin view."""
    result = await db.execute(
        select(
            EventRegistration,
            User.name,
            User.display_name,
            User.email,
        )
        .join(User, EventRegistration.user_id == User.id)
        .where(EventRegistration.event_id == event_id)
        .order_by(EventRegistration.registered_at.desc())
        .limit(limit)
        .offset(offset)
    )

    registrations = []
    for row in result:
        reg = row[0]
        registrations.append({
            "id": str(reg.id),
            "user_id": str(reg.user_id),
            "name": row.display_name or row.name or "Runner",
            "email": row.email,
            "registered_at": reg.registered_at.isoformat(),
            "status": reg.status,
            "best_time_seconds": reg.best_time_seconds,
            "total_distance_km": reg.total_distance_km,
        })

    return registrations
