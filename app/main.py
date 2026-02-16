from fastapi import FastAPI, Request
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
from sqlalchemy import text
from app.database import init_db, async_session, engine
from app.services import analytics
from app.services.achievement_service import seed_achievement_definitions
from app.services.challenge_service import auto_generate_weekly_challenges, auto_generate_monthly_challenge

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


@app.on_event("startup")
async def startup():
    """Initialize the database and seed data on startup."""
    await init_db()

    # Migrate: add is_admin column if missing
    async with engine.begin() as conn:
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT FALSE"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS bio VARCHAR(255)"))

    async with async_session() as db:
        await seed_achievement_definitions(db)
        await auto_generate_weekly_challenges(db)
        await auto_generate_monthly_challenge(db)


@app.on_event("shutdown")
async def shutdown():
    """Flush analytics and LLM observability on shutdown."""
    from langfuse import Langfuse
    Langfuse().flush()
    analytics.shutdown()


@app.get("/")
async def home():
    """Serve the marketing website homepage."""
    from fastapi.responses import FileResponse
    return FileResponse(WEBSITE_DIST / "index.html")


@app.get("/hero-video.mp4")
async def hero_video():
    """Serve the hero video."""
    return FileResponse(WEBSITE_DIST / "hero-video.mp4", media_type="video/mp4")


@app.get("/stride-icon.svg")
async def stride_icon():
    """Serve the stride icon."""
    return FileResponse(WEBSITE_DIST / "stride-icon.svg", media_type="image/svg+xml")


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "version": "2.0.0"}
