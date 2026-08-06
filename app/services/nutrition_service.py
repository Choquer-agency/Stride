"""
Nutrition service — parse photos/text via Claude Vision, log meals, compute
daily targets + gap, and detect Low Energy Availability (LEA) signals.

LEA SAFETY: every targets/gap function in this module is forbidden from
recommending caloric deficit. compute_daily_targets returns a target-floor,
not a ceiling. compute_today_gap reports SHORTFALLS, never surplus warnings.
"""

import json
import logging
import re
import statistics
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.garmin_daily_metric import GarminDailyMetric
from app.models.hydration_log import HydrationLog
from app.models.nutrition_log import EntryMethod, MealType, NutritionLog
from app.models.recipe_template import RecipeTemplate
from app.models.user import User
from app.models.wellness_checkin import WellnessCheckin
from app.services import coaching_models
from app.services.anthropic_client import AnthropicClient
from app.services.prompt_builder import prompt_builder

logger = logging.getLogger(__name__)


# ── Tunable thresholds ──────────────────────────────────────────────────────
# Targets are intentionally floors. Performance + recovery, not weight.

# Bodyweight-relative carb floor (g/kg/day) by workout type
_CARB_FLOOR_REST = 4.0
_CARB_FLOOR_EASY = 6.0
_CARB_FLOOR_QUALITY = 8.0
_CARB_FLOOR_LONG = 9.0

# Protein floor — endurance athletes
_PROTEIN_FLOOR_GKG = 1.6

# Default body weight when not stored on User (kg)
_DEFAULT_BODY_WEIGHT_KG = 70.0

# Gap warning threshold — alert when current < 80% of floor
_GAP_FLOOR_PCT = 0.80

# LEA detection
_LEA_INTAKE_FLOOR_KCAL_PER_KG = 30.0   # below this is dangerously low
_LEA_HRV_DECLINE_PCT = 0.05            # 5%+ HRV drop over the window
_LEA_RHR_RISE_BPM = 4
_LEA_SLEEP_HOURS_FLOOR = 7.0
_LEA_MOTIVATION_FLOOR = 2.5
_LEA_SIGNALS_REQUIRED_FOR_CRITICAL = 3


# ── LLM-driven parsing ──────────────────────────────────────────────────────

async def parse_photo(image_bytes: bytes, *, hint_meal_type: Optional[str] = None) -> dict:
    """
    Send the photo to Claude vision via the existing analyze_image helper.
    Returns a parsed-meal dict ready for the iOS confirm screen. ALWAYS returns
    a valid structure — on parse failure, returns an empty meal with
    confidence=0 and a notes message.
    """
    client = AnthropicClient()
    system_prompt = prompt_builder.get_nutrition_parse_vision_prompt()
    prompt_with_hint = system_prompt
    if hint_meal_type:
        prompt_with_hint += f"\n\nMeal type hint: {hint_meal_type}\n"

    try:
        raw = await client.analyze_image(
            image_bytes,
            prompt_with_hint,
            model=coaching_models.NUTRITION_PARSE_MODEL,
            name="nutrition-parse-photo",
        )
    except Exception as exc:
        logger.exception("Vision parse failed")
        return _empty_parsed(reason=f"Vision call failed: {type(exc).__name__}")

    return _safe_parse_json(raw)


async def parse_text(description: str, *, hint_meal_type: Optional[str] = None) -> dict:
    """Parse a natural-language meal description via Sonnet (no vision)."""
    client = AnthropicClient()
    system_prompt = prompt_builder.get_nutrition_parse_vision_prompt()
    user_prompt = f"Text description of the meal:\n{description}"
    if hint_meal_type:
        user_prompt = f"Meal type: {hint_meal_type}\n\n" + user_prompt

    try:
        raw = await client.generate_plan(
            system_prompt,
            user_prompt,
            name="nutrition-parse-text",
            model=coaching_models.NUTRITION_PARSE_MODEL,
        )
    except Exception as exc:
        logger.exception("Text parse failed")
        return _empty_parsed(reason=f"Text parse call failed: {type(exc).__name__}")

    return _safe_parse_json(raw)


def _safe_parse_json(raw: str) -> dict:
    """Tolerant of model output wrapping JSON in code fences or trailing prose."""
    if not raw:
        return _empty_parsed(reason="empty model output")

    # Strip ```json ... ``` fences if present
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        # Drop opening fence + close fence
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
        cleaned = re.sub(r"\s*```\s*$", "", cleaned)

    # Find first { ... last } block
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start == -1 or end == -1:
        return _empty_parsed(reason="no JSON object in output")

    blob = cleaned[start:end + 1]
    try:
        parsed = json.loads(blob)
    except json.JSONDecodeError:
        return _empty_parsed(reason="invalid JSON")

    if not isinstance(parsed, dict):
        return _empty_parsed(reason="JSON not an object")

    # Normalize fields
    return {
        "items": parsed.get("items") or [],
        "total_calories": int(parsed.get("total_calories") or 0),
        "total_carbs_g": float(parsed.get("total_carbs_g") or 0),
        "total_protein_g": float(parsed.get("total_protein_g") or 0),
        "total_fat_g": float(parsed.get("total_fat_g") or 0),
        "total_fiber_g": float(parsed.get("total_fiber_g") or 0),
        "confidence": float(parsed.get("confidence") or 0),
        "notes": parsed.get("notes"),
    }


def _empty_parsed(*, reason: str) -> dict:
    return {
        "items": [],
        "total_calories": 0,
        "total_carbs_g": 0.0,
        "total_protein_g": 0.0,
        "total_fat_g": 0.0,
        "total_fiber_g": 0.0,
        "confidence": 0.0,
        "notes": reason,
    }


# ── Logging + retrieval ─────────────────────────────────────────────────────

async def log_meal(
    db: AsyncSession,
    user: User,
    *,
    meal_type: str,
    entry_method: str,
    parsed_items: list,
    total_calories: Optional[int],
    total_carbs: Optional[float],
    total_protein: Optional[float],
    total_fat: Optional[float],
    total_fiber: Optional[float] = None,
    photo_url: Optional[str] = None,
    raw_description: Optional[str] = None,
    confidence: Optional[float] = None,
    edited_after_parse: bool = False,
    related_workout_id: Optional[UUID] = None,
) -> NutritionLog:
    row = NutritionLog(
        user_id=user.id,
        meal_type=meal_type,
        entry_method=entry_method,
        photo_url=photo_url,
        raw_description=raw_description,
        parsed_items=parsed_items or [],
        total_calories=total_calories,
        total_carbs=Decimal(str(total_carbs)) if total_carbs is not None else None,
        total_protein=Decimal(str(total_protein)) if total_protein is not None else None,
        total_fat=Decimal(str(total_fat)) if total_fat is not None else None,
        total_fiber=Decimal(str(total_fiber)) if total_fiber is not None else None,
        confidence=confidence,
        edited_after_parse=edited_after_parse,
        related_workout_id=related_workout_id,
    )
    db.add(row)
    await db.flush()
    logger.info("Meal logged: user=%s meal=%s cal=%s carbs=%s", user.id, meal_type, total_calories, total_carbs)
    return row


async def get_today_totals(db: AsyncSession, user_id: UUID, today: Optional[date] = None) -> dict:
    today = today or datetime.now(timezone.utc).date()
    start = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)
    end = datetime.combine(today, datetime.max.time(), tzinfo=timezone.utc)
    result = await db.execute(
        select(NutritionLog).where(
            NutritionLog.user_id == user_id,
            NutritionLog.logged_at >= start,
            NutritionLog.logged_at <= end,
        ).order_by(NutritionLog.logged_at)
    )
    rows = list(result.scalars().all())
    cal = sum(int(r.total_calories or 0) for r in rows)
    carbs = sum(float(r.total_carbs or 0) for r in rows)
    protein = sum(float(r.total_protein or 0) for r in rows)
    fat = sum(float(r.total_fat or 0) for r in rows)
    return {
        "calories": cal,
        "carbs_g": round(carbs, 1),
        "protein_g": round(protein, 1),
        "fat_g": round(fat, 1),
        "meal_count": len(rows),
        "meals": [_log_to_dict(r) for r in rows],
    }


def _log_to_dict(r: NutritionLog) -> dict:
    return {
        "id": str(r.id),
        "logged_at": r.logged_at.isoformat() if r.logged_at else None,
        "meal_type": r.meal_type,
        "items": r.parsed_items or [],
        "total_calories": int(r.total_calories or 0),
        "total_carbs_g": float(r.total_carbs or 0),
        "total_protein_g": float(r.total_protein or 0),
        "total_fat_g": float(r.total_fat or 0),
    }


# ── Targets + gap ───────────────────────────────────────────────────────────

def compute_daily_targets(*, body_weight_kg: float, planned_workout_type: Optional[str]) -> dict:
    """
    Returns target FLOORS for today's macros. These are the minimums to hit
    for the planned workload — not caps, never deficits.
    """
    pt = (planned_workout_type or "").lower()
    if any(k in pt for k in ("interval", "tempo", "threshold", "vo2", "speed")):
        carb_floor_gkg = _CARB_FLOOR_QUALITY
    elif "long" in pt:
        carb_floor_gkg = _CARB_FLOOR_LONG
    elif any(k in pt for k in ("easy", "recovery")):
        carb_floor_gkg = _CARB_FLOOR_EASY
    else:
        carb_floor_gkg = _CARB_FLOOR_REST

    carbs_floor = round(body_weight_kg * carb_floor_gkg, 0)
    protein_floor = round(body_weight_kg * _PROTEIN_FLOOR_GKG, 0)
    # Fat: minimum 0.8 g/kg as a baseline for hormonal health — not capped.
    fat_floor = round(body_weight_kg * 0.8, 0)
    # Calorie floor derived; this is a SAFETY floor only (LEA).
    cal_floor = int(round(_LEA_INTAKE_FLOOR_KCAL_PER_KG * body_weight_kg))

    return {
        "carbs_g_floor": carbs_floor,
        "protein_g_floor": protein_floor,
        "fat_g_floor": fat_floor,
        "calorie_floor_lea_safety": cal_floor,
        "carb_floor_gkg": carb_floor_gkg,
        "body_weight_kg_used": body_weight_kg,
        "planned_workout_type": planned_workout_type,
    }


def compute_today_gap(*, totals: dict, targets: dict) -> dict:
    """
    Reports SHORTFALLS only. If athlete is over a floor, that's fine —
    we don't recommend cutting back. LEA safety drives this design.
    """
    out = {"shortfalls": {}, "any_shortfall": False}
    if totals.get("carbs_g", 0) < targets["carbs_g_floor"] * _GAP_FLOOR_PCT:
        out["shortfalls"]["carbs_g"] = {
            "current": totals.get("carbs_g", 0),
            "floor": targets["carbs_g_floor"],
            "deficit_g": round(targets["carbs_g_floor"] - totals.get("carbs_g", 0), 1),
        }
        out["any_shortfall"] = True
    if totals.get("protein_g", 0) < targets["protein_g_floor"] * _GAP_FLOOR_PCT:
        out["shortfalls"]["protein_g"] = {
            "current": totals.get("protein_g", 0),
            "floor": targets["protein_g_floor"],
            "deficit_g": round(targets["protein_g_floor"] - totals.get("protein_g", 0), 1),
        }
        out["any_shortfall"] = True
    if totals.get("calories", 0) < targets["calorie_floor_lea_safety"]:
        out["shortfalls"]["calories"] = {
            "current": totals.get("calories", 0),
            "floor": targets["calorie_floor_lea_safety"],
            "deficit_kcal": targets["calorie_floor_lea_safety"] - totals.get("calories", 0),
            "lea_floor": True,
        }
        out["any_shortfall"] = True
    return out


# ── Hydration ───────────────────────────────────────────────────────────────

async def add_hydration(
    db: AsyncSession,
    user: User,
    *,
    glasses: int = 1,
    electrolyte_servings: int = 0,
    today: Optional[date] = None,
    glass_ml: int = 240,
) -> HydrationLog:
    today = today or datetime.now(timezone.utc).date()
    stmt = pg_insert(HydrationLog).values(
        user_id=user.id,
        date=today,
        glasses_logged=glasses,
        estimated_ml=glasses * glass_ml,
        electrolyte_servings=electrolyte_servings,
    ).on_conflict_do_update(
        constraint="uq_hydration_user_date",
        set_={
            "glasses_logged": HydrationLog.glasses_logged + glasses,
            "estimated_ml": HydrationLog.estimated_ml + glasses * glass_ml,
            "electrolyte_servings": HydrationLog.electrolyte_servings + electrolyte_servings,
            "updated_at": datetime.now(timezone.utc),
        },
    ).returning(HydrationLog)
    result = await db.execute(stmt)
    return result.scalar_one()


# ── Recipe templates ────────────────────────────────────────────────────────

async def save_template(
    db: AsyncSession,
    user: User,
    *,
    name: str,
    items: list,
    total_calories: Optional[int],
    total_carbs: Optional[float],
    total_protein: Optional[float],
    total_fat: Optional[float],
) -> RecipeTemplate:
    row = RecipeTemplate(
        user_id=user.id,
        name=name,
        items=items or [],
        total_calories=total_calories,
        total_carbs=Decimal(str(total_carbs)) if total_carbs is not None else None,
        total_protein=Decimal(str(total_protein)) if total_protein is not None else None,
        total_fat=Decimal(str(total_fat)) if total_fat is not None else None,
    )
    db.add(row)
    await db.flush()
    return row


async def list_templates(db: AsyncSession, user_id: UUID, limit: int = 30) -> list[RecipeTemplate]:
    result = await db.execute(
        select(RecipeTemplate)
        .where(RecipeTemplate.user_id == user_id)
        .order_by(desc(RecipeTemplate.use_count), desc(RecipeTemplate.last_used_at))
        .limit(limit)
    )
    return list(result.scalars().all())


async def use_template(
    db: AsyncSession,
    user: User,
    *,
    template_id: UUID,
    meal_type: str,
) -> NutritionLog:
    template = await db.get(RecipeTemplate, template_id)
    if template is None or template.user_id != user.id:
        raise LookupError(f"RecipeTemplate {template_id} not found")
    log = await log_meal(
        db, user,
        meal_type=meal_type,
        entry_method=EntryMethod.TEMPLATE.value,
        parsed_items=template.items or [],
        total_calories=template.total_calories,
        total_carbs=float(template.total_carbs) if template.total_carbs is not None else None,
        total_protein=float(template.total_protein) if template.total_protein is not None else None,
        total_fat=float(template.total_fat) if template.total_fat is not None else None,
    )
    template.use_count = (template.use_count or 0) + 1
    template.last_used_at = datetime.now(timezone.utc)
    db.add(template)
    return log


# ── LEA detection ───────────────────────────────────────────────────────────

async def check_lea_signals(db: AsyncSession, user: User, *, window_days: int = 14) -> dict:
    """
    Phase 6 implementation of the LEA detector. Returns a signal-counting dict.
    Phase 3's anomaly_engine._check_lea_pattern wraps this and raises a
    critical-component AnomalyFlag when ≥3 signals are present.

    Signals (each is a bool):
      - chronic_low_intake: avg daily kcal/kg < 30
      - hrv_declining_with_load: HRV trending down ≥5% across window
      - rhr_rising: avg RHR vs first half of window up ≥4 bpm
      - sleep_short: avg sleep hours < 7 across window
      - mood_low: avg motivation < 2.5 (Phase 4 wellness)
      - missed_periods: TODO — explicit flag from athlete profile (out of v2 scope)
    """
    today = datetime.now(timezone.utc).date()
    start = today - timedelta(days=window_days)

    body_weight_kg = float(getattr(user, "body_weight_kg", _DEFAULT_BODY_WEIGHT_KG) or _DEFAULT_BODY_WEIGHT_KG)

    # 1) Chronic low intake
    intake_q = await db.execute(
        select(NutritionLog.logged_at, NutritionLog.total_calories).where(
            NutritionLog.user_id == user.id,
            NutritionLog.logged_at >= datetime.combine(start, datetime.min.time(), tzinfo=timezone.utc),
        )
    )
    by_date: dict[date, int] = {}
    for logged_at, cal in intake_q.all():
        if logged_at and cal:
            by_date[logged_at.date()] = by_date.get(logged_at.date(), 0) + int(cal)
    daily_kcal_per_kg = [v / body_weight_kg for v in by_date.values()]
    chronic_low_intake = (
        len(daily_kcal_per_kg) >= max(3, window_days // 3)
        and statistics.mean(daily_kcal_per_kg) < _LEA_INTAKE_FLOOR_KCAL_PER_KG
    )

    # 2/3) Recovery metrics
    metrics_q = await db.execute(
        select(GarminDailyMetric).where(
            GarminDailyMetric.user_id == user.id,
            GarminDailyMetric.date >= start,
        ).order_by(GarminDailyMetric.date)
    )
    metrics = list(metrics_q.scalars().all())

    hrv_declining = False
    rhr_rising = False
    sleep_short = False
    if len(metrics) >= max(4, window_days // 2):
        # Split into halves
        midpoint = len(metrics) // 2
        first_half = metrics[:midpoint]
        second_half = metrics[midpoint:]

        def _avg(rows, attr):
            vals = [getattr(r, attr) for r in rows if getattr(r, attr) is not None]
            return statistics.mean(vals) if vals else None

        hrv_first = _avg(first_half, "hrv_overnight")
        hrv_second = _avg(second_half, "hrv_overnight")
        if hrv_first and hrv_second:
            decline = (hrv_first - hrv_second) / hrv_first
            hrv_declining = decline >= _LEA_HRV_DECLINE_PCT

        rhr_first = _avg(first_half, "resting_heart_rate")
        rhr_second = _avg(second_half, "resting_heart_rate")
        if rhr_first and rhr_second:
            rhr_rising = (rhr_second - rhr_first) >= _LEA_RHR_RISE_BPM

        sleep_avg = _avg(metrics, "sleep_duration_minutes")
        if sleep_avg is not None:
            sleep_short = (sleep_avg / 60) < _LEA_SLEEP_HOURS_FLOOR

    # 4) Motivation drop (Phase 4)
    wellness_q = await db.execute(
        select(WellnessCheckin.motivation).where(
            WellnessCheckin.user_id == user.id,
            WellnessCheckin.date >= start,
            WellnessCheckin.motivation.is_not(None),
        )
    )
    motivations = [int(m[0]) for m in wellness_q.all() if m[0]]
    mood_low = bool(motivations) and (statistics.mean(motivations) < _LEA_MOTIVATION_FLOOR)

    signals = {
        "chronic_low_intake": chronic_low_intake,
        "hrv_declining_with_load": hrv_declining,
        "rhr_rising": rhr_rising,
        "sleep_short": sleep_short,
        "mood_low": mood_low,
    }
    count = sum(1 for v in signals.values() if v)
    return {
        "window_days": window_days,
        "signals": signals,
        "signal_count": count,
        "is_critical": count >= _LEA_SIGNALS_REQUIRED_FOR_CRITICAL,
        "body_weight_kg_used": body_weight_kg,
        "daily_kcal_avg": round(statistics.mean(daily_kcal_per_kg) * body_weight_kg, 0) if daily_kcal_per_kg else None,
    }
