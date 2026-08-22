from pydantic import BaseModel, Field, model_validator
from typing import Optional
from datetime import date
from enum import Enum


class RaceType(str, Enum):
    """Supported race distances."""
    FIVE_K = "5K"
    TEN_K = "10K"
    HALF_MARATHON = "Half Marathon"
    MARATHON = "Marathon"
    CUSTOM = "Custom"


class TerrainType(str, Enum):
    """Terrain types for ultra/custom distances."""
    ROAD = "road"
    TRAIL = "trail"
    MOUNTAIN = "mountain"


class FitnessLevel(str, Enum):
    """Self-assessed fitness levels."""
    BEGINNER = "beginner"
    INTERMEDIATE = "intermediate"
    ADVANCED = "advanced"


class DayOfWeek(str, Enum):
    """Days of the week."""
    MONDAY = "Monday"
    TUESDAY = "Tuesday"
    WEDNESDAY = "Wednesday"
    THURSDAY = "Thursday"
    FRIDAY = "Friday"
    SATURDAY = "Saturday"
    SUNDAY = "Sunday"


class PlanMode(str, Enum):
    """Training plan generation mode based on user's conflict resolution choice."""
    AGGRESSIVE = "aggressive"  # User overrides - build toward original goal
    RECOMMENDED = "recommended"  # User accepts - use adjusted/safer approach


class GoalType(str, Enum):
    """What the athlete is training toward."""
    RACE = "race"      # A race with a time goal
    FINISH = "finish"  # A race with a completion goal (no time target)
    HABIT = "habit"    # No race — a rolling block to build a consistent running habit


class ConflictType(str, Enum):
    """Types of conflicts that can be detected between goals and current state."""
    GOAL_VS_FITNESS = "goal_vs_fitness"  # Goal pace much faster than current fitness
    INJURY_RISK = "injury_risk"  # Injury history with aggressive goals
    TIMELINE_PRESSURE = "timeline_pressure"  # Not enough training time
    VOLUME_INSUFFICIENT = "volume_insufficient"  # Weekly volume too low for goal
    BENCHMARKS_UNREACHABLE = "benchmarks_unreachable"  # Required training benchmarks cannot be safely reached in timeline


class RiskLevel(str, Enum):
    """Risk level for detected conflicts."""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class DetectedConflict(BaseModel):
    """A single detected conflict between user goals and current state."""
    conflict_type: ConflictType = Field(..., description="Type of conflict detected")
    risk_level: RiskLevel = Field(..., description="Severity of the conflict")
    title: str = Field(..., description="Short title for the conflict")
    description: str = Field(..., description="Detailed explanation of the conflict")
    recommendation: str = Field(..., description="What we recommend instead")


class ConflictAnalysisResponse(BaseModel):
    """Response from conflict analysis endpoint."""
    has_conflicts: bool = Field(..., description="Whether any conflicts were detected")
    conflicts: list[DetectedConflict] = Field(default_factory=list, description="List of detected conflicts")
    original_goal_time: Optional[str] = Field(None, description="The user's original goal time")
    recommended_goal_time: Optional[str] = Field(None, description="Recommended adjusted goal time")
    recommendation_summary: Optional[str] = Field(None, description="Summary of overall recommendation")


class PlanEditRequest(BaseModel):
    """Request schema for editing an existing training plan."""
    race_type: RaceType = Field(..., description="Target race distance")
    race_date: date = Field(..., description="Date of the goal race")
    race_name: Optional[str] = Field(None, description="Name of the race")
    goal_time: Optional[str] = Field(None, description="Target finish time")
    custom_distance_km: Optional[float] = Field(None, ge=1, le=500, description="Custom race distance in km")
    start_date: date = Field(..., description="Plan start date")
    current_plan_content: str = Field(..., description="The raw text of the current training plan")
    edit_instructions: str = Field(..., description="Natural language description of desired changes")
    goal_type: Optional[GoalType] = Field(None, description="race | finish | habit — preserved from the original plan request")
    beginner_mode: bool = Field(default=False, description="Compose the beginner module so edits keep the beginner plan style")


class CompletedWorkoutData(BaseModel):
    """Data for a single completed workout, sent for performance analysis."""
    date: str = Field(..., description="Workout date (YYYY-MM-DD)")
    workout_type: str = Field(..., description="Type of workout")
    planned_distance_km: Optional[float] = Field(None)
    actual_distance_km: Optional[float] = Field(None)
    planned_pace_description: Optional[str] = Field(None)
    actual_avg_pace_sec_per_km: Optional[float] = Field(None)
    completion_score: Optional[int] = Field(None, description="0-100 score")
    feedback_rating: Optional[int] = Field(None, description="0-5 subjective feel")


class PerformanceAnalysisRequest(BaseModel):
    """Request schema for AI performance analysis (SSE streaming)."""
    race_type: RaceType
    race_date: date
    start_date: date
    goal_time: Optional[str] = None
    custom_distance_km: Optional[float] = Field(None, ge=1, le=500, description="Custom race distance in km")
    current_weekly_mileage: int
    fitness_level: FitnessLevel
    completed_workouts: list[CompletedWorkoutData]
    weeks_into_plan: int
    total_plan_weeks: int
    current_plan_content: str = Field(..., description="Raw text of the current training plan")


class KmSplitData(BaseModel):
    """Data for a single kilometer split."""
    kilometer: int
    pace: str
    time: str
    is_fastest: bool = False


class PostRunCoachRequest(BaseModel):
    """Request schema for AI post-run coaching summary (SSE streaming → ElevenLabs TTS)."""
    # Run data
    run_date: str
    run_type: str = "easy run"
    total_distance_km: float
    total_time: str
    avg_pace: str
    km_splits: list[KmSplitData] = []
    pace_consistency_pct: Optional[float] = None
    negative_split: bool = False
    avg_hr: Optional[int] = None
    max_hr: Optional[int] = None
    avg_cadence: Optional[int] = None
    elevation_gain: Optional[float] = None

    # Records and milestones
    pr_flag: bool = False
    pr_detail: Optional[str] = None
    weekly_distance_km: Optional[float] = None
    weekly_goal_km: Optional[float] = None
    streak_days: Optional[int] = None
    monthly_distance_km: Optional[float] = None

    # Comparison
    last_similar_run_pace: Optional[str] = None
    last_similar_run_date: Optional[str] = None
    trend: Optional[str] = None

    # Tomorrow's workout
    tomorrow_type: Optional[str] = None
    tomorrow_distance_km: Optional[float] = None
    tomorrow_target_pace: Optional[str] = None
    tomorrow_notes: Optional[str] = None

    # Athlete context
    athlete_name: str = "runner"
    habits_to_reinforce: Optional[str] = None
    training_block: Optional[str] = None
    goal_race: Optional[str] = None

    # What prerecorded alerts were already played mid-run
    prerecorded_alerts_delivered: Optional[str] = None


class PreRunCoachRequest(BaseModel):
    """Request schema for the AI pre-run motivational intro spoken before the countdown."""
    athlete_name: Optional[str] = None
    workout_type: Optional[str] = None       # e.g. "tempo run", "intervals", "long run", "free run"
    workout_title: Optional[str] = None      # e.g. "Tempo 8K" (if planned)
    target_distance_km: Optional[float] = None
    target_duration_minutes: Optional[int] = None
    target_pace: Optional[str] = None        # e.g. "5:00/km"
    is_free_run: bool = False
    goal_race: Optional[str] = None
    weeks_to_race: Optional[int] = None
    # Athlete's local time-of-day bucket ("early morning", "morning", "afternoon",
    # "evening", "night") — used so the coach's greeting matches the hour.
    time_of_day: Optional[str] = None


class PreRunCoachResponse(BaseModel):
    text: str


class TrainingPlanRequest(BaseModel):
    """Request schema for training plan generation."""
    
    # Goal Information
    race_type: RaceType = Field(..., description="Target race distance")
    race_date: date = Field(..., description="Date of the goal race")
    race_name: Optional[str] = Field(None, description="Name of the race (optional)")
    goal_time: Optional[str] = Field(None, description="Target finish time (optional)")
    custom_distance_km: Optional[float] = Field(None, ge=1, le=500, description="Custom race distance in km")
    terrain_type: Optional[TerrainType] = Field(None, description="Terrain type for ultra distances")
    elevation_gain_m: Optional[int] = Field(None, ge=0, le=20000, description="Total elevation gain in meters")

    # Current Fitness
    current_weekly_mileage: int = Field(..., ge=0, le=300, description="Current weekly running volume in km")
    longest_recent_run: int = Field(..., ge=0, le=160, description="Longest run in past 4 weeks in km")
    recent_race_times: Optional[str] = Field(None, description="Recent race performances")
    recent_runs: Optional[str] = Field(None, description="Recent training runs from the last 7-21 days")
    fitness_level: FitnessLevel = Field(..., description="Self-assessed fitness level")
    
    # Schedule Constraints
    start_date: date = Field(..., description="When to start training")
    rest_days: list[DayOfWeek] = Field(default_factory=list, description="Preferred rest days")
    long_run_day: DayOfWeek = Field(default=DayOfWeek.SUNDAY, description="Preferred day for long runs")
    double_days_allowed: bool = Field(default=False, description="Whether two-a-day workouts are allowed")
    cross_training_days: Optional[list[DayOfWeek]] = Field(None, description="Days for cross-training")
    running_days_per_week: int = Field(default=5, ge=1, le=7, description="Number of running days per week")
    gym_days_per_week: int = Field(default=2, ge=0, le=4, description="Number of gym/strength training days per week")
    cross_train_days_per_week: int = Field(default=0, ge=0, le=5, description="Number of dedicated cross-training session days per week")
    cross_train_modality: Optional[str] = Field(None, description="Cross-training modality, e.g. 'Peloton indoor cycling'")

    # Beginner / goal shaping
    goal_type: Optional[GoalType] = Field(None, description="race | finish | habit; habit means no race — race_date is the block end date")
    beginner_mode: bool = Field(default=False, description="True-beginner plan style: run/walk progression, effort over pace")

    # Equipment & preferences
    strength_equipment: Optional[str] = Field(None, description="Equipment available for strength sessions; only prescribe with these")
    training_notes: Optional[str] = Field(None, description="Free-form athlete preferences/habits the coach should honor")
    
    # Running History
    years_running: int = Field(..., ge=0, le=50, description="Years of running experience")
    previous_injuries: Optional[str] = Field(None, description="Any injury history or limitations")
    previous_experience: Optional[str] = Field(None, description="Previous experience at goal distance")
    
    # Plan Mode (set after conflict resolution)
    plan_mode: Optional[PlanMode] = Field(None, description="Plan generation mode chosen after conflict resolution")
    recommended_goal_time: Optional[str] = Field(None, description="Adjusted goal time if user accepts recommendation")

    @model_validator(mode="after")
    def validate_custom_distance(self):
        if self.race_type == RaceType.CUSTOM and not self.custom_distance_km:
            raise ValueError("custom_distance_km is required when race_type is Custom")
        return self

    class Config:
        json_schema_extra = {
            "example": {
                "race_type": "Marathon",
                "race_date": "2026-05-15",
                "race_name": "Boston Marathon",
                "goal_time": "3:30:00",
                "current_weekly_mileage": 56,
                "longest_recent_run": 22,
                "recent_race_times": "Half marathon: 1:42:00 (2 months ago)",
                "fitness_level": "intermediate",
                "start_date": "2026-02-01",
                "rest_days": ["Friday"],
                "long_run_day": "Sunday",
                "double_days_allowed": False,
                "cross_training_days": ["Wednesday"],
                "running_days_per_week": 5,
                "gym_days_per_week": 2,
                "years_running": 3,
                "previous_injuries": "Minor IT band issues in 2024, fully recovered",
                "previous_experience": "Completed one marathon in 4:15:00 two years ago"
            }
        }
