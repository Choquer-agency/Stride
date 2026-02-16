"""Admin dashboard routes — Jinja2 + HTMX."""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Request, Form, UploadFile, File
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from pathlib import Path

from app.database import get_db
from app.models.user import User
from app.models.event import Event, EventRegistration
from app.services.admin_auth import (
    get_admin_user,
    create_admin_session,
    COOKIE_NAME,
)
from app.services.auth_service import verify_password
from app.services.event_service import (
    create_event,
    update_event,
    delete_event,
    list_all_events,
    get_event_registrations,
)
from app.services.storage_service import upload_file, delete_file

BASE_DIR = Path(__file__).resolve().parent.parent.parent
templates = Jinja2Templates(directory=BASE_DIR / "templates")

router = APIRouter(prefix="/admin", tags=["admin"])


# ── Login ───────────────────────────────────────────────────────────────────


@router.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse("admin/login.html", {"request": request, "error": None})


@router.post("/login", response_class=HTMLResponse)
async def login_submit(
    request: Request,
    email: str = Form(...),
    password: str = Form(...),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    if user is None or not user.is_admin or not user.hashed_password:
        return templates.TemplateResponse(
            "admin/login.html",
            {"request": request, "error": "Invalid credentials or not an admin."},
        )

    if not verify_password(password, user.hashed_password):
        return templates.TemplateResponse(
            "admin/login.html",
            {"request": request, "error": "Invalid credentials or not an admin."},
        )

    token = create_admin_session(str(user.id))
    response = RedirectResponse(url="/admin/", status_code=303)
    response.set_cookie(
        key=COOKIE_NAME,
        value=token,
        httponly=True,
        samesite="lax",
        max_age=86400 * 7,
    )
    return response


@router.get("/logout")
async def logout():
    response = RedirectResponse(url="/admin/login", status_code=303)
    response.delete_cookie(COOKIE_NAME)
    return response


# ── Dashboard ───────────────────────────────────────────────────────────────


@router.get("/", response_class=HTMLResponse)
async def dashboard(
    request: Request,
    admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
):
    now = datetime.now(timezone.utc)

    # Stats
    total_events = (await db.execute(select(func.count()).select_from(Event))).scalar() or 0
    active_events = (await db.execute(
        select(func.count()).select_from(Event)
        .where(Event.starts_at <= now, Event.ends_at >= now, Event.is_active == True)
    )).scalar() or 0
    total_registrations = (await db.execute(
        select(func.count()).select_from(EventRegistration)
    )).scalar() or 0
    upcoming_events = (await db.execute(
        select(func.count()).select_from(Event)
        .where(Event.starts_at > now, Event.is_active == True)
    )).scalar() or 0

    return templates.TemplateResponse("admin/dashboard.html", {
        "request": request,
        "admin": admin,
        "stats": {
            "total_events": total_events,
            "active_events": active_events,
            "total_registrations": total_registrations,
            "upcoming_events": upcoming_events,
        },
    })


# ── Events List ─────────────────────────────────────────────────────────────


@router.get("/events", response_class=HTMLResponse)
async def events_list(
    request: Request,
    status: str = "all",
    admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
):
    events = await list_all_events(db, status_filter=status)

    # Get registration counts
    event_ids = [e.id for e in events]
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

    now_utc = datetime.now(timezone.utc)

    # Check if HTMX request
    if request.headers.get("HX-Request"):
        return templates.TemplateResponse("admin/events/list.html", {
            "request": request,
            "events": events,
            "counts": counts,
            "status": status,
            "admin": admin,
            "now_utc": now_utc,
            "partial": True,
        })

    return templates.TemplateResponse("admin/events/list.html", {
        "request": request,
        "events": events,
        "counts": counts,
        "status": status,
        "admin": admin,
        "now_utc": now_utc,
        "partial": False,
    })


# ── Create Event ────────────────────────────────────────────────────────────


@router.get("/events/new", response_class=HTMLResponse)
async def new_event_form(
    request: Request,
    admin: User = Depends(get_admin_user),
):
    return templates.TemplateResponse("admin/events/form.html", {
        "request": request,
        "admin": admin,
        "event": None,
        "errors": {},
    })


@router.post("/events", response_class=HTMLResponse)
async def create_event_submit(
    request: Request,
    title: str = Form(...),
    description: str = Form(""),
    event_type: str = Form(...),
    distance_category: str = Form(""),
    distance_km: float = Form(0),
    starts_at: str = Form(...),
    ends_at: str = Form(...),
    registration_opens_at: str = Form(""),
    registration_closes_at: str = Form(""),
    max_participants: int = Form(0),
    sponsor_name: str = Form(""),
    primary_color: str = Form("#FF2617"),
    accent_color: str = Form("#1A1A2E"),
    is_featured: bool = Form(False),
    admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
):
    def parse_dt(s: str):
        if not s:
            return None
        try:
            return datetime.fromisoformat(s).replace(tzinfo=timezone.utc)
        except ValueError:
            return None

    event = await create_event(
        db,
        title=title,
        description=description or None,
        event_type=event_type,
        distance_category=distance_category or None,
        distance_km=distance_km or None,
        starts_at=parse_dt(starts_at),
        ends_at=parse_dt(ends_at),
        registration_opens_at=parse_dt(registration_opens_at),
        registration_closes_at=parse_dt(registration_closes_at),
        max_participants=max_participants or None,
        sponsor_name=sponsor_name or None,
        primary_color=primary_color or None,
        accent_color=accent_color or None,
        is_featured=is_featured,
        created_by=admin.id,
    )

    return RedirectResponse(url=f"/admin/events/{event.id}/edit", status_code=303)


# ── Edit Event ──────────────────────────────────────────────────────────────


@router.get("/events/{event_id}/edit", response_class=HTMLResponse)
async def edit_event_form(
    request: Request,
    event_id: str,
    admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Event).where(Event.id == uuid.UUID(event_id)))
    event = result.scalar_one_or_none()
    if event is None:
        return RedirectResponse(url="/admin/events", status_code=303)

    return templates.TemplateResponse("admin/events/form.html", {
        "request": request,
        "admin": admin,
        "event": event,
        "errors": {},
    })


@router.post("/events/{event_id}", response_class=HTMLResponse)
async def update_event_submit(
    request: Request,
    event_id: str,
    title: str = Form(...),
    description: str = Form(""),
    event_type: str = Form(...),
    distance_category: str = Form(""),
    distance_km: float = Form(0),
    starts_at: str = Form(...),
    ends_at: str = Form(...),
    registration_opens_at: str = Form(""),
    registration_closes_at: str = Form(""),
    max_participants: int = Form(0),
    sponsor_name: str = Form(""),
    primary_color: str = Form("#FF2617"),
    accent_color: str = Form("#1A1A2E"),
    is_featured: bool = Form(False),
    is_active: bool = Form(True),
    admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
):
    def parse_dt(s: str):
        if not s:
            return None
        try:
            return datetime.fromisoformat(s).replace(tzinfo=timezone.utc)
        except ValueError:
            return None

    await update_event(
        db,
        event_id=uuid.UUID(event_id),
        title=title,
        description=description or None,
        event_type=event_type,
        distance_category=distance_category or None,
        distance_km=distance_km or None,
        starts_at=parse_dt(starts_at),
        ends_at=parse_dt(ends_at),
        registration_opens_at=parse_dt(registration_opens_at),
        registration_closes_at=parse_dt(registration_closes_at),
        max_participants=max_participants or None,
        sponsor_name=sponsor_name or None,
        primary_color=primary_color or None,
        accent_color=accent_color or None,
        is_featured=is_featured,
        is_active=is_active,
    )

    return RedirectResponse(url=f"/admin/events/{event_id}/edit", status_code=303)


# ── Delete Event ────────────────────────────────────────────────────────────


@router.delete("/events/{event_id}", response_class=HTMLResponse)
async def delete_event_endpoint(
    event_id: str,
    admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
):
    # Delete associated images from R2
    result = await db.execute(select(Event).where(Event.id == uuid.UUID(event_id)))
    event = result.scalar_one_or_none()
    if event:
        if event.sponsor_logo_url:
            try:
                delete_file(event.sponsor_logo_url)
            except Exception:
                pass
        if event.banner_image_url:
            try:
                delete_file(event.banner_image_url)
            except Exception:
                pass

    await delete_event(db, uuid.UUID(event_id))
    return HTMLResponse("")  # HTMX will remove the row


# ── Image Upload ────────────────────────────────────────────────────────────


@router.post("/events/{event_id}/upload-logo", response_class=HTMLResponse)
async def upload_logo(
    request: Request,
    event_id: str,
    file: UploadFile = File(...),
    admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Event).where(Event.id == uuid.UUID(event_id)))
    event = result.scalar_one_or_none()
    if event is None:
        return HTMLResponse("Event not found", status_code=404)

    # Delete old logo
    if event.sponsor_logo_url:
        try:
            delete_file(event.sponsor_logo_url)
        except Exception:
            pass

    file_bytes = await file.read()
    url = upload_file(file_bytes, file.filename or "logo.png", file.content_type or "image/png", folder="events/logos")

    event.sponsor_logo_url = url
    await db.commit()

    return HTMLResponse(f'''
        <div id="logo-preview" class="image-preview">
            <img src="{url}" alt="Sponsor Logo" style="max-height: 80px;">
            <span class="upload-success">Uploaded</span>
        </div>
    ''')


@router.post("/events/{event_id}/upload-banner", response_class=HTMLResponse)
async def upload_banner(
    request: Request,
    event_id: str,
    file: UploadFile = File(...),
    admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Event).where(Event.id == uuid.UUID(event_id)))
    event = result.scalar_one_or_none()
    if event is None:
        return HTMLResponse("Event not found", status_code=404)

    # Delete old banner
    if event.banner_image_url:
        try:
            delete_file(event.banner_image_url)
        except Exception:
            pass

    file_bytes = await file.read()
    url = upload_file(file_bytes, file.filename or "banner.jpg", file.content_type or "image/jpeg", folder="events/banners")

    event.banner_image_url = url
    await db.commit()

    return HTMLResponse(f'''
        <div id="banner-preview" class="image-preview">
            <img src="{url}" alt="Banner" style="max-width: 100%; max-height: 200px;">
            <span class="upload-success">Uploaded</span>
        </div>
    ''')


# ── Event Detail (Registrations + Leaderboard) ─────────────────────────────


@router.get("/events/{event_id}/detail", response_class=HTMLResponse)
async def event_detail(
    request: Request,
    event_id: str,
    admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Event).where(Event.id == uuid.UUID(event_id)))
    event = result.scalar_one_or_none()
    if event is None:
        return RedirectResponse(url="/admin/events", status_code=303)

    count_result = await db.execute(
        select(func.count()).select_from(EventRegistration)
        .where(EventRegistration.event_id == uuid.UUID(event_id))
    )
    registration_count = count_result.scalar() or 0

    return templates.TemplateResponse("admin/events/detail.html", {
        "request": request,
        "admin": admin,
        "event": event,
        "registration_count": registration_count,
    })


@router.get("/events/{event_id}/registrations", response_class=HTMLResponse)
async def event_registrations(
    request: Request,
    event_id: str,
    admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
):
    registrations = await get_event_registrations(db, uuid.UUID(event_id))
    return templates.TemplateResponse("admin/events/_registrations.html", {
        "request": request,
        "registrations": registrations,
    })


@router.get("/events/{event_id}/leaderboard", response_class=HTMLResponse)
async def event_leaderboard(
    request: Request,
    event_id: str,
    admin: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Event).where(Event.id == uuid.UUID(event_id)))
    event = result.scalar_one_or_none()

    from app.services.event_service import get_event_detail
    detail = await get_event_detail(db, uuid.UUID(event_id), admin.id)

    return templates.TemplateResponse("admin/events/_leaderboard.html", {
        "request": request,
        "event": event,
        "leaderboard": detail["leaderboard"] if detail else [],
    })
