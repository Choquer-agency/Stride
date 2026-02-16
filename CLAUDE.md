# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Stride is an AI-powered running coach with three components:
- **Python FastAPI backend** (`app/`) — API server with SSE streaming, JWT auth, PostgreSQL
- **Native iOS app** (`StrideApp/`) — SwiftUI + SwiftData, MVVM architecture
- **React marketing site** (`website/`) — Vite + Tailwind CSS

## Commands

### Backend
```bash
# Install deps
pip install -r requirements.txt

# Run dev server (auto-reload)
uvicorn app.main:app --reload

# API docs at http://localhost:8000/docs
```

### Website
```bash
cd website
npm install
npm run dev      # Dev server at localhost:5173
npm run build    # Production build → dist/
npm run lint     # ESLint
```

### iOS
- Open `StrideApp/` in Xcode (project.yml for XcodeGen)
- iOS 17.0+ / Swift 5.9+ / Xcode 15+

## Architecture

### Backend (`app/`)
- **Entry point**: `app/main.py` — FastAPI app with CORS, static files, Jinja2 templates
- **Routes**: `routes/plans.py` (plan generation/editing SSE), `routes/auth.py` (JWT + OAuth), `routes/runs.py`, `routes/community.py`, `routes/admin.py` (HTMX dashboard), `routes/social.py`
- **Services**: Business logic layer — `auth_service.py` (JWT/passwords), `prompt_builder.py` (LLM prompt assembly), `event_service.py`, `social_service.py`, `storage_service.py` (Cloudflare R2), `analytics.py` (PostHog)
- **Prompts**: `prompts/coach_speed.txt` (5K/10K), `coach_marathon.txt` (HM/FM), `coach_ultra.txt` (50K+), `coach_edit.txt`, `coach_analysis.txt`
- **Database**: Neon PostgreSQL via SQLAlchemy async (`database.py`). Schema migrations done inline in startup event (no Alembic). Key tables: `users`, `events`, `follows`, `teams`, `activity_logs`, `achievements`, `challenges`
- **Auth**: JWT via python-jose, password hashing via passlib/bcrypt. `get_current_user()` dependency for protected routes
- **LLM**: OpenAI GPT-4.1 and Anthropic Claude for plan generation. Langfuse for observability

### iOS (`StrideApp/`)
- **SwiftData models**: `TrainingPlan` → `Week[]` → `Workout[]` (cascade deletes). `RunLog` is standalone for permanent run history that survives plan deletion
- **SSE streaming**: `APIService.generatePlan()` / `editPlan()` use chunked callbacks (`onChunk`/`onComplete`/`onError`)
- **Plan parsing**: `PlanParser.parse()` converts raw AI text → `[ParsedWeek]` → SwiftData models. Plans stored as `rawPlanContent` for re-parsing
- **Auth state machine**: `AuthService` manages `unknown` → `signedOut` → `needsProfile` → `signedIn`. JWT stored in Keychain via `KeychainService`
- **Tabs**: Run, Plan, Stats, Profile (in `MainTabView.swift`)
- **Active plan queries** must filter `isArchived == false` using `@Query` with `#Predicate`

### Design System
- **Brand color**: `Color.stridePrimary` = #FF2617 (red)
- **Fonts**: `.inter()` for body text, `.barlowCondensed()` for numbers/stats (custom TTFs in `StrideApp/Fonts/`)

## Key Environment Variables
Backend requires `.env` with: `OPENAI_API_KEY`, `OPENAI_MODEL`, `DATABASE_URL` (asyncpg), `JWT_SECRET_KEY`, `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, `LANGFUSE_*`, `POSTHOG_API_KEY`, `R2_*` (Cloudflare storage), `ADMIN_SESSION_SECRET`

## Deployment
- **Backend**: Railway (uvicorn on `$PORT`)
- **Database**: Neon PostgreSQL (connection pooler)
- **Storage**: Cloudflare R2 (S3-compatible)
- **iOS**: Xcode → Archive → TestFlight
