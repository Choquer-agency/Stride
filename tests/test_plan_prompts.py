"""Regression tests for plan-generation prompt composition."""

import unittest
from datetime import date

from app.models.schemas import (
    DayOfWeek,
    FitnessLevel,
    PlanMode,
    RaceType,
    TrainingPlanRequest,
)
from app.services.prompt_builder import prompt_builder


def request_for(race_type: RaceType, **overrides) -> TrainingPlanRequest:
    values = {
        "race_type": race_type,
        "race_date": date(2026, 10, 4),
        "start_date": date(2026, 7, 11),
        "goal_time": "1:50:00" if race_type == RaceType.HALF_MARATHON else None,
        "current_weekly_mileage": 32,
        "longest_recent_run": 14,
        "recent_runs": "Four runs last week: 6, 7, 5, and 14 km",
        "fitness_level": FitnessLevel.INTERMEDIATE,
        "rest_days": [DayOfWeek.FRIDAY],
        "long_run_day": DayOfWeek.SUNDAY,
        "running_days_per_week": 4,
        "gym_days_per_week": 1,
        "years_running": 3,
    }
    values.update(overrides)
    return TrainingPlanRequest(**values)


class PlanPromptTests(unittest.TestCase):
    def test_every_race_prompt_includes_quality_contract(self):
        cases = [
            (RaceType.FIVE_K, None),
            (RaceType.TEN_K, None),
            (RaceType.HALF_MARATHON, None),
            (RaceType.MARATHON, None),
            (RaceType.CUSTOM, 80.0),
        ]
        for race_type, custom_distance in cases:
            with self.subTest(race_type=race_type, custom_distance=custom_distance):
                prompt = prompt_builder.get_system_prompt(race_type, custom_distance)
                self.assertIn("PLAN QUALITY CONTRACT", prompt)
                self.assertIn("ARITHMETIC AND CONSISTENCY AUDIT", prompt)
                self.assertIn("PARSER-SAFE OUTPUT CONTRACT", prompt)

    def test_aggressive_mode_does_not_force_unsafe_benchmarks(self):
        request = request_for(
            RaceType.MARATHON,
            plan_mode=PlanMode.AGGRESSIVE,
            goal_time="3:15:00",
        )
        prompt = prompt_builder.build_user_prompt(request)
        self.assertIn("ASPIRATIONAL, NOT FORCED", prompt)
        self.assertIn("rather than manufacturing a dangerous progression", prompt)
        self.assertNotIn("benchmarks are REQUIRED", prompt)
        self.assertNotIn("even if progression is aggressive", prompt)

    def test_partial_weeks_are_counted_without_flooring(self):
        prompt = prompt_builder.build_user_prompt(request_for(RaceType.HALF_MARATHON))
        # July 11 to October 4 is 85 days, requiring 13 calendar week rows.
        self.assertIn("Training Duration: 13 weeks (85 days)", prompt)
        self.assertIn("Week 1 is a PARTIAL week", prompt)

    def test_edit_prompt_gets_quality_contract_but_analysis_keeps_its_own_format(self):
        edit_prompt = prompt_builder.get_edit_system_prompt(RaceType.MARATHON)
        analysis_prompt = prompt_builder.get_analysis_system_prompt(RaceType.MARATHON)
        self.assertIn("PLAN QUALITY CONTRACT", edit_prompt)
        self.assertIn("Treat workouts before the Modification Date as historical records", edit_prompt)
        self.assertNotIn("PARSER-SAFE OUTPUT CONTRACT", analysis_prompt)
        self.assertIn("Absence from that list", analysis_prompt)


if __name__ == "__main__":
    unittest.main()
