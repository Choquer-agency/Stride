import hashlib
from pathlib import Path
from app.models.schemas import TrainingPlanRequest, PlanEditRequest, PerformanceAnalysisRequest, RaceType, PlanMode, GoalType
from app.services.conflict_analyzer import REQUIRED_BENCHMARKS, get_required_benchmarks
from datetime import date, timedelta

# Shared coaching foundation (voice, units, safety) prepended to every coaching prompt.
FOUNDATION_PROMPT = "_coach_foundation.txt"
PLAN_QUALITY_PROMPT = "_plan_quality_contract.txt"
# Plan-building framework (reasoning frame, training vocabulary, periodization,
# pace-zone derivation, output standards). Composed for plan generation/editing only.
PLAN_CORE_PROMPT = "coach_plan_core.txt"


def get_coach_file(race_type: RaceType, custom_distance_km: float | None = None, beginner_mode: bool = False) -> str:
    """Route to the correct race-specific module based on race type and custom distance."""
    if beginner_mode:
        # True-beginner plans replace the race module entirely — race_type may be
        # a synthetic placeholder for habit-building blocks.
        return "race/beginner.txt"
    if race_type != RaceType.CUSTOM:
        return {
            RaceType.FIVE_K: "race/speed.txt",
            RaceType.TEN_K: "race/speed.txt",
            RaceType.HALF_MARATHON: "race/half.txt",
            RaceType.MARATHON: "race/marathon.txt",
        }.get(race_type, "race/marathon.txt")
    # Custom: route by distance
    km = custom_distance_km or 42.195
    if km >= 50:
        return "race/ultra.txt"
    if km >= 35:
        return "race/marathon.txt"
    if km >= 15:
        return "race/half.txt"
    return "race/speed.txt"


class PromptBuilder:
    """Builds prompts for training plan generation and coaching loops."""

    def __init__(self):
        self._prompt_cache: dict[str, str] = {}
        self._sha_cache: dict[str, str] = {}
        self._prompts_dir = Path(__file__).parent.parent / "prompts"

    def _load_prompt(self, filename: str) -> str:
        """Load and cache a prompt file."""
        if filename not in self._prompt_cache:
            prompt_path = self._prompts_dir / filename
            self._prompt_cache[filename] = prompt_path.read_text(encoding="utf-8")
        return self._prompt_cache[filename]

    def compose(self, *filenames: str) -> str:
        """Concatenate multiple prompt fragments with `\\n\\n` separators."""
        return "\n\n".join(self._load_prompt(f) for f in filenames)

    def prompt_sha(self, filename: str) -> str:
        """
        Return a 6-char sha256 prefix of the prompt file's current contents.
        Used for `coaching_events.prompt_used` versioning.
        """
        if filename not in self._sha_cache:
            content = self._load_prompt(filename)
            self._sha_cache[filename] = hashlib.sha256(content.encode("utf-8")).hexdigest()[:6]
        return self._sha_cache[filename]

    def _coaching_prompt(
        self,
        behavior_filename: str,
        race_type: RaceType | None = None,
        custom_distance_km: float | None = None,
        memo: str = "",
    ) -> str:
        """
        Compose a full coaching prompt:
            foundation + race-specific persona (if applicable) + memo block + behavior instructions.

        Args:
            behavior_filename: e.g. "coach_weekly_review.txt"
            race_type: Athlete's target race; if provided, race-specific coach is included
            custom_distance_km: For Custom race types
            memo: Pre-loaded coach memo content. Empty string skips the memo block.
        """
        parts: list[str] = [self._load_prompt(FOUNDATION_PROMPT)]
        if race_type is not None:
            coach_file = get_coach_file(race_type, custom_distance_km)
            parts.append(self._load_prompt(coach_file))
        if memo:
            parts.append(f"## What you know about this athlete\n\n{memo}")
        parts.append(self._load_prompt(behavior_filename))
        return "\n\n".join(parts)
    
    def get_system_prompt(self, race_type: RaceType, custom_distance_km: float | None = None, beginner_mode: bool = False) -> str:
        """
        System prompt for plan generation:
        coach voice + plan-building framework + race module + quality contract.
        """
        coach_file = get_coach_file(race_type, custom_distance_km, beginner_mode)
        return self.compose(FOUNDATION_PROMPT, PLAN_CORE_PROMPT, coach_file, PLAN_QUALITY_PROMPT)
    
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
        # Count calendar rows the model must output, including partial first/final weeks.
        training_weeks = max(1, (training_days + 6) // 7)
        
        # Format rest days
        rest_days_str = ", ".join([d.value for d in request.rest_days]) if request.rest_days else "None specified"
        locked_rest_days_count = len(request.rest_days)
        
        # Calculate scheduling constraints
        ride_days = request.cross_train_days_per_week
        available_days = 7 - locked_rest_days_count
        total_sessions = request.running_days_per_week + request.gym_days_per_week + ride_days
        stacking_required = total_sessions > available_days

        # Human-readable session breakdowns; both omit rides entirely when none are
        # requested so existing (ride-free) prompts remain byte-identical.
        session_breakdown = f"{request.running_days_per_week} runs + {request.gym_days_per_week} gym"
        stacking_prose = f"{request.running_days_per_week} runs and {request.gym_days_per_week} gym sessions"
        if ride_days > 0:
            session_breakdown += f" + {ride_days} rides"
            stacking_prose = f"{request.running_days_per_week} runs, {request.gym_days_per_week} gym sessions, and {ride_days} rides"

        # Build scheduling summary
        if locked_rest_days_count == 0:
            scheduling_summary = f"All 7 days available for training. {total_sessions} total sessions to schedule on separate days."
        elif stacking_required and request.double_days_allowed:
            sessions_to_stack = total_sessions - available_days
            gym_only_days = request.gym_days_per_week - sessions_to_stack
            scheduling_summary = (
                f"STACKING MINIMIZATION: With {stacking_prose} in {available_days} available days, "
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
        if ride_days > 0:
            modality = request.cross_train_modality or "indoor cycling"
            cross_training_str = (
                f"{ride_days} ride(s) per week ({modality}) — schedule each as a dedicated "
                f"session day, never on a locked rest day"
            )
        else:
            cross_training_str = "Auto-select optimal days based on the training schedule"
        
        # Detect partial first week (start date is not Monday)
        start_day_name = request.start_date.strftime("%A")
        days_of_week = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        start_day_index = days_of_week.index(start_day_name) if start_day_name in days_of_week else 0
        is_partial_first_week = start_day_name != "Monday"
        days_in_first_week = 7 - start_day_index  # e.g., Saturday = index 5, so 2 days
        
        # Build race distance string
        if request.race_type == RaceType.CUSTOM and request.custom_distance_km:
            race_distance_str = f"{request.custom_distance_km} km (Custom)"
        else:
            race_distance_str = request.race_type.value

        # Build terrain block
        terrain_block = ""
        if request.terrain_type or request.elevation_gain_m:
            terrain_lines = ["\nTERRAIN & ELEVATION"]
            if request.terrain_type:
                terrain_lines.append(f"Terrain Type: {request.terrain_type.value.capitalize()}")
            if request.elevation_gain_m is not None:
                terrain_lines.append(f"Total Elevation Gain: {request.elevation_gain_m} meters")
            terrain_block = "\n".join(terrain_lines)

        # Beginner plan style rider on the fitness section
        beginner_style_line = ""
        if request.beginner_mode:
            beginner_style_line = (
                "\nPlan Style: TRUE BEGINNER — use run/walk progressions and effort language "
                "(conversational, comfortable) instead of pace targets."
            )

        # Equipment & preferences block
        equipment_block = ""
        if request.strength_equipment or request.training_notes:
            # Leading blank line separates the section when appended inline after
            # the Cross-Training Days line; empty block leaves the template untouched.
            eq_lines = ["\n\nEQUIPMENT AND PREFERENCES"]
            if request.strength_equipment:
                eq_lines.append(f"Strength Equipment Available: {request.strength_equipment}")
                eq_lines.append("Only prescribe strength work using the listed equipment — nothing else.")
            if request.training_notes:
                eq_lines.append(f"Athlete Notes: {request.training_notes}")
            equipment_block = "\n".join(eq_lines)

        # Build the goal section. Habit blocks have NO race — race_date is repurposed
        # as the block end date and the race fields are omitted entirely.
        is_habit = request.goal_type == GoalType.HABIT
        if is_habit:
            goal_section = f"""GOAL INFORMATION
Goal: Build a consistent running habit (NO RACE)
Plan End Date: {request.race_date.strftime("%A, %B %d, %Y")}
There is no race. Never schedule a race day or a taper. End the plan with a
celebration/benchmark week that lets the athlete see how far they've come."""
        else:
            if request.goal_type == GoalType.FINISH:
                goal_time_str = "Completion — finish the distance, no time goal"
            else:
                goal_time_str = request.goal_time or "Finish strong (no specific time goal)"
            goal_section = f"""GOAL INFORMATION
Race Distance: {race_distance_str}
Race Date: {request.race_date.strftime("%A, %B %d, %Y")}
Race Name: {request.race_name or "Not specified"}
Goal Time: {goal_time_str}"""

        prompt = f"""
ATHLETE PROFILE AND TRAINING REQUEST
=====================================

{goal_section}
{terrain_block}

TRAINING TIMELINE
Start Date: {request.start_date.strftime("%A, %B %d, %Y")}
Training Duration: {training_weeks} weeks ({training_days} days)

CURRENT FITNESS
Weekly Volume: {request.current_weekly_mileage} km per week
Longest Recent Run: {request.longest_recent_run} km (past 4 weeks)
Recent Race Times: {request.recent_race_times or "None provided"}
Recent Runs (Last 7-14 Days): {request.recent_runs or "None provided"}
Self-Assessed Level: {request.fitness_level.value.capitalize()}{beginner_style_line}

SCHEDULE CONSTRAINTS
Running Days per Week: {request.running_days_per_week} days
Gym/Strength Sessions per Week: {request.gym_days_per_week} days
Fixed Rest Days: {rest_days_str}
Long Run Day: {request.long_run_day.value}
Double Days Allowed: {"Yes" if request.double_days_allowed else "No"}
Cross-Training Days: {cross_training_str}{equipment_block}

SCHEDULING SUMMARY
Available Training Days: {available_days} (7 days minus {locked_rest_days_count} fixed rest days)
Total Sessions Required: {total_sessions} ({session_breakdown})
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
Start the plan on {request.start_date.strftime("%A, %B %d, %Y")} and end with {"a celebration/benchmark week (NO race)" if is_habit else "race week"} concluding on {request.race_date.strftime("%A, %B %d, %Y")}.
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
            benchmarks = get_required_benchmarks(request)
            peak_long_run = benchmarks.get("peak_long_run_km", 30)
            peak_volume = benchmarks.get("peak_weekly_volume_km", 75)
            
            return f"""
=====================================
ATHLETE OVERRIDE ACTIVE
=====================================

The athlete has reviewed the identified training considerations and CHOSEN TO PURSUE 
their original goal of {goal_time}.

AMBITIOUS MODE INSTRUCTIONS:
• Start from the athlete's demonstrated fitness, not the fitness implied by the goal
• Progress toward goal-specific work only as the available timeline and background support
• Include race-pace exposure appropriate to this race distance and demonstrated readiness
• Prioritize the highest probability of arriving healthy enough to race well
• Be direct when the original target remains a reach; ambition does not override safety
• The athlete understands the challenge and wants to train for their goal

READINESS REFERENCES (ASPIRATIONAL, NOT FORCED):
• A well-prepared athlete for this goal may peak near a {peak_long_run} km long run
• A well-prepared athlete may approach {peak_volume} km in the highest-volume week
• Reach these only when progression from current training is coherent and recoverable
• If either reference is not safely reachable, say so plainly and prescribe the best
  achievable preparation rather than manufacturing a dangerous progression

The athlete is competitive and has made an informed decision to pursue this goal.
Build the strongest possible plan to give them the best chance of achieving it.
Do not confuse "strongest" with "most volume"; specificity, consistency, and recovery matter.
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
• Use evidence-based pacing that matches current fitness
• Focus on building the aerobic base thoroughly before race-specific work
• The athlete may exceed this goal on race day, but training should be calibrated here
• Include race-specific pace work appropriate to the event and adjusted goal
"""
        
        return ""

    def get_analysis_system_prompt(self, race_type: RaceType, custom_distance_km: float | None = None) -> str:
        """
        Performance analysis: voice + race module + analysis behavior.

        Deliberately excludes _plan_quality_contract.txt — the contract's
        parser-safe output rules describe plan documents and would conflict with
        the analysis prose format. coach_analysis.txt carries the structural
        invariants an analysis must respect.
        """
        coach_file = get_coach_file(race_type, custom_distance_km)
        return self.compose(FOUNDATION_PROMPT, coach_file, "coach_analysis.txt")

    def build_analysis_user_prompt(self, request: PerformanceAnalysisRequest) -> str:
        """
        Build the user prompt for performance analysis.

        Formats plan metadata and completed workout data as structured text.
        """
        # Format completed workouts
        workout_lines = []
        for w in request.completed_workouts:
            parts = [f"Date: {w.date}", f"Type: {w.workout_type}"]
            if w.planned_distance_km is not None:
                parts.append(f"Planned: {w.planned_distance_km} km")
            if w.actual_distance_km is not None:
                parts.append(f"Actual: {w.actual_distance_km} km")
            if w.planned_pace_description:
                parts.append(f"Planned pace: {w.planned_pace_description}")
            if w.actual_avg_pace_sec_per_km is not None:
                mins = int(w.actual_avg_pace_sec_per_km) // 60
                secs = int(w.actual_avg_pace_sec_per_km) % 60
                parts.append(f"Actual pace: {mins}:{secs:02d} /km")
            if w.completion_score is not None:
                parts.append(f"Score: {w.completion_score}/100")
            if w.feedback_rating is not None:
                parts.append(f"Feel: {w.feedback_rating}/5")
            workout_lines.append(" | ".join(parts))

        workouts_text = "\n".join(workout_lines)

        analysis_distance = f"{request.custom_distance_km} km (Custom)" if request.race_type == RaceType.CUSTOM and request.custom_distance_km else request.race_type.value

        return f"""PERFORMANCE ANALYSIS REQUEST
=====================================

PLAN INFORMATION
Analysis Date: {date.today().strftime("%A, %B %d, %Y")}
Race Distance: {analysis_distance}
Race Date: {request.race_date.strftime("%A, %B %d, %Y")}
Plan Start Date: {request.start_date.strftime("%A, %B %d, %Y")}
Goal Time: {request.goal_time or "Not specified"}
Current Weekly Mileage: {request.current_weekly_mileage} km
Fitness Level: {request.fitness_level.value.capitalize()}
Progress: Week {request.weeks_into_plan} of {request.total_plan_weeks}

CURRENT TRAINING PLAN
{request.current_plan_content}

=====================================
COMPLETED WORKOUT DATA ({len(request.completed_workouts)} workouts)
=====================================
{workouts_text}

=====================================

Please analyze this athlete's training execution and provide your assessment."""

    def get_edit_system_prompt(self, race_type: RaceType, custom_distance_km: float | None = None, beginner_mode: bool = False) -> str:
        """Plan modification: same composition as generation, plus edit-mode behavior."""
        coach_file = get_coach_file(race_type, custom_distance_km, beginner_mode)
        return self.compose(
            FOUNDATION_PROMPT, PLAN_CORE_PROMPT, coach_file, PLAN_QUALITY_PROMPT, "coach_edit.txt"
        )

    def get_pre_run_voice_prompt(self) -> str:
        """Load the pre-run voice (TTS) coach prompt — Itzler-style send-off before run start."""
        return self._load_prompt("coach_pre_run_voice.txt")

    def get_post_run_voice_prompt(self, prerecorded_alerts: str) -> str:
        """Load the post-run voice (TTS) coach prompt with prerecorded-alerts placeholder substituted."""
        template = self._load_prompt("coach_post_run_voice.txt")
        return template.replace("{prerecorded_alerts}", prerecorded_alerts)

    # ── Coaching loop prompts (Phases 2–9) ──────────────────────────────────
    # Each composes: _coach_foundation.txt + race-specific persona + memo + behavior file.
    # Behavior files are added in their respective phase implementations.

    def get_weekly_review_prompt(self, race_type: RaceType, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_weekly_review.txt", race_type, custom_distance_km, memo)

    def get_block_review_prompt(self, race_type: RaceType, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_block_review.txt", race_type, custom_distance_km, memo)

    def get_post_run_check_prompt(self, race_type: RaceType, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_post_run.txt", race_type, custom_distance_km, memo)

    def get_red_flag_prompt(self, race_type: RaceType, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_red_flag.txt", race_type, custom_distance_km, memo)

    def get_consolidation_prompt(self, race_type: RaceType, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_consolidation.txt", race_type, custom_distance_km, memo)

    def get_post_race_prompt(self, race_type: RaceType, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_post_race.txt", race_type, custom_distance_km, memo)

    def get_race_prep_prompt(self, race_type: RaceType, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_race_prep.txt", race_type, custom_distance_km, memo)

    def get_race_logistics_prompt(self, race_type: RaceType, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_race_logistics.txt", race_type, custom_distance_km, memo)

    def get_race_fueling_prompt(self, race_type: RaceType, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_race_fueling.txt", race_type, custom_distance_km, memo)

    def get_chat_prompt(self, race_type: RaceType, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_chat.txt", race_type, custom_distance_km, memo)

    def get_nutrition_prompt(self, race_type: RaceType | None = None, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_nutrition.txt", race_type, custom_distance_km, memo)

    def get_nutrition_meal_feedback_prompt(self, memo: str = "") -> str:
        # Race-specific persona omitted — meal feedback is generic running fueling.
        return self._coaching_prompt("coach_nutrition_meal_feedback.txt", None, None, memo)

    def get_nutrition_parse_vision_prompt(self) -> str:
        """Vision-parsing prompt for photo/text meal logging — no memo, no race persona."""
        return self._load_prompt("coach_nutrition_parse_vision.txt")

    def get_wellness_prompt(self, race_type: RaceType | None = None, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_wellness.txt", race_type, custom_distance_km, memo)

    def get_wellness_concern_prompt(self, race_type: RaceType | None = None, custom_distance_km: float | None = None, memo: str = "") -> str:
        return self._coaching_prompt("coach_wellness_concern.txt", race_type, custom_distance_km, memo)

    def get_memo_update_prompt(self) -> str:
        """Used by coach_memo_service to update the persistent memo after a weekly review."""
        return self._load_prompt("coach_memo_update.txt")

    def build_edit_user_prompt(self, request: PlanEditRequest) -> str:
        """
        Build the user prompt for plan editing.

        Combines the current plan content with the athlete's edit instructions.
        """
        edit_distance = f"{request.custom_distance_km} km (Custom)" if request.race_type == RaceType.CUSTOM and request.custom_distance_km else request.race_type.value

        if request.goal_type == GoalType.HABIT:
            goal_header = f"""Goal: Habit-building block (NO RACE — never schedule one)
Modification Date: {date.today().strftime("%A, %B %d, %Y")}
Plan End Date: {request.race_date.strftime("%A, %B %d, %Y")}"""
        else:
            goal_header = f"""Race Distance: {edit_distance}
Modification Date: {date.today().strftime("%A, %B %d, %Y")}
Race Date: {request.race_date.strftime("%A, %B %d, %Y")}
Race Name: {request.race_name or "Not specified"}
Goal Time: {request.goal_time or "Not specified"}"""

        return f"""CURRENT TRAINING PLAN
=====================================
{goal_header}
Plan Start Date: {request.start_date.strftime("%A, %B %d, %Y")}

{request.current_plan_content}

=====================================
MODIFICATION REQUEST
=====================================
{request.edit_instructions}

Please output the COMPLETE modified plan following the exact same format as above."""


# Singleton instance
prompt_builder = PromptBuilder()
