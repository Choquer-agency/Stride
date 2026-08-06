import json

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse

from app.models.schemas import TrainingPlanRequest, PlanEditRequest, PerformanceAnalysisRequest, PostRunCoachRequest, PreRunCoachRequest, PreRunCoachResponse, ConflictAnalysisResponse
from app.models.user import User
from app.services import plan_store
from app.services.anthropic_client import AnthropicClient, ClaudeRefusalError
from app.services.coaching_models import (
    PLAN_MODEL,
    PLAN_EDIT_MODEL,
    PLAN_ANALYSIS_MODEL,
    PRE_RUN_COACH_MODEL,
    POST_RUN_COACH_MODEL,
)
from app.services.prompt_builder import prompt_builder
from app.services.conflict_analyzer import conflict_analyzer
from app.services.auth_service import get_current_user
from app.services import analytics


router = APIRouter(prefix="/api", tags=["plans"])


@router.post("/analyze-conflicts", response_model=ConflictAnalysisResponse)
async def analyze_conflicts(request: TrainingPlanRequest, current_user: User = Depends(get_current_user)) -> ConflictAnalysisResponse:
    """
    Analyze a training plan request for conflicts between goals and current fitness.
    """
    if request.race_date <= request.start_date:
        raise HTTPException(
            status_code=400,
            detail="Race date must be after start date"
        )

    result = conflict_analyzer.analyze(request)

    analytics.capture(str(current_user.id), "conflicts_analyzed", {
        "race_type": request.race_type.value,
        "has_conflicts": result.has_conflicts,
    })

    return result


@router.post("/generate-plan")
async def generate_training_plan(request: TrainingPlanRequest, current_user: User = Depends(get_current_user)):
    """
    Generate a personalized training plan based on the athlete's profile.

    Returns a streaming response with the plan text.
    """
    if request.race_date <= request.start_date:
        raise HTTPException(
            status_code=400,
            detail="Race date must be after start date"
        )

    training_days = (request.race_date - request.start_date).days
    if training_days < 14:
        raise HTTPException(
            status_code=400,
            detail="Training period must be at least 2 weeks"
        )

    system_prompt = prompt_builder.get_system_prompt(request.race_type, request.custom_distance_km)
    user_prompt = prompt_builder.build_user_prompt(request)

    client = AnthropicClient()
    user_id_str = str(current_user.id)
    session_id = f"user:{user_id_str}:plan:{request.race_type.value}:{request.race_date}"

    analytics.capture(user_id_str, "plan_generated", {
        "race_type": request.race_type.value,
        "fitness_level": request.fitness_level.value,
        "plan_mode": request.plan_mode.value if request.plan_mode else None,
    })

    async def generate():
        full_output: list[str] = []
        try:
            async for chunk in client.generate_plan_stream(
                system_prompt,
                user_prompt,
                name="generate-plan",
                user_id=user_id_str,
                session_id=session_id,
                metadata={"race_type": request.race_type.value, "fitness_level": request.fitness_level.value},
                model=PLAN_MODEL,
            ):
                full_output.append(chunk)
                yield f"data: {json.dumps({'content': chunk})}\n\n"
            # Persist the generated plan server-side (never breaks the stream)
            await plan_store.save_plan_own_session(
                current_user.id,
                "".join(full_output),
                source="generated",
                race_type=request.race_type.value,
                race_date=request.race_date,
                race_name=request.race_name,
                goal_time=request.goal_time,
                custom_distance_km=request.custom_distance_km,
                start_date=request.start_date,
                fitness_level=request.fitness_level.value,
            )
            yield f"data: {json.dumps({'done': True})}\n\n"
        except ClaudeRefusalError:
            yield f"data: {json.dumps({'error': 'The coach could not process this request. Please adjust your inputs and try again.'})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )


@router.post("/edit-plan")
async def edit_training_plan(request: PlanEditRequest, current_user: User = Depends(get_current_user)):
    """
    Edit an existing training plan based on natural language instructions.

    Streams back the complete modified plan via SSE.
    """
    if not request.current_plan_content.strip():
        raise HTTPException(
            status_code=400,
            detail="Current plan content is required"
        )

    if not request.edit_instructions.strip():
        raise HTTPException(
            status_code=400,
            detail="Edit instructions are required"
        )

    system_prompt = prompt_builder.get_edit_system_prompt(request.race_type, request.custom_distance_km)
    user_prompt = prompt_builder.build_edit_user_prompt(request)

    client = AnthropicClient()
    user_id_str = str(current_user.id)
    session_id = f"user:{user_id_str}:plan:{request.race_type.value}:{request.race_date}"

    analytics.capture(user_id_str, "plan_edited", {
        "race_type": request.race_type.value,
    })

    async def generate():
        full_output: list[str] = []
        try:
            async for chunk in client.generate_plan_stream(
                system_prompt,
                user_prompt,
                name="edit-plan",
                user_id=user_id_str,
                session_id=session_id,
                metadata={"race_type": request.race_type.value},
                model=PLAN_EDIT_MODEL,
            ):
                full_output.append(chunk)
                yield f"data: {json.dumps({'content': chunk})}\n\n"
            await plan_store.save_plan_own_session(
                current_user.id,
                "".join(full_output),
                source="edited",
                race_type=request.race_type.value,
                race_date=request.race_date,
                race_name=request.race_name,
                goal_time=request.goal_time,
                custom_distance_km=request.custom_distance_km,
                start_date=request.start_date,
                change_note=request.edit_instructions[:2000],
            )
            yield f"data: {json.dumps({'done': True})}\n\n"
        except ClaudeRefusalError:
            yield f"data: {json.dumps({'error': 'The coach could not process this request. Please adjust your instructions and try again.'})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )


@router.post("/analyze-performance")
async def analyze_performance(request: PerformanceAnalysisRequest, current_user: User = Depends(get_current_user)):
    """
    Analyze an athlete's training performance against their plan.

    Streams back a coaching analysis via SSE, ending with a suggested plan adjustment.
    """
    if len(request.completed_workouts) < 1:
        raise HTTPException(
            status_code=400,
            detail="At least one completed workout is required for analysis"
        )

    if not request.current_plan_content.strip():
        raise HTTPException(
            status_code=400,
            detail="Current plan content is required"
        )

    system_prompt = prompt_builder.get_analysis_system_prompt(request.race_type, request.custom_distance_km)
    user_prompt = prompt_builder.build_analysis_user_prompt(request)

    client = AnthropicClient()
    user_id_str = str(current_user.id)
    session_id = f"user:{user_id_str}:plan:{request.race_type.value}:{request.race_date}"

    analytics.capture(user_id_str, "performance_analyzed", {
        "race_type": request.race_type.value,
        "weeks_into_plan": request.weeks_into_plan,
        "total_workouts": len(request.completed_workouts),
    })

    async def generate():
        try:
            async for chunk in client.generate_plan_stream(
                system_prompt,
                user_prompt,
                name="analyze-performance",
                user_id=user_id_str,
                session_id=session_id,
                metadata={
                    "race_type": request.race_type.value,
                    "weeks_into_plan": request.weeks_into_plan,
                },
                model=PLAN_ANALYSIS_MODEL,
            ):
                yield f"data: {json.dumps({'content': chunk})}\n\n"
            yield f"data: {json.dumps({'done': True})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )


# ── Post-Run AI Coach ────────────────────────────────────────────────────────


def _build_post_run_user_prompt(req: PostRunCoachRequest) -> str:
    """Build the user message from run data."""
    best_split = None
    slowest_split = None
    if req.km_splits:
        sorted_by_pace = sorted(req.km_splits, key=lambda s: s.pace)
        best_split = sorted_by_pace[0]
        slowest_split = sorted_by_pace[-1]

    lines = [
        "RUN DATA:",
        f"- Date: {req.run_date}",
        f"- Run type: {req.run_type}",
        f"- Total distance: {req.total_distance_km} km",
        f"- Total time: {req.total_time}",
        f"- Average pace: {req.avg_pace}/km",
    ]

    if best_split:
        lines.append(f"- Best split: Kilometer {best_split.kilometer} at {best_split.pace}/km")
    if slowest_split:
        lines.append(f"- Slowest split: Kilometer {slowest_split.kilometer} at {slowest_split.pace}/km")
    if req.pace_consistency_pct is not None:
        lines.append(f"- Pace consistency: {req.pace_consistency_pct:.1f}% variance across splits")
    lines.append(f"- Negative split: {req.negative_split}")
    if req.avg_hr:
        lines.append(f"- Average heart rate: {req.avg_hr} bpm")
    if req.max_hr:
        lines.append(f"- Max heart rate: {req.max_hr} bpm")
    if req.avg_cadence:
        lines.append(f"- Average cadence: {req.avg_cadence} spm")
    if req.elevation_gain:
        lines.append(f"- Elevation gain: {req.elevation_gain:.0f} m")

    lines.append("")
    lines.append("RECORDS AND MILESTONES:")
    lines.append(f"- New personal record: {req.pr_flag}")
    lines.append(f"- PR detail: {req.pr_detail or 'none'}")
    if req.weekly_distance_km is not None and req.weekly_goal_km is not None:
        lines.append(f"- Weekly distance so far: {req.weekly_distance_km:.1f} km of {req.weekly_goal_km:.1f} km goal")
    if req.streak_days:
        lines.append(f"- Running streak: {req.streak_days} consecutive days")
    if req.monthly_distance_km:
        lines.append(f"- Monthly distance: {req.monthly_distance_km:.1f} km")

    if req.last_similar_run_pace or req.trend:
        lines.append("")
        lines.append("COMPARISON TO RECENT RUNS:")
        if req.last_similar_run_pace:
            lines.append(f"- Last run at similar distance: {req.last_similar_run_pace}/km on {req.last_similar_run_date or 'unknown'}")
        if req.trend:
            lines.append(f"- Trend: {req.trend}")

    if req.tomorrow_type:
        lines.append("")
        lines.append("TOMORROW'S WORKOUT:")
        lines.append(f"- Type: {req.tomorrow_type}")
        if req.tomorrow_distance_km:
            lines.append(f"- Target distance: {req.tomorrow_distance_km} km")
        if req.tomorrow_target_pace:
            lines.append(f"- Target pace: {req.tomorrow_target_pace}/km")
        if req.tomorrow_notes:
            lines.append(f"- Notes: {req.tomorrow_notes}")

    lines.append("")
    lines.append("ATHLETE CONTEXT:")
    lines.append(f"- Name: {req.athlete_name}")
    if req.habits_to_reinforce:
        lines.append(f"- Known habits to reinforce: {req.habits_to_reinforce}")
    if req.training_block:
        lines.append(f"- Current training block: {req.training_block}")
    if req.goal_race:
        lines.append(f"- Goal race: {req.goal_race}")

    lines.append("")
    lines.append("Generate the spoken post-run coaching summary.")

    return "\n".join(lines)


@router.post("/post-run-coach")
async def post_run_coach(request: PostRunCoachRequest, current_user: User = Depends(get_current_user)):
    """
    Generate a personalized post-run coaching summary.
    Streams back spoken text designed for ElevenLabs TTS playback.
    """
    prerecorded_alerts = request.prerecorded_alerts_delivered or "Kilometer splits with pace and total time were announced each kilometer."
    system_prompt = prompt_builder.get_post_run_voice_prompt(prerecorded_alerts)
    user_prompt = _build_post_run_user_prompt(request)

    client = AnthropicClient()
    user_id_str = str(current_user.id)

    analytics.capture(user_id_str, "post_run_coach_generated", {
        "distance_km": request.total_distance_km,
        "run_type": request.run_type,
        "pr_flag": request.pr_flag,
    })

    async def generate():
        try:
            async for chunk in client.generate_plan_stream(
                system_prompt,
                user_prompt,
                name="post-run-coach",
                user_id=user_id_str,
                session_id=f"user:{user_id_str}:run:{request.run_date}",
                metadata={
                    "distance_km": request.total_distance_km,
                    "run_type": request.run_type,
                },
                model=POST_RUN_COACH_MODEL,
            ):
                yield f"data: {json.dumps({'content': chunk})}\n\n"
            yield f"data: {json.dumps({'done': True})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )


# ── Pre-Run AI Coach ─────────────────────────────────────────────────────────


def _build_pre_run_user_prompt(req: PreRunCoachRequest) -> str:
    lines = ["WORKOUT DETAILS:"]
    if req.is_free_run:
        lines.append("- Type: free run (athlete chose their own distance/pace)")
    elif req.workout_type:
        lines.append(f"- Type: {req.workout_type}")
    if req.workout_title:
        lines.append(f"- Title: {req.workout_title}")
    if req.target_distance_km:
        lines.append(f"- Target distance: {req.target_distance_km} kilometers")
    if req.target_duration_minutes:
        lines.append(f"- Target duration: {req.target_duration_minutes} minutes")
    if req.target_pace:
        lines.append(f"- Target pace: {req.target_pace}")
    if req.goal_race:
        lines.append(f"- Goal race: {req.goal_race}")
    if req.weeks_to_race is not None:
        lines.append(f"- Weeks until race: {req.weeks_to_race}")
    if req.athlete_name:
        lines.append(f"- Athlete: {req.athlete_name}")
    if req.time_of_day:
        lines.append(f"- Local time of day: {req.time_of_day}")
    lines.append("")
    lines.append("Generate the pre-run motivational send-off.")
    return "\n".join(lines)


@router.post("/pre-run-coach", response_model=PreRunCoachResponse)
async def pre_run_coach(request: PreRunCoachRequest, current_user: User = Depends(get_current_user)) -> PreRunCoachResponse:
    """Generate a short motivational intro spoken right before the countdown."""
    import logging
    import traceback
    log = logging.getLogger(__name__)
    user_id_str = str(current_user.id)

    try:
        client = AnthropicClient()
        text = await client.generate_plan(
            prompt_builder.get_pre_run_voice_prompt(),
            _build_pre_run_user_prompt(request),
            name="pre-run-coach",
            user_id=user_id_str,
            session_id=f"user:{user_id_str}:pre-run",
            metadata={
                "workout_type": request.workout_type,
                "is_free_run": request.is_free_run,
            },
            model=PRE_RUN_COACH_MODEL,
        )
    except Exception as e:
        tb = traceback.format_exc()
        log.error("pre-run-coach failed: %s\n%s", e, tb)
        # Echo the error class + message in the HTTPException detail so it surfaces
        # in the iOS response body during development.
        raise HTTPException(status_code=500, detail=f"{type(e).__name__}: {e}")

    try:
        analytics.capture(user_id_str, "pre_run_coach_generated", {
            "workout_type": request.workout_type or "free_run",
            "is_free_run": request.is_free_run,
        })
    except Exception:
        log.exception("analytics capture failed (non-fatal)")

    return PreRunCoachResponse(text=text.strip())


# ── Server-side plan store: pull + backfill sync ─────────────────────────────


from datetime import date as _date
from typing import Optional as _Optional
from uuid import UUID as _UUID

from pydantic import BaseModel as _BaseModel
from sqlalchemy.ext.asyncio import AsyncSession as _AsyncSession

from app.database import get_db as _get_db


class ActivePlanResponse(_BaseModel):
    id: _Optional[_UUID] = None
    updated_at: _Optional[str] = None
    source: _Optional[str] = None
    raw_plan_content: _Optional[str] = None
    race_type: _Optional[str] = None
    race_date: _Optional[str] = None
    race_name: _Optional[str] = None
    goal_time: _Optional[str] = None
    custom_distance_km: _Optional[float] = None
    start_date: _Optional[str] = None
    change_note: _Optional[str] = None


@router.get("/plans/active", response_model=ActivePlanResponse)
async def get_active_plan(
    current_user: User = Depends(get_current_user),
    db: _AsyncSession = Depends(_get_db),
) -> ActivePlanResponse:
    """
    The server's copy of the athlete's active plan. iOS compares updated_at
    against the last version it applied; a newer server_edit means the coach
    changed the plan here and the app should offer to apply it.
    """
    record = await plan_store.get_active(db, current_user.id)
    if record is None:
        return ActivePlanResponse()
    return ActivePlanResponse(
        id=record.id,
        updated_at=record.updated_at.isoformat() if record.updated_at else None,
        source=record.source,
        raw_plan_content=record.raw_plan_content,
        race_type=record.race_type,
        race_date=record.race_date.isoformat() if record.race_date else None,
        race_name=record.race_name,
        goal_time=record.goal_time,
        custom_distance_km=record.custom_distance_km,
        start_date=record.start_date.isoformat() if record.start_date else None,
        change_note=record.change_note,
    )


class PlanSyncRequest(_BaseModel):
    client_plan_id: _Optional[_UUID] = None
    raw_plan_content: str
    race_type: _Optional[str] = None
    race_date: _Optional[_date] = None
    race_name: _Optional[str] = None
    goal_time: _Optional[str] = None
    custom_distance_km: _Optional[float] = None
    start_date: _Optional[_date] = None


@router.post("/plans/sync", response_model=ActivePlanResponse)
async def sync_plan(
    body: PlanSyncRequest,
    current_user: User = Depends(get_current_user),
    db: _AsyncSession = Depends(_get_db),
) -> ActivePlanResponse:
    """
    iOS backfill: upload the device's active plan when the server has no copy
    (plans created before server-side persistence) or when the device holds
    content the server doesn't. No-ops when content already matches.
    """
    if not body.raw_plan_content.strip():
        raise HTTPException(status_code=400, detail="raw_plan_content is required")

    existing = await plan_store.get_active(db, current_user.id)
    if existing is not None and existing.raw_plan_content == body.raw_plan_content:
        record = existing
    else:
        record = await plan_store.save_plan(
            db,
            current_user.id,
            body.raw_plan_content,
            source="ios_backfill",
            race_type=body.race_type,
            race_date=body.race_date,
            race_name=body.race_name,
            goal_time=body.goal_time,
            custom_distance_km=body.custom_distance_km,
            start_date=body.start_date,
            client_plan_id=body.client_plan_id,
        )
        await db.commit()

    return ActivePlanResponse(
        id=record.id,
        updated_at=record.updated_at.isoformat() if record.updated_at else None,
        source=record.source,
        race_type=record.race_type,
    )
