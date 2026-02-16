"""
Conflict Analyzer Service

Analyzes training plan requests to detect conflicts between user goals
and their current fitness level, injury history, timeline, and volume.
"""

import math
import re
from datetime import date
from app.models.schemas import (
    TrainingPlanRequest,
    RaceType,
    FitnessLevel,
    ConflictType,
    RiskLevel,
    DetectedConflict,
    ConflictAnalysisResponse,
)


# Known distance→value curves for interpolation
# Sorted by distance in km
_DISTANCE_CURVE = [
    (5.0, "5K"),
    (10.0, "10K"),
    (21.1, "HM"),
    (42.195, "M"),
    (50.0, "50K"),
    (80.0, "80K"),
    (100.0, "100K"),
    (160.0, "160K"),
    (200.0, "160+"),
]

# Race distances in km for standard types
RACE_DISTANCES = {
    RaceType.FIVE_K: 5.0,
    RaceType.TEN_K: 10.0,
    RaceType.HALF_MARATHON: 21.1,
    RaceType.MARATHON: 42.195,
}

# Known distance→value data for interpolation
_MIN_WEEKS_CURVE = [
    (5.0, 6), (10.0, 8), (21.1, 10), (42.195, 12),
    (50.0, 14), (80.0, 16), (100.0, 18), (160.0, 20), (200.0, 24),
]

_MIN_VOLUME_CURVE = [
    (5.0, 25), (10.0, 30), (21.1, 40), (42.195, 50),
    (50.0, 60), (80.0, 70), (100.0, 80), (160.0, 90), (200.0, 100),
]

_PEAK_LONG_RUN_CURVE = [
    (5.0, 12), (10.0, 16), (21.1, 20), (42.195, 30),
    (50.0, 40), (80.0, 50), (100.0, 55), (160.0, 60), (200.0, 65),
]

_PEAK_VOLUME_CURVE = [
    (5.0, 30), (10.0, 40), (21.1, 50), (42.195, 75),
    (50.0, 90), (80.0, 100), (100.0, 110), (160.0, 120), (200.0, 130),
]


def _interpolate(curve: list[tuple[float, float]], distance_km: float) -> float:
    """Linearly interpolate a value from a sorted (distance, value) curve."""
    if distance_km <= curve[0][0]:
        return curve[0][1]
    if distance_km >= curve[-1][0]:
        return curve[-1][1]
    for i in range(len(curve) - 1):
        d0, v0 = curve[i]
        d1, v1 = curve[i + 1]
        if d0 <= distance_km <= d1:
            t = (distance_km - d0) / (d1 - d0)
            return v0 + t * (v1 - v0)
    return curve[-1][1]


def get_race_distance_km(request: TrainingPlanRequest) -> float:
    """Get the effective race distance in km from a request."""
    if request.race_type == RaceType.CUSTOM:
        return request.custom_distance_km or 42.195
    return RACE_DISTANCES.get(request.race_type, 42.195)


def get_min_training_weeks(request: TrainingPlanRequest) -> int:
    """Get minimum recommended training weeks for a request."""
    km = get_race_distance_km(request)
    return round(_interpolate(_MIN_WEEKS_CURVE, km))


def get_min_volume_for_aggressive(request: TrainingPlanRequest) -> int:
    """Get minimum volume for aggressive goals for a request."""
    km = get_race_distance_km(request)
    return round(_interpolate(_MIN_VOLUME_CURVE, km))


def get_required_benchmarks(request: TrainingPlanRequest) -> dict:
    """Get required training benchmarks for a request."""
    km = get_race_distance_km(request)
    return {
        "peak_long_run_km": round(_interpolate(_PEAK_LONG_RUN_CURVE, km)),
        "peak_weekly_volume_km": round(_interpolate(_PEAK_VOLUME_CURVE, km)),
    }


# Legacy dict for prompt_builder REQUIRED_BENCHMARKS import
REQUIRED_BENCHMARKS = {
    RaceType.FIVE_K: {"peak_long_run_km": 12, "peak_weekly_volume_km": 30},
    RaceType.TEN_K: {"peak_long_run_km": 16, "peak_weekly_volume_km": 40},
    RaceType.HALF_MARATHON: {"peak_long_run_km": 20, "peak_weekly_volume_km": 50},
    RaceType.MARATHON: {"peak_long_run_km": 30, "peak_weekly_volume_km": 75},
}


def parse_time_to_seconds(time_str: str) -> int | None:
    """
    Parse a time string (e.g., '3:30:00', '1:45:00', '45:00') to total seconds.
    Returns None if parsing fails.
    """
    if not time_str:
        return None
    
    # Clean up the string
    time_str = time_str.strip()
    
    # Try H:MM:SS format
    match = re.match(r'^(\d+):(\d{1,2}):(\d{2})$', time_str)
    if match:
        hours, minutes, seconds = map(int, match.groups())
        return hours * 3600 + minutes * 60 + seconds
    
    # Try M:SS or MM:SS format (for shorter races)
    match = re.match(r'^(\d{1,2}):(\d{2})$', time_str)
    if match:
        minutes, seconds = map(int, match.groups())
        return minutes * 60 + seconds
    
    return None


def seconds_to_time_str(seconds: int) -> str:
    """Convert seconds back to H:MM:SS format."""
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    secs = seconds % 60
    return f"{hours}:{minutes:02d}:{secs:02d}"


def calculate_pace_per_km(time_seconds: int, distance_km: float) -> float:
    """Calculate pace in seconds per km."""
    if distance_km <= 0:
        return 0
    return time_seconds / distance_km


def format_pace(seconds_per_km: float) -> str:
    """Format pace as M:SS/km."""
    minutes = int(seconds_per_km // 60)
    secs = int(seconds_per_km % 60)
    return f"{minutes}:{secs:02d}/km"


def estimate_marathon_time_from_half(half_time_seconds: int) -> int:
    """
    Estimate marathon time from half marathon time.
    Uses a multiplier of ~2.1 to account for fatigue.
    """
    return int(half_time_seconds * 2.1)


def estimate_reasonable_goal_time(request: TrainingPlanRequest) -> str | None:
    """
    Estimate a reasonable goal time based on recent race performances.
    Returns None if not enough data.
    """
    if not request.recent_race_times:
        return None
    
    race_text = request.recent_race_times.lower()
    race_distance = get_race_distance_km(request)
    
    # Try to extract half marathon time
    half_match = re.search(r'half[- ]?marathon[:\s]*(\d+:\d+:\d+|\d+:\d+)', race_text)
    if half_match and request.race_type == RaceType.MARATHON:
        half_time = parse_time_to_seconds(half_match.group(1))
        if half_time:
            estimated = estimate_marathon_time_from_half(half_time)
            return seconds_to_time_str(estimated)
    
    # Try to find any time mention and extrapolate
    time_match = re.search(r'(\d+:\d+:\d+)', race_text)
    if time_match:
        return time_match.group(1)
    
    return None


def add_time_buffer(time_str: str, buffer_percent: float = 0.1) -> str:
    """Add a buffer percentage to a time (e.g., 10% slower)."""
    seconds = parse_time_to_seconds(time_str)
    if seconds:
        adjusted = int(seconds * (1 + buffer_percent))
        return seconds_to_time_str(adjusted)
    return time_str


class ConflictAnalyzer:
    """Analyzes training plan requests for potential conflicts."""
    
    def analyze(self, request: TrainingPlanRequest) -> ConflictAnalysisResponse:
        """
        Analyze a training plan request for conflicts.
        
        Returns a ConflictAnalysisResponse with detected conflicts and recommendations.
        """
        conflicts: list[DetectedConflict] = []
        
        # Check each type of conflict
        goal_conflict = self._check_goal_vs_fitness(request)
        if goal_conflict:
            conflicts.append(goal_conflict)
        
        injury_conflict = self._check_injury_risk(request)
        if injury_conflict:
            conflicts.append(injury_conflict)
        
        timeline_conflict = self._check_timeline_pressure(request)
        if timeline_conflict:
            conflicts.append(timeline_conflict)
        
        volume_conflict = self._check_volume_insufficient(request)
        if volume_conflict:
            conflicts.append(volume_conflict)
        
        benchmarks_conflict = self._check_benchmarks_reachable(request)
        if benchmarks_conflict:
            conflicts.append(benchmarks_conflict)
        
        # Calculate recommended goal time
        recommended_goal = self._calculate_recommended_goal(request, conflicts)
        
        # Build summary
        summary = self._build_summary(conflicts, request.goal_time, recommended_goal)
        
        return ConflictAnalysisResponse(
            has_conflicts=len(conflicts) > 0,
            conflicts=conflicts,
            original_goal_time=request.goal_time,
            recommended_goal_time=recommended_goal,
            recommendation_summary=summary,
        )
    
    def _check_goal_vs_fitness(self, request: TrainingPlanRequest) -> DetectedConflict | None:
        """Check if goal pace is significantly faster than current fitness indicates."""
        if not request.goal_time or not request.recent_race_times:
            return None
        
        goal_seconds = parse_time_to_seconds(request.goal_time)
        if not goal_seconds:
            return None

        race_distance = get_race_distance_km(request)
        goal_pace = calculate_pace_per_km(goal_seconds, race_distance)

        # Try to estimate current fitness from recent races
        estimated_time = estimate_reasonable_goal_time(request)
        if not estimated_time:
            return None

        estimated_seconds = parse_time_to_seconds(estimated_time)
        if not estimated_seconds:
            return None

        estimated_pace = calculate_pace_per_km(estimated_seconds, race_distance)
        
        # Check if goal pace is >15% faster than estimated
        pace_diff_percent = (estimated_pace - goal_pace) / estimated_pace * 100
        
        if pace_diff_percent > 15:
            return DetectedConflict(
                conflict_type=ConflictType.GOAL_VS_FITNESS,
                risk_level=RiskLevel.HIGH if pace_diff_percent > 25 else RiskLevel.MEDIUM,
                title="Ambitious Goal Pace",
                description=(
                    f"Your goal pace of {format_pace(goal_pace)} is {pace_diff_percent:.0f}% faster than "
                    f"what your recent race performances suggest ({format_pace(estimated_pace)}). "
                    f"This is an ambitious target that may require significant fitness gains."
                ),
                recommendation=(
                    f"Based on your recent performances, a more achievable goal would be around "
                    f"{estimated_time}. You can still train toward your original goal, but "
                    f"expectations should be calibrated."
                ),
            )
        
        return None
    
    def _check_injury_risk(self, request: TrainingPlanRequest) -> DetectedConflict | None:
        """Check for injury history combined with aggressive goals."""
        if not request.previous_injuries:
            return None
        
        injuries = request.previous_injuries.lower()
        
        # Keywords that indicate significant injury history
        high_risk_keywords = ['stress fracture', 'surgery', 'chronic', 'recurring', 'tendon']
        medium_risk_keywords = ['it band', 'plantar', 'achilles', 'shin splint', 'knee']
        
        has_high_risk = any(kw in injuries for kw in high_risk_keywords)
        has_medium_risk = any(kw in injuries for kw in medium_risk_keywords)
        
        # Only flag if there's also an aggressive goal
        is_aggressive = False
        if request.goal_time:
            goal_seconds = parse_time_to_seconds(request.goal_time)
            if goal_seconds and request.race_type == RaceType.MARATHON:
                # Sub-3:30 marathon is aggressive with injury history
                is_aggressive = goal_seconds < 3.5 * 3600
            elif goal_seconds and request.race_type == RaceType.HALF_MARATHON:
                # Sub-1:45 half is aggressive with injury history
                is_aggressive = goal_seconds < 1.75 * 3600
        
        if not is_aggressive:
            return None
        
        if has_high_risk:
            return DetectedConflict(
                conflict_type=ConflictType.INJURY_RISK,
                risk_level=RiskLevel.HIGH,
                title="Injury History Concern",
                description=(
                    f"You've reported significant injury history ({request.previous_injuries}). "
                    f"Pursuing an aggressive time goal increases re-injury risk."
                ),
                recommendation=(
                    "Consider a more conservative goal that prioritizes consistent training "
                    "and healthy completion. You can always negative split and exceed expectations on race day."
                ),
            )
        elif has_medium_risk:
            return DetectedConflict(
                conflict_type=ConflictType.INJURY_RISK,
                risk_level=RiskLevel.MEDIUM,
                title="Injury History Noted",
                description=(
                    f"You've reported injury history ({request.previous_injuries}). "
                    f"High-intensity training toward an aggressive goal may increase risk."
                ),
                recommendation=(
                    "The plan will include marathon-pace work, but we recommend extra attention "
                    "to recovery and being willing to adjust if warning signs appear."
                ),
            )
        
        return None
    
    def _check_timeline_pressure(self, request: TrainingPlanRequest) -> DetectedConflict | None:
        """Check if training timeline is too short for the goal distance."""
        training_days = (request.race_date - request.start_date).days
        training_weeks = training_days // 7
        
        min_weeks = get_min_training_weeks(request)
        
        if training_weeks < min_weeks:
            is_severe = training_weeks < min_weeks * 0.7
            
            return DetectedConflict(
                conflict_type=ConflictType.TIMELINE_PRESSURE,
                risk_level=RiskLevel.HIGH if is_severe else RiskLevel.MEDIUM,
                title="Compressed Training Timeline",
                description=(
                    f"You have {training_weeks} weeks to train for a {request.race_type.value}. "
                    f"We typically recommend at least {min_weeks} weeks for optimal preparation."
                ),
                recommendation=(
                    "With a shorter timeline, we'll need to be strategic about progression. "
                    "Consider focusing on completion rather than a time goal, or look for "
                    "a later race if achieving a specific time is important."
                ),
            )
        
        return None
    
    def _check_volume_insufficient(self, request: TrainingPlanRequest) -> DetectedConflict | None:
        """Check if current weekly volume is too low for an aggressive goal."""
        min_volume = get_min_volume_for_aggressive(request)
        
        # Only flag if there's an aggressive time goal
        if not request.goal_time:
            return None
        
        # Check if goal implies aggressive training
        goal_seconds = parse_time_to_seconds(request.goal_time)
        if not goal_seconds:
            return None
        
        race_distance = get_race_distance_km(request)
        goal_pace = calculate_pace_per_km(goal_seconds, race_distance)

        # Sub-5:00/km pace for marathon is aggressive
        is_aggressive_pace = goal_pace < 300  # 5:00/km in seconds
        
        if request.current_weekly_mileage < min_volume and is_aggressive_pace:
            return DetectedConflict(
                conflict_type=ConflictType.VOLUME_INSUFFICIENT,
                risk_level=RiskLevel.MEDIUM,
                title="Volume Build Required",
                description=(
                    f"Your current weekly volume of {request.current_weekly_mileage} km is below the "
                    f"{min_volume} km typically needed to support marathon-pace training for your goal."
                ),
                recommendation=(
                    "The plan will prioritize building your aerobic base before introducing "
                    "race-specific work. Marathon-pace sessions may be limited until volume improves."
                ),
            )
        
        return None
    
    def _check_benchmarks_reachable(self, request: TrainingPlanRequest) -> DetectedConflict | None:
        """
        Check if required training benchmarks (peak long run, volume) are reachable 
        within the available timeline using safe progression (10% weekly increase).
        """
        benchmarks = get_required_benchmarks(request)
        
        required_peak_long_run = benchmarks["peak_long_run_km"]
        current_long_run = request.longest_recent_run
        
        # If already at or above required benchmark, no conflict
        if current_long_run >= required_peak_long_run:
            return None
        
        # Ensure we have a minimum starting point for calculation
        # (avoid division by zero or log of zero)
        current_long_run = max(current_long_run, 5)
        
        # Calculate weeks needed using 10% weekly progression rule
        # weeks_needed = ceil(log(target / current) / log(1.10))
        weeks_for_long_run = math.ceil(
            math.log(required_peak_long_run / current_long_run) / math.log(1.10)
        )
        
        # Add recovery weeks (1 down week every 3 build weeks)
        recovery_weeks = weeks_for_long_run // 3
        total_weeks_needed = weeks_for_long_run + recovery_weeks
        
        # Add 2 weeks for taper (marathon and longer distances)
        race_km = get_race_distance_km(request)
        if race_km >= 42.0:
            total_weeks_needed += 2
        elif race_km >= 15.0:
            total_weeks_needed += 1
        
        # Calculate available training weeks
        training_days = (request.race_date - request.start_date).days
        available_weeks = training_days // 7
        
        # Check if we have enough time
        if available_weeks >= total_weeks_needed:
            return None
        
        # Calculate the deficit
        weeks_short = total_weeks_needed - available_weeks
        
        # Determine risk level based on how compressed the timeline would need to be
        compression_ratio = available_weeks / total_weeks_needed if total_weeks_needed > 0 else 0
        if compression_ratio < 0.6:
            risk_level = RiskLevel.HIGH
        elif compression_ratio < 0.8:
            risk_level = RiskLevel.MEDIUM
        else:
            risk_level = RiskLevel.LOW
        
        # Build specific messaging
        race_km = get_race_distance_km(request)
        race_name = f"{race_km:.0f} km" if request.race_type == RaceType.CUSTOM else request.race_type.value
        
        return DetectedConflict(
            conflict_type=ConflictType.BENCHMARKS_UNREACHABLE,
            risk_level=risk_level,
            title="Training Benchmarks May Not Be Reached Safely",
            description=(
                f"To properly prepare for a {race_name}, you need peak long runs of "
                f"{required_peak_long_run} km. From your current longest run of {request.longest_recent_run} km, "
                f"this requires approximately {total_weeks_needed} weeks of safe progression "
                f"(10% weekly increase with recovery weeks). You have {available_weeks} weeks available, "
                f"which is {weeks_short} week(s) short."
            ),
            recommendation=(
                f"Options: (1) Accept a more aggressive progression that still hits the required "
                f"{required_peak_long_run} km peak long run, (2) adjust your goal to focus on completion "
                f"rather than a time target, or (3) find a later race with more preparation time. "
                f"If you proceed, the plan will compress progression to still reach required benchmarks."
            ),
        )
    
    def _calculate_recommended_goal(
        self, 
        request: TrainingPlanRequest, 
        conflicts: list[DetectedConflict]
    ) -> str | None:
        """Calculate a recommended goal time based on conflicts."""
        if not request.goal_time:
            return None
        
        if not conflicts:
            return request.goal_time
        
        # Check if we have a fitness-based estimate
        estimated = estimate_reasonable_goal_time(request)
        if estimated:
            return estimated
        
        # Otherwise, add a buffer to the original goal based on conflict severity
        high_risk_count = sum(1 for c in conflicts if c.risk_level == RiskLevel.HIGH)
        medium_risk_count = sum(1 for c in conflicts if c.risk_level == RiskLevel.MEDIUM)
        
        # Calculate buffer: 10% for each high risk, 5% for each medium
        buffer = high_risk_count * 0.10 + medium_risk_count * 0.05
        buffer = min(buffer, 0.25)  # Cap at 25%
        
        if buffer > 0:
            return add_time_buffer(request.goal_time, buffer)
        
        return request.goal_time
    
    def _build_summary(
        self, 
        conflicts: list[DetectedConflict], 
        original_goal: str | None,
        recommended_goal: str | None
    ) -> str | None:
        """Build a summary of the conflict analysis."""
        if not conflicts:
            return None
        
        high_count = sum(1 for c in conflicts if c.risk_level == RiskLevel.HIGH)
        medium_count = sum(1 for c in conflicts if c.risk_level == RiskLevel.MEDIUM)
        
        if high_count > 0:
            severity = "significant"
        elif medium_count > 1:
            severity = "moderate"
        else:
            severity = "minor"
        
        goal_comparison = ""
        if original_goal and recommended_goal and original_goal != recommended_goal:
            goal_comparison = (
                f" Based on your profile, we recommend adjusting your target from "
                f"{original_goal} to {recommended_goal}."
            )
        
        return (
            f"We've identified {len(conflicts)} {severity} consideration(s) that may affect "
            f"your training plan.{goal_comparison} You can choose to override these "
            f"recommendations and train for your original goal, or accept our adjusted approach."
        )


# Singleton instance
conflict_analyzer = ConflictAnalyzer()
