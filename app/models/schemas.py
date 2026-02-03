from pydantic import BaseModel, Field
from typing import Optional
from datetime import date
from enum import Enum


class RaceType(str, Enum):
    """Supported race distances."""
    FIVE_K = "5K"
    TEN_K = "10K"
    HALF_MARATHON = "Half Marathon"
    MARATHON = "Marathon"
    FIFTY_K = "50K"
    EIGHTY_K = "80K"
    HUNDRED_K = "100K"
    HUNDRED_SIXTY_K = "160K"
    HUNDRED_SIXTY_PLUS = "160+ km"


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


class TrainingPlanRequest(BaseModel):
    """Request schema for training plan generation."""
    
    # Goal Information
    race_type: RaceType = Field(..., description="Target race distance")
    race_date: date = Field(..., description="Date of the goal race")
    race_name: Optional[str] = Field(None, description="Name of the race (optional)")
    goal_time: Optional[str] = Field(None, description="Target finish time (optional)")
    
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
    running_days_per_week: int = Field(default=5, ge=3, le=7, description="Number of running days per week")
    gym_days_per_week: int = Field(default=2, ge=0, le=4, description="Number of gym/strength training days per week")
    
    # Running History
    years_running: int = Field(..., ge=0, le=50, description="Years of running experience")
    previous_injuries: Optional[str] = Field(None, description="Any injury history or limitations")
    previous_experience: Optional[str] = Field(None, description="Previous experience at goal distance")
    
    # Plan Mode (set after conflict resolution)
    plan_mode: Optional[PlanMode] = Field(None, description="Plan generation mode chosen after conflict resolution")
    recommended_goal_time: Optional[str] = Field(None, description="Adjusted goal time if user accepts recommendation")

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
