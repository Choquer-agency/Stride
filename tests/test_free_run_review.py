"""Free runs receive honest coaching context and return shoe IDs for phone sync."""
from datetime import datetime, timezone
from uuid import uuid4

from app.models.community_schemas import RunResponse
from app.models.schemas import PostRunCoachRequest
from app.routes.plans import _build_post_run_user_prompt


def test_free_run_prompt_has_no_imaginary_prescription():
    request = PostRunCoachRequest(
        run_date="2026-11-05", run_type="free run", total_distance_km=14.82,
        total_time="1:28:00", avg_pace="5:56", athlete_name="Bryce",
    )
    prompt = _build_post_run_user_prompt(request)
    assert "athlete-chosen free run" in prompt
    assert "Do not claim it met or missed a training-plan target" in prompt
    assert "PRESCRIBED SESSION" not in prompt
    assert "TOMORROW'S WORKOUT" not in prompt


def test_server_run_response_includes_shoe_id():
    shoe_id = uuid4()
    response = RunResponse.model_validate({
        "id": uuid4(), "completed_at": datetime.now(timezone.utc),
        "distance_km": 14.82, "duration_seconds": 5300,
        "avg_pace_sec_per_km": 357.6, "data_source": "gps",
        "is_leaderboard_eligible": False,
        "synced_at": datetime.now(timezone.utc), "shoe_id": shoe_id,
    })
    assert response.model_dump(mode="json")["shoe_id"] == str(shoe_id)
