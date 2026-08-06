"""
Nutrition + hydration + race fueling routes.

Photo flow:
  1. POST /api/nutrition/parse-photo (multipart) → server runs Claude Vision,
     RETURNS the parsed items but DOES NOT save. iOS shows a confirm screen.
  2. After athlete reviews + edits, POST /api/nutrition/log saves the row.

Text flow: same shape with /api/nutrition/parse-text taking JSON description.

Manual flow: skip parse, directly POST to /api/nutrition/log.
"""

import logging
from datetime import datetime
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.event import Event, EventRegistration
from app.models.race_fueling_plan import RaceFuelingPlan
from app.models.recipe_template import RecipeTemplate
from app.models.user import User
from app.services import nutrition_service, race_fueling_service, storage_service
from app.services.auth_service import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/nutrition", tags=["nutrition"])
hydration_router = APIRouter(prefix="/api/hydration", tags=["nutrition"])


# ── Parse (no save) ─────────────────────────────────────────────────────────

class ParsedMealDTO(BaseModel):
    items: list
    total_calories: int
    total_carbs_g: float
    total_protein_g: float
    total_fat_g: float
    total_fiber_g: float
    confidence: float
    notes: Optional[str] = None
    photo_url: Optional[str] = None


@router.post("/parse-photo", response_model=ParsedMealDTO)
async def parse_photo(
    file: UploadFile = File(...),
    meal_type: Optional[str] = Form(None),
    upload: bool = Form(True),  # If True, also upload to R2 and return photo_url
    current_user: User = Depends(get_current_user),
) -> ParsedMealDTO:
    """Vision-parse a meal photo. Returns parsed items WITHOUT saving."""
    contents = await file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="Empty file")
    if len(contents) > 10 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Image too large (10MB max)")

    parsed = await nutrition_service.parse_photo(contents, hint_meal_type=meal_type)

    photo_url: Optional[str] = None
    if upload:
        try:
            photo_url = storage_service.upload_file(
                contents,
                f"meal_{current_user.id}_{datetime.utcnow().timestamp():.0f}.jpg",
                file.content_type or "image/jpeg",
                folder="nutrition",
            )
        except Exception:
            logger.exception("R2 upload failed for nutrition photo")

    return ParsedMealDTO(**parsed, photo_url=photo_url)


class ParseTextRequest(BaseModel):
    description: str = Field(..., min_length=1, max_length=2000)
    meal_type: Optional[str] = None


@router.post("/parse-text", response_model=ParsedMealDTO)
async def parse_text(
    body: ParseTextRequest,
    current_user: User = Depends(get_current_user),
) -> ParsedMealDTO:
    parsed = await nutrition_service.parse_text(body.description, hint_meal_type=body.meal_type)
    return ParsedMealDTO(**parsed)


# ── Log meal ────────────────────────────────────────────────────────────────

class LogMealRequest(BaseModel):
    meal_type: str
    entry_method: str
    parsed_items: list = Field(default_factory=list)
    total_calories: Optional[int] = None
    total_carbs_g: Optional[float] = None
    total_protein_g: Optional[float] = None
    total_fat_g: Optional[float] = None
    total_fiber_g: Optional[float] = None
    photo_url: Optional[str] = None
    raw_description: Optional[str] = None
    confidence: Optional[float] = None
    edited_after_parse: bool = False
    related_workout_id: Optional[UUID] = None


class LogMealResponse(BaseModel):
    id: UUID
    logged_at: datetime
    meal_type: str


@router.post("/log", response_model=LogMealResponse)
async def log_meal_endpoint(
    body: LogMealRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> LogMealResponse:
    row = await nutrition_service.log_meal(
        db, current_user,
        meal_type=body.meal_type,
        entry_method=body.entry_method,
        parsed_items=body.parsed_items,
        total_calories=body.total_calories,
        total_carbs=body.total_carbs_g,
        total_protein=body.total_protein_g,
        total_fat=body.total_fat_g,
        total_fiber=body.total_fiber_g,
        photo_url=body.photo_url,
        raw_description=body.raw_description,
        confidence=body.confidence,
        edited_after_parse=body.edited_after_parse,
        related_workout_id=body.related_workout_id,
    )
    return LogMealResponse(id=row.id, logged_at=row.logged_at, meal_type=row.meal_type)


# ── Templates ──────────────────────────────────────────────────────────────

class SaveTemplateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    items: list
    total_calories: Optional[int] = None
    total_carbs_g: Optional[float] = None
    total_protein_g: Optional[float] = None
    total_fat_g: Optional[float] = None


class TemplateDTO(BaseModel):
    id: UUID
    name: str
    items: list
    total_calories: Optional[int]
    total_carbs_g: Optional[float]
    total_protein_g: Optional[float]
    total_fat_g: Optional[float]
    use_count: int


@router.post("/save-template", response_model=TemplateDTO)
async def save_template_endpoint(
    body: SaveTemplateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> TemplateDTO:
    row = await nutrition_service.save_template(
        db, current_user,
        name=body.name,
        items=body.items,
        total_calories=body.total_calories,
        total_carbs=body.total_carbs_g,
        total_protein=body.total_protein_g,
        total_fat=body.total_fat_g,
    )
    return _template_to_dto(row)


@router.get("/templates")
async def list_templates_endpoint(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    rows = await nutrition_service.list_templates(db, current_user.id)
    return {"items": [_template_to_dto(r).model_dump() for r in rows]}


class LogFromTemplateRequest(BaseModel):
    template_id: UUID
    meal_type: str


@router.post("/log-template", response_model=LogMealResponse)
async def log_from_template(
    body: LogFromTemplateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> LogMealResponse:
    try:
        row = await nutrition_service.use_template(
            db, current_user, template_id=body.template_id, meal_type=body.meal_type,
        )
    except LookupError:
        raise HTTPException(status_code=404, detail="Template not found")
    return LogMealResponse(id=row.id, logged_at=row.logged_at, meal_type=row.meal_type)


def _template_to_dto(row: RecipeTemplate) -> TemplateDTO:
    return TemplateDTO(
        id=row.id,
        name=row.name,
        items=row.items or [],
        total_calories=row.total_calories,
        total_carbs_g=float(row.total_carbs) if row.total_carbs is not None else None,
        total_protein_g=float(row.total_protein) if row.total_protein is not None else None,
        total_fat_g=float(row.total_fat) if row.total_fat is not None else None,
        use_count=row.use_count or 0,
    )


# ── Today + history ─────────────────────────────────────────────────────────

class TodayResponse(BaseModel):
    totals: dict
    targets: dict
    gap: dict


@router.get("/today", response_model=TodayResponse)
async def get_today(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> TodayResponse:
    totals = await nutrition_service.get_today_totals(db, current_user.id)
    body_weight_kg = float(getattr(current_user, "body_weight_kg", None) or 70.0)
    # planned_workout_type is iOS-side; we approximate from today's planned Run if any.
    # Phase 6 v1 reads from latest Run's denormalized planned_workout_type if today's run exists.
    planned_type = await _today_planned_type(db, current_user.id)
    targets = nutrition_service.compute_daily_targets(
        body_weight_kg=body_weight_kg,
        planned_workout_type=planned_type,
    )
    gap = nutrition_service.compute_today_gap(totals=totals, targets=targets)
    return TodayResponse(totals=totals, targets=targets, gap=gap)


async def _today_planned_type(db: AsyncSession, user_id: UUID) -> Optional[str]:
    """Look at today's Run row (if any) to pick up planned workout type."""
    from datetime import date, datetime, timezone
    from app.models.run import Run
    today = datetime.now(timezone.utc).date()
    start = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)
    end = datetime.combine(today, datetime.max.time(), tzinfo=timezone.utc)
    result = await db.execute(
        select(Run.planned_workout_type).where(
            Run.user_id == user_id,
            Run.completed_at >= start,
            Run.completed_at <= end,
        ).limit(1)
    )
    return result.scalar_one_or_none()


@router.get("/history")
async def get_history(
    days: int = 7,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    if days > 90:
        days = 90
    from datetime import datetime, timedelta, timezone
    from app.models.nutrition_log import NutritionLog
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    result = await db.execute(
        select(NutritionLog).where(
            NutritionLog.user_id == current_user.id,
            NutritionLog.logged_at >= cutoff,
        ).order_by(NutritionLog.logged_at.desc())
    )
    rows = list(result.scalars().all())
    return {
        "items": [
            {
                "id": str(r.id),
                "logged_at": r.logged_at.isoformat() if r.logged_at else None,
                "meal_type": r.meal_type,
                "items": r.parsed_items or [],
                "total_calories": int(r.total_calories or 0),
                "total_carbs_g": float(r.total_carbs or 0),
                "total_protein_g": float(r.total_protein or 0),
                "total_fat_g": float(r.total_fat or 0),
                "photo_url": r.photo_url,
            }
            for r in rows
        ]
    }


# ── Hydration ──────────────────────────────────────────────────────────────

class HydrationAddRequest(BaseModel):
    glasses: int = 1
    electrolyte_servings: int = 0


class HydrationDTO(BaseModel):
    glasses_logged: int
    estimated_ml: int
    electrolyte_servings: int


@hydration_router.post("/add", response_model=HydrationDTO)
async def hydration_add(
    body: HydrationAddRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> HydrationDTO:
    row = await nutrition_service.add_hydration(
        db, current_user,
        glasses=body.glasses,
        electrolyte_servings=body.electrolyte_servings,
    )
    return HydrationDTO(
        glasses_logged=row.glasses_logged,
        estimated_ml=row.estimated_ml,
        electrolyte_servings=row.electrolyte_servings,
    )


# ── Race fueling plan ───────────────────────────────────────────────────────

class RaceFuelingPlanDTO(BaseModel):
    id: UUID
    event_id: UUID
    generated_at: datetime
    three_days_before: dict
    race_morning: dict
    during_race: dict
    post_race: dict
    weather_forecast: Optional[dict]
    course_notes: Optional[str]
    athlete_edits: dict


@router.get("/race-fueling-plan/{event_id}", response_model=RaceFuelingPlanDTO)
async def get_race_fueling_plan(
    event_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> RaceFuelingPlanDTO:
    result = await db.execute(
        select(RaceFuelingPlan)
        .where(
            RaceFuelingPlan.user_id == current_user.id,
            RaceFuelingPlan.event_id == event_id,
        )
        .order_by(RaceFuelingPlan.generated_at.desc())
        .limit(1)
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="Race fueling plan not found")
    return _race_plan_to_dto(row)


@router.post("/race-fueling-plan/{event_id}/regenerate", response_model=RaceFuelingPlanDTO)
async def regenerate_race_fueling_plan(
    event_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> RaceFuelingPlanDTO:
    plan_id = await race_fueling_service.generate_plan(current_user.id, event_id)
    if plan_id is None:
        raise HTTPException(status_code=500, detail="Race fueling plan generation failed")
    row = await db.get(RaceFuelingPlan, plan_id)
    if row is None:
        raise HTTPException(status_code=500, detail="Plan generated but not found")
    return _race_plan_to_dto(row)


def _race_plan_to_dto(row: RaceFuelingPlan) -> RaceFuelingPlanDTO:
    return RaceFuelingPlanDTO(
        id=row.id,
        event_id=row.event_id,
        generated_at=row.generated_at,
        three_days_before=row.three_days_before or {},
        race_morning=row.race_morning or {},
        during_race=row.during_race or {},
        post_race=row.post_race or {},
        weather_forecast=row.weather_forecast,
        course_notes=row.course_notes,
        athlete_edits=row.athlete_edits or {},
    )
