from fastapi import FastAPI, Request
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.middleware.cors import CORSMiddleware
from pathlib import Path

from app.routes.plans import router as plans_router
from app.routes.auth import router as auth_router
from app.routes.runs import router as runs_router
from app.routes.community import router as community_router
from app.routes.admin import router as admin_router
from app.routes.social import router as social_router
from app.routes.shoes import router as shoes_router
from app.routes.devices import router as devices_router
from app.routes.coaching import router as coaching_router
from app.routes.garmin import router as garmin_router
from app.routes.wellness import router as wellness_router
from app.routes.nutrition import router as nutrition_router, hydration_router
from app.routes.race_prep import router as race_prep_router
from app.routes.strength import router as strength_router
from app.routes.voice import router as voice_router
from sqlalchemy import text
from app.database import init_db, async_session, engine
from app.models.shoe import Shoe  # noqa: F401 — ensure table is created
# v2 coaching infrastructure tables — register with Base.metadata
from app.models.coaching_event import CoachingEvent  # noqa: F401
from app.models.anomaly_flag import AnomalyFlag  # noqa: F401
from app.models.coach_memo import CoachMemo  # noqa: F401
from app.models.plan_adjustment import PlanAdjustment  # noqa: F401
from app.models.coaching_cooldown import CoachingCooldown  # noqa: F401
from app.models.weekly_focus import WeeklyFocus  # noqa: F401
# v2 Phase 1: Garmin tables
from app.models.garmin_workout import GarminWorkout  # noqa: F401
from app.models.garmin_daily_metric import GarminDailyMetric  # noqa: F401
from app.models.garmin_periodic_metric import GarminPeriodicMetric  # noqa: F401
# v2 Phase 4: Wellness check-ins
from app.models.wellness_checkin import WellnessCheckin  # noqa: F401
# v2 Phase 5: Conversational chat
from app.models.chat_message import ChatMessage  # noqa: F401
from app.models.chat_summary import ChatSummary  # noqa: F401
# v2 Phase 6: Nutrition + hydration + race fueling + recipe templates
from app.models.nutrition_log import NutritionLog  # noqa: F401
from app.models.hydration_log import HydrationLog  # noqa: F401
from app.models.race_fueling_plan import RaceFuelingPlan  # noqa: F401
from app.models.recipe_template import RecipeTemplate  # noqa: F401
# v2 Phase 8: Race-prep logistics checklist
from app.models.race_logistics_checklist import RaceLogisticsChecklist  # noqa: F401
# v2 Phase 9: Strength logging
from app.models.strength_exercise import StrengthExercise  # noqa: F401
from app.models.strength_session import StrengthSession  # noqa: F401
from app.models.strength_set import StrengthSet  # noqa: F401
from app.models.weekly_checkin import WeeklyCheckin  # noqa: F401
from app.models.training_plan import TrainingPlanRecord  # noqa: F401
from app.services import analytics
from app.services.achievement_service import seed_achievement_definitions
from app.services.challenge_service import auto_generate_weekly_challenges, auto_generate_monthly_challenge
from app.scheduler import start_scheduler, shutdown_scheduler
from app.services.adjustment_jobs import register_jobs as register_adjustment_jobs
from app.services.garmin_jobs import register_jobs as register_garmin_jobs
from app.services.weekly_review_jobs import register_jobs as register_weekly_review_jobs
from app.services.wellness_jobs import register_jobs as register_wellness_jobs
from app.services.nutrition_jobs import register_jobs as register_nutrition_jobs
from app.services.block_review_jobs import register_jobs as register_block_review_jobs
from app.services.race_prep_jobs import register_jobs as register_race_prep_jobs
from app.services.weekly_checkin_jobs import register_jobs as register_weekly_checkin_jobs

# Get the project root directory
BASE_DIR = Path(__file__).resolve().parent.parent

app = FastAPI(
    title="Stride - AI Running Coach",
    description="Professional training plan generator powered by AI",
    version="2.0.0"
)

# CORS middleware for development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount static files
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")

# Mount website dist assets (CSS/JS/images from Vite build)
WEBSITE_DIST = BASE_DIR / "website" / "dist"
app.mount("/assets", StaticFiles(directory=WEBSITE_DIST / "assets"), name="website-assets")
app.mount("/photos", StaticFiles(directory=WEBSITE_DIST / "photos"), name="website-photos")

# Templates (for admin)
templates = Jinja2Templates(directory=BASE_DIR / "templates")

# Include routers
app.include_router(auth_router)
app.include_router(plans_router)
app.include_router(runs_router)
app.include_router(community_router)
app.include_router(admin_router)
app.include_router(social_router)
app.include_router(shoes_router)
app.include_router(devices_router)
app.include_router(coaching_router)
app.include_router(garmin_router)
app.include_router(wellness_router)
app.include_router(nutrition_router)
app.include_router(hydration_router)
app.include_router(race_prep_router)
app.include_router(strength_router)
app.include_router(voice_router)


@app.on_event("startup")
async def startup():
    """Initialize the database and seed data on startup."""
    await init_db()

    # Migrate: add is_admin column if missing
    async with engine.begin() as conn:
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT FALSE"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS bio VARCHAR(255)"))
        await conn.execute(text("ALTER TABLE runs ADD COLUMN IF NOT EXISTS shoe_id UUID REFERENCES shoes(id)"))

        # v2 coaching infrastructure — User schema additions (Phase 0)
        # Per-loop coaching mode toggle: {loop_name: "shadow" | "live" | "off"}
        await conn.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS coaching_modes JSONB NOT NULL DEFAULT '"
            "{\"weekly_review\":\"shadow\",\"block_review\":\"shadow\",\"post_run_check\":\"shadow\","
            "\"race_prep\":\"shadow\",\"chat\":\"live\",\"nutrition\":\"off\",\"wellness\":\"live\"}'::jsonb"
        ))
        # First-3-events feedback counter: {loop_name: int}
        await conn.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS coaching_feedback_seen JSONB NOT NULL DEFAULT '{}'::jsonb"
        ))
        # APNs device token (hex)
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS apns_device_token VARCHAR(64)"))
        # Garmin OAuth + connection state (Phase 1 wires)
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS garmin_access_token TEXT"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS garmin_refresh_token TEXT"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS garmin_user_id VARCHAR(64)"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS garmin_connected_at TIMESTAMP WITH TIME ZONE"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS garmin_disconnected_at TIMESTAMP WITH TIME ZONE"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS garmin_backfill_status VARCHAR(16) NOT NULL DEFAULT 'pending'"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS garmin_backfill_progress INTEGER NOT NULL DEFAULT 0"))
        # Notification preferences
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS quiet_hours_start TIME"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS quiet_hours_end TIME"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS muted_notification_types TEXT[] NOT NULL DEFAULT '{}'"))
        # Pause coach (Phase 3)
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS coaching_paused_until TIMESTAMP WITH TIME ZONE"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS coaching_resume_pending BOOLEAN NOT NULL DEFAULT FALSE"))

        # v2 Phase 2: pin race type for cron-driven prompts (no iOS context at cron time)
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS current_race_type VARCHAR(20) DEFAULT 'marathon'"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS checkin_day_of_week INTEGER"))
        # Widen rep-range display column (seed data has values up to 17 chars)
        await conn.execute(text("ALTER TABLE strength_exercises ALTER COLUMN default_rep_range TYPE VARCHAR(32)"))

        # v2 Phase 4: enforce one morning wellness check-in per user per date
        # (additional pre_run / post_run / manual entries on the same date are allowed).
        await conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_wellness_morning_per_user_date "
            "ON wellness_checkins (user_id, date) WHERE entry_method = 'morning'"
        ))

    async with async_session() as db:
        await seed_achievement_definitions(db)
        await auto_generate_weekly_challenges(db)
        await auto_generate_monthly_challenge(db)
        # v2 Phase 9: seed strength exercise library on startup
        from app.services import strength_service
        await strength_service.seed_library_if_empty(db)
        await db.commit()

    # Register all v2 cron jobs before starting the scheduler.
    register_garmin_jobs()
    register_weekly_review_jobs()
    register_adjustment_jobs()
    register_wellness_jobs()
    register_nutrition_jobs()
    register_block_review_jobs()
    register_race_prep_jobs()
    register_weekly_checkin_jobs()
    start_scheduler()


@app.on_event("shutdown")
async def shutdown():
    """Flush analytics and LLM observability on shutdown."""
    shutdown_scheduler()
    from app.services.push_service import cleanup_apns_temp_files
    cleanup_apns_temp_files()
    from langfuse import Langfuse
    Langfuse().flush()
    analytics.shutdown()


@app.get("/")
async def home():
    """Serve the marketing website homepage."""
    return FileResponse(WEBSITE_DIST / "index.html")


@app.get("/hero-video2.mp4")
async def hero_video():
    """Serve the hero video."""
    return FileResponse(WEBSITE_DIST / "hero-video2.mp4", media_type="video/mp4")


@app.get("/stride-icon.svg")
async def stride_icon():
    """Serve the stride icon."""
    return FileResponse(WEBSITE_DIST / "stride-icon.svg", media_type="image/svg+xml")


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "version": "2.0.0"}
