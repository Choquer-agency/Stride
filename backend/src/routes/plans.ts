import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { query, queryOne, execute } from '../db.js';

export const plansRouter = Router();

// Get current training plan
plansRouter.get('/current', async (req, res) => {
  try {
    const plan = await queryOne(
      `SELECT * FROM training_plans 
       WHERE user_id = $1 
       ORDER BY created_at DESC 
       LIMIT 1`,
      [req.user!.id]
    );

    if (!plan) {
      res.status(404).json({ error: 'No training plan found' });
      return;
    }

    // Get week plans
    const weeks = await query(
      `SELECT * FROM week_plans 
       WHERE training_plan_id = $1 
       ORDER BY week_number`,
      [(plan as any).id]
    );

    // Get workouts for each week
    const weeksWithWorkouts = await Promise.all(
      (weeks as any[]).map(async (week) => {
        const workouts = await query(
          `SELECT * FROM planned_workouts 
           WHERE week_plan_id = $1 
           ORDER BY workout_date`,
          [week.id]
        );
        return { ...week, workouts };
      })
    );

    res.json({ ...plan, weeks: weeksWithWorkouts });
  } catch (error) {
    console.error('Error fetching plan:', error);
    res.status(500).json({ error: 'Failed to fetch training plan' });
  }
});

// Create/save training plan
plansRouter.post('/', async (req, res) => {
  try {
    const {
      id = uuidv4(),
      goalId,
      startDate,
      eventDate,
      generationMethod,
      totalWeeks,
      weeklyRunDays,
      weeklyGymDays,
      availabilityJson,
      generationContextJson,
      goalFeasibilityJson,
      phasesJson,
      weeks = [],
    } = req.body;

    // Delete existing plan if any
    await execute(
      'DELETE FROM training_plans WHERE user_id = $1',
      [req.user!.id]
    );

    // Insert new plan
    await execute(
      `INSERT INTO training_plans (
        id, user_id, goal_id, created_at, last_modified, start_date, event_date,
        generation_method, total_weeks, weekly_run_days, weekly_gym_days,
        availability_json, generation_context_json, goal_feasibility_json, phases_json
      ) VALUES ($1, $2, $3, NOW(), NOW(), $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)`,
      [
        id,
        req.user!.id,
        goalId,
        startDate,
        eventDate,
        generationMethod,
        totalWeeks,
        weeklyRunDays,
        weeklyGymDays,
        availabilityJson ? JSON.stringify(availabilityJson) : null,
        generationContextJson ? JSON.stringify(generationContextJson) : null,
        goalFeasibilityJson ? JSON.stringify(goalFeasibilityJson) : null,
        JSON.stringify(phasesJson),
      ]
    );

    // Insert weeks and workouts
    for (const week of weeks) {
      const weekId = week.id || uuidv4();

      await execute(
        `INSERT INTO week_plans (
          id, training_plan_id, week_number, start_date, end_date,
          phase_json, target_weekly_km
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [
          weekId,
          id,
          week.weekNumber,
          week.startDate,
          week.endDate,
          JSON.stringify(week.phase),
          week.targetWeeklyKm,
        ]
      );

      // Insert workouts for this week
      for (const workout of week.workouts || []) {
        await execute(
          `INSERT INTO planned_workouts (
            id, week_plan_id, workout_date, type, title, description,
            completed, actual_workout_id, target_distance_km, target_duration_seconds,
            target_pace_seconds_per_km, intervals_json, exercise_program_json,
            warmup_block_json, cooldown_block_json
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`,
          [
            workout.id || uuidv4(),
            weekId,
            workout.date,
            workout.type,
            workout.title,
            workout.description,
            workout.completed || false,
            workout.actualWorkoutId,
            workout.targetDistanceKm,
            workout.targetDurationSeconds,
            workout.targetPaceSecondsPerKm,
            workout.intervals ? JSON.stringify(workout.intervals) : null,
            workout.exerciseProgram ? JSON.stringify(workout.exerciseProgram) : null,
            workout.warmupBlock ? JSON.stringify(workout.warmupBlock) : null,
            workout.cooldownBlock ? JSON.stringify(workout.cooldownBlock) : null,
          ]
        );
      }
    }

    res.status(201).json({ id, message: 'Training plan saved successfully' });
  } catch (error) {
    console.error('Error saving plan:', error);
    res.status(500).json({ error: 'Failed to save training plan' });
  }
});

// Update a planned workout (mark complete, etc.)
plansRouter.put('/workouts/:id', async (req, res) => {
  try {
    const { completed, actualWorkoutId } = req.body;

    // Verify ownership through the plan hierarchy
    const workout = await queryOne(
      `SELECT pw.id FROM planned_workouts pw
       JOIN week_plans wp ON pw.week_plan_id = wp.id
       JOIN training_plans tp ON wp.training_plan_id = tp.id
       WHERE pw.id = $1 AND tp.user_id = $2`,
      [req.params.id, req.user!.id]
    );

    if (!workout) {
      res.status(404).json({ error: 'Workout not found' });
      return;
    }

    await execute(
      `UPDATE planned_workouts SET
        completed = COALESCE($1, completed),
        actual_workout_id = COALESCE($2, actual_workout_id)
       WHERE id = $3`,
      [completed, actualWorkoutId, req.params.id]
    );

    res.json({ message: 'Workout updated successfully' });
  } catch (error) {
    console.error('Error updating workout:', error);
    res.status(500).json({ error: 'Failed to update workout' });
  }
});

// Delete training plan
plansRouter.delete('/current', async (req, res) => {
  try {
    await execute(
      'DELETE FROM training_plans WHERE user_id = $1',
      [req.user!.id]
    );

    res.json({ message: 'Training plan deleted successfully' });
  } catch (error) {
    console.error('Error deleting plan:', error);
    res.status(500).json({ error: 'Failed to delete training plan' });
  }
});

// Get baseline assessments
plansRouter.get('/assessments', async (req, res) => {
  try {
    const assessments = await query(
      `SELECT * FROM baseline_assessments 
       WHERE user_id = $1 
       ORDER BY assessment_date DESC`,
      [req.user!.id]
    );

    res.json(assessments);
  } catch (error) {
    console.error('Error fetching assessments:', error);
    res.status(500).json({ error: 'Failed to fetch assessments' });
  }
});

// Save baseline assessment
plansRouter.post('/assessments', async (req, res) => {
  try {
    const {
      id = uuidv4(),
      method,
      vdot,
      testDistanceKm,
      testTimeSeconds,
      easyPaceMin,
      easyPaceMax,
      longRunPaceMin,
      longRunPaceMax,
      thresholdPace,
      intervalPace,
      repetitionPace,
      racePace,
    } = req.body;

    await execute(
      `INSERT INTO baseline_assessments (
        id, user_id, assessment_date, method, vdot,
        test_distance_km, test_time_seconds,
        easy_pace_min, easy_pace_max, long_run_pace_min, long_run_pace_max,
        threshold_pace, interval_pace, repetition_pace, race_pace
      ) VALUES ($1, $2, NOW(), $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`,
      [
        id,
        req.user!.id,
        method,
        vdot,
        testDistanceKm,
        testTimeSeconds,
        easyPaceMin,
        easyPaceMax,
        longRunPaceMin,
        longRunPaceMax,
        thresholdPace,
        intervalPace,
        repetitionPace,
        racePace,
      ]
    );

    res.status(201).json({ id, message: 'Assessment saved successfully' });
  } catch (error) {
    console.error('Error saving assessment:', error);
    res.status(500).json({ error: 'Failed to save assessment' });
  }
});

// Get adaptation records
plansRouter.get('/adaptations', async (req, res) => {
  try {
    const records = await query(
      `SELECT * FROM adaptation_records 
       WHERE user_id = $1 
       ORDER BY timestamp DESC 
       LIMIT 26`,
      [req.user!.id]
    );

    res.json(records);
  } catch (error) {
    console.error('Error fetching adaptations:', error);
    res.status(500).json({ error: 'Failed to fetch adaptation records' });
  }
});

// Save adaptation record
plansRouter.post('/adaptations', async (req, res) => {
  try {
    const {
      id = uuidv4(),
      weekStartDate,
      weekEndDate,
      completionRate,
      avgPaceVariance,
      avgHrDrift,
      avgRpe,
      avgFatigue,
      injuryCount,
      overallStatus,
      adjustmentCount,
      volumeChangePercent,
      intensityChangePercent,
      coachTitle,
      coachSummary,
      coachDetails,
      messageSeverity,
    } = req.body;

    await execute(
      `INSERT INTO adaptation_records (
        id, user_id, timestamp, week_start_date, week_end_date,
        completion_rate, avg_pace_variance, avg_hr_drift, avg_rpe, avg_fatigue,
        injury_count, overall_status, adjustment_count,
        volume_change_percent, intensity_change_percent,
        coach_title, coach_summary, coach_details, message_severity
      ) VALUES ($1, $2, NOW(), $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)`,
      [
        id,
        req.user!.id,
        weekStartDate,
        weekEndDate,
        completionRate,
        avgPaceVariance,
        avgHrDrift,
        avgRpe,
        avgFatigue,
        injuryCount,
        overallStatus,
        adjustmentCount,
        volumeChangePercent,
        intensityChangePercent,
        coachTitle,
        coachSummary,
        coachDetails,
        messageSeverity,
      ]
    );

    res.status(201).json({ id, message: 'Adaptation record saved successfully' });
  } catch (error) {
    console.error('Error saving adaptation:', error);
    res.status(500).json({ error: 'Failed to save adaptation record' });
  }
});
