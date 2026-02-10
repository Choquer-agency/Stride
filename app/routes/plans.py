from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from app.models.schemas import TrainingPlanRequest, PlanEditRequest, ConflictAnalysisResponse
from app.services.openai_client import OpenAIClient
from app.services.prompt_builder import prompt_builder
from app.services.conflict_analyzer import conflict_analyzer
import json


router = APIRouter(prefix="/api", tags=["plans"])


@router.post("/analyze-conflicts", response_model=ConflictAnalysisResponse)
async def analyze_conflicts(request: TrainingPlanRequest) -> ConflictAnalysisResponse:
    """
    Analyze a training plan request for conflicts between goals and current fitness.
    
    This endpoint should be called after onboarding to detect issues like:
    - Goal pace significantly faster than current fitness
    - Injury history with aggressive goals
    - Insufficient training timeline
    - Weekly volume too low for goal
    
    Returns conflicts and recommendations, allowing users to override or accept.
    """
    # Validate dates
    if request.race_date <= request.start_date:
        raise HTTPException(
            status_code=400,
            detail="Race date must be after start date"
        )
    
    # Run conflict analysis
    return conflict_analyzer.analyze(request)


@router.post("/generate-plan")
async def generate_training_plan(request: TrainingPlanRequest):
    """
    Generate a personalized training plan based on the athlete's profile.
    
    Returns a streaming response with the plan text.
    """
    # Validate dates
    if request.race_date <= request.start_date:
        raise HTTPException(
            status_code=400,
            detail="Race date must be after start date"
        )
    
    # Calculate weeks
    training_days = (request.race_date - request.start_date).days
    if training_days < 14:
        raise HTTPException(
            status_code=400,
            detail="Training period must be at least 2 weeks"
        )
    
    # Build prompts using the specialized coach for this race type
    system_prompt = prompt_builder.get_system_prompt(request.race_type)
    user_prompt = prompt_builder.build_user_prompt(request)
    
    # Create OpenAI client
    client = OpenAIClient()
    
    async def generate():
        """Stream the generated plan."""
        try:
            async for chunk in client.generate_plan_stream(system_prompt, user_prompt):
                # Send each chunk as a server-sent event
                yield f"data: {json.dumps({'content': chunk})}\n\n"
            # Signal completion
            yield f"data: {json.dumps({'done': True})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"
    
    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"  # Disable nginx buffering
        }
    )


@router.post("/edit-plan")
async def edit_training_plan(request: PlanEditRequest):
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

    system_prompt = prompt_builder.get_edit_system_prompt()
    user_prompt = prompt_builder.build_edit_user_prompt(request)

    client = OpenAIClient()

    async def generate():
        """Stream the edited plan."""
        try:
            async for chunk in client.generate_plan_stream(system_prompt, user_prompt):
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
