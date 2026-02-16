import json

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse

from app.models.schemas import TrainingPlanRequest, PlanEditRequest, PerformanceAnalysisRequest, ConflictAnalysisResponse
from app.models.user import User
from app.services.anthropic_client import AnthropicClient
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

    system_prompt = prompt_builder.get_system_prompt(request.race_type)
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
        try:
            async for chunk in client.generate_plan_stream(
                system_prompt,
                user_prompt,
                name="generate-plan",
                user_id=user_id_str,
                session_id=session_id,
                metadata={"race_type": request.race_type.value, "fitness_level": request.fitness_level.value},
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

    system_prompt = prompt_builder.get_edit_system_prompt(request.race_type)
    user_prompt = prompt_builder.build_edit_user_prompt(request)

    client = AnthropicClient()
    user_id_str = str(current_user.id)
    session_id = f"user:{user_id_str}:plan:{request.race_type.value}:{request.race_date}"

    analytics.capture(user_id_str, "plan_edited", {
        "race_type": request.race_type.value,
    })

    async def generate():
        try:
            async for chunk in client.generate_plan_stream(
                system_prompt,
                user_prompt,
                name="edit-plan",
                user_id=user_id_str,
                session_id=session_id,
                metadata={"race_type": request.race_type.value},
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

    system_prompt = prompt_builder.get_analysis_system_prompt(request.race_type)
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
