from pathlib import Path
from app.models.schemas import TrainingPlanRequest, RaceType, PlanMode
from app.services.conflict_analyzer import REQUIRED_BENCHMARKS
from datetime import timedelta


# Map race types to their specialized coach prompt files
RACE_TYPE_TO_COACH = {
    RaceType.FIVE_K: "coach_speed.txt",
    RaceType.TEN_K: "coach_speed.txt",
    RaceType.HALF_MARATHON: "coach_marathon.txt",
    RaceType.MARATHON: "coach_marathon.txt",
    RaceType.FIFTY_K: "coach_ultra.txt",
    RaceType.EIGHTY_K: "coach_ultra.txt",
    RaceType.HUNDRED_K: "coach_ultra.txt",
    RaceType.HUNDRED_SIXTY_K: "coach_ultra.txt",
    RaceType.HUNDRED_SIXTY_PLUS: "coach_ultra.txt",
}


class PromptBuilder:
    """Builds prompts for training plan generation."""
    
    def __init__(self):
        self._prompt_cache: dict[str, str] = {}
        self._prompts_dir = Path(__file__).parent.parent / "prompts"
    
    def _load_prompt(self, filename: str) -> str:
        """Load and cache a prompt file."""
        if filename not in self._prompt_cache:
            prompt_path = self._prompts_dir / filename
            self._prompt_cache[filename] = prompt_path.read_text(encoding="utf-8")
        return self._prompt_cache[filename]
    
    def get_system_prompt(self, race_type: RaceType) -> str:
        """
        Get the appropriate system prompt for the given race type.
        
        Args:
            race_type: The target race distance
            
        Returns:
            The specialized coaching system prompt
        """
        coach_file = RACE_TYPE_TO_COACH.get(race_type)
        if coach_file is None:
            # Fallback to marathon coach for unknown types
            coach_file = "coach_marathon.txt"
        return self._load_prompt(coach_file)
    
    @property
    def system_prompt(self) -> str:
        """
        Legacy property for backwards compatibility.
        Returns the marathon coach as default.
        
        Deprecated: Use get_system_prompt(race_type) instead.
        """
        return self._load_prompt("coach_marathon.txt")
    
    def build_user_prompt(self, request: TrainingPlanRequest) -> str:
        """
        Build the user prompt from the training plan request.
        
        Args:
            request: The validated training plan request
            
        Returns:
            A formatted prompt string with all athlete details
        """
        # Calculate training duration
        training_days = (request.race_date - request.start_date).days
        training_weeks = training_days // 7
        
        # Format rest days
        rest_days_str = ", ".join([d.value for d in request.rest_days]) if request.rest_days else "None specified"
        locked_rest_days_count = len(request.rest_days)
        
        # Calculate scheduling constraints
        available_days = 7 - locked_rest_days_count
        total_sessions = request.running_days_per_week + request.gym_days_per_week
        stacking_required = total_sessions > available_days
        
        # Build scheduling summary
        if locked_rest_days_count == 0:
            scheduling_summary = f"All 7 days available for training. {total_sessions} total sessions to schedule on separate days."
        elif stacking_required and request.double_days_allowed:
            sessions_to_stack = total_sessions - available_days
            gym_only_days = request.gym_days_per_week - sessions_to_stack
            scheduling_summary = (
                f"STACKING MINIMIZATION: With {request.running_days_per_week} runs and {request.gym_days_per_week} gym sessions in {available_days} available days, "
                f"place {gym_only_days} gym session(s) on non-run days first, then stack exactly {sessions_to_stack} gym session(s) onto easy run days. "
                f"Do NOT create extra rest days — use all {available_days} available days."
            )
        elif stacking_required and not request.double_days_allowed:
            # This shouldn't happen due to frontend validation, but handle defensively
            scheduling_summary = (
                f"WARNING: {total_sessions} sessions requested but only {available_days} days available. "
                f"Configuration may be invalid."
            )
        else:
            unused_days = available_days - total_sessions
            scheduling_summary = (
                f"{available_days} days available after {locked_rest_days_count} fixed rest day(s). "
                f"{total_sessions} total sessions to schedule on separate days — NO stacking needed. "
                f"{unused_days} day(s) will be additional rest days."
            )
        
        # Cross-training days are auto-selected by the coach
        cross_training_str = "Auto-select optimal days based on the training schedule"
        
        # Detect partial first week (start date is not Monday)
        start_day_name = request.start_date.strftime("%A")
        days_of_week = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        start_day_index = days_of_week.index(start_day_name) if start_day_name in days_of_week else 0
        is_partial_first_week = start_day_name != "Monday"
        days_in_first_week = 7 - start_day_index  # e.g., Saturday = index 5, so 2 days
        
        prompt = f"""
ATHLETE PROFILE AND TRAINING REQUEST
=====================================

GOAL INFORMATION
Race Distance: {request.race_type.value}
Race Date: {request.race_date.strftime("%A, %B %d, %Y")}
Race Name: {request.race_name or "Not specified"}
Goal Time: {request.goal_time or "Finish strong (no specific time goal)"}

TRAINING TIMELINE
Start Date: {request.start_date.strftime("%A, %B %d, %Y")}
Training Duration: {training_weeks} weeks ({training_days} days)

CURRENT FITNESS
Weekly Volume: {request.current_weekly_mileage} km per week
Longest Recent Run: {request.longest_recent_run} km (past 4 weeks)
Recent Race Times: {request.recent_race_times or "None provided"}
Recent Runs (Last 7-14 Days): {request.recent_runs or "None provided"}
Self-Assessed Level: {request.fitness_level.value.capitalize()}

SCHEDULE CONSTRAINTS
Running Days per Week: {request.running_days_per_week} days
Gym/Strength Sessions per Week: {request.gym_days_per_week} days
Fixed Rest Days: {rest_days_str}
Long Run Day: {request.long_run_day.value}
Double Days Allowed: {"Yes" if request.double_days_allowed else "No"}
Cross-Training Days: {cross_training_str}

SCHEDULING SUMMARY
Available Training Days: {available_days} (7 days minus {locked_rest_days_count} fixed rest days)
Total Sessions Required: {total_sessions} ({request.running_days_per_week} runs + {request.gym_days_per_week} gym)
Stacking Required: {"Yes — stack exactly " + str(total_sessions - available_days) + " gym session(s) onto easy run days" if stacking_required else "No — use separate days for all sessions"}
{scheduling_summary}
{"" if not is_partial_first_week else f"""
PARTIAL FIRST WEEK (MANDATORY)
The plan starts on {start_day_name}, NOT Monday. Week 1 is a PARTIAL week with only {days_in_first_week} day(s).
• Week 1 MUST ONLY include days from {start_day_name} through Sunday — do NOT output Monday through {days_of_week[start_day_index - 1] if start_day_index > 0 else "Sunday"} for Week 1
• Distribute a reduced training load appropriate for {days_in_first_week} day(s)
• Weekly volume for Week 1 should be proportionally reduced (roughly {days_in_first_week}/7 of a normal week)
• Full Monday-through-Sunday weeks begin from Week 2 onwards
• The week header for Week 1 should show the actual dates starting from {start_day_name}
"""}
RUNNING BACKGROUND
Years Running: {request.years_running} years
Previous Injuries/Limitations: {request.previous_injuries or "None reported"}
Previous Experience at Goal Distance: {request.previous_experience or "None"}

=====================================

Please create a complete, week-by-week training plan for this athlete.
Start the plan on {request.start_date.strftime("%A, %B %d, %Y")} and end with race week concluding on {request.race_date.strftime("%A, %B %d, %Y")}.
"""
        
        # Add plan mode instructions if specified
        mode_instructions = self._get_plan_mode_instructions(request)
        if mode_instructions:
            prompt += "\n\n" + mode_instructions
        
        return prompt.strip()
    
    def _get_plan_mode_instructions(self, request: TrainingPlanRequest) -> str:
        """
        Get additional instructions based on plan mode.
        
        Args:
            request: The training plan request with optional plan_mode
            
        Returns:
            Additional prompt instructions for the selected mode
        """
        if not request.plan_mode:
            return ""
        
        if request.plan_mode == PlanMode.AGGRESSIVE:
            goal_time = request.goal_time or "their stated goal"
            
            # Get required benchmarks for this race type
            benchmarks = REQUIRED_BENCHMARKS.get(request.race_type, {})
            peak_long_run = benchmarks.get("peak_long_run_km", 30)
            peak_volume = benchmarks.get("peak_weekly_volume_km", 75)
            
            return f"""
=====================================
ATHLETE OVERRIDE ACTIVE
=====================================

The athlete has reviewed the identified training considerations and CHOSEN TO PURSUE 
their original goal of {goal_time}.

AGGRESSIVE MODE INSTRUCTIONS:
• Build a progressive plan that starts at the athlete's current demonstrated fitness level
• Systematically build toward goal pace over the training block
• Include marathon-pace exposure in the final 4-6 weeks of training
• Prioritize the highest probability of success at the stated goal
• Still respect injury prevention principles but push the training appropriately
• Do NOT water down the plan or suggest easier alternatives
• The athlete understands the challenge and wants to train for their goal

MANDATORY TRAINING BENCHMARKS (NON-NEGOTIABLE):
• Peak long run MUST reach at least {peak_long_run} km before taper begins
• Peak weekly volume should approach {peak_volume} km during the highest volume weeks
• Progression may be compressed (more aggressive week-to-week increases) to hit these benchmarks
• If the timeline requires faster progression than 10%/week, use up to 15%/week for long runs
• These benchmarks are REQUIRED for race readiness — do NOT reduce them
• A plan that fails to reach the {peak_long_run} km peak long run is INVALID

The athlete is competitive and has made an informed decision to pursue this goal.
Build the strongest possible plan to give them the best chance of achieving it.
The plan MUST hit the required training benchmarks even if progression is aggressive.
"""
        
        elif request.plan_mode == PlanMode.RECOMMENDED:
            adjusted_goal = request.recommended_goal_time or request.goal_time
            return f"""
=====================================
ADJUSTED GOAL APPROACH
=====================================

The athlete has reviewed the training considerations and accepted the recommended 
adjusted goal of {adjusted_goal}.

RECOMMENDED MODE INSTRUCTIONS:
• Build the plan around the adjusted goal time of {adjusted_goal}
• Prioritize consistency, health, and sustainable progression
• Use conservative pacing that matches current fitness
• Focus on building the aerobic base thoroughly before race-specific work
• The athlete may exceed this goal on race day, but training should be calibrated here
• Include appropriate marathon-pace work based on the adjusted goal
"""
        
        return ""


# Singleton instance
prompt_builder = PromptBuilder()
