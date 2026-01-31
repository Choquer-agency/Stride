import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { query, queryOne, execute } from '../db.js';

export const workoutsRouter = Router();

// Get all workouts for the authenticated user
workoutsRouter.get('/', async (req, res) => {
  try {
    const workouts = await query(
      `SELECT * FROM workout_sessions 
       WHERE user_id = $1 
       ORDER BY start_time DESC`,
      [req.user!.id]
    );

    res.json(workouts);
  } catch (error) {
    console.error('Error fetching workouts:', error);
    res.status(500).json({ error: 'Failed to fetch workouts' });
  }
});

// Get a specific workout with samples and splits
workoutsRouter.get('/:id', async (req, res) => {
  try {
    const workout = await queryOne(
      'SELECT * FROM workout_sessions WHERE id = $1 AND user_id = $2',
      [req.params.id, req.user!.id]
    );

    if (!workout) {
      res.status(404).json({ error: 'Workout not found' });
      return;
    }

    // Get splits
    const splits = await query(
      'SELECT * FROM workout_splits WHERE session_id = $1 ORDER BY km_index',
      [req.params.id]
    );

    // Get recent samples (last 300)
    const samples = await query(
      `SELECT * FROM workout_samples 
       WHERE session_id = $1 
       ORDER BY timestamp DESC 
       LIMIT 300`,
      [req.params.id]
    );

    res.json({
      ...workout,
      splits,
      samples: samples.reverse(),
    });
  } catch (error) {
    console.error('Error fetching workout:', error);
    res.status(500).json({ error: 'Failed to fetch workout' });
  }
});

// Create a new workout
workoutsRouter.post('/', async (req, res) => {
  try {
    const {
      id = uuidv4(),
      startTime,
      endTime,
      accumulatedActiveTime,
      pauseIntervalsJson,
      workoutTitle,
      effortRating,
      notes,
      fatigueLevel,
      injuryFlag,
      injuryNotes,
      plannedWorkoutId,
      intervalCompletionsJson,
      splits = [],
      samples = [],
    } = req.body;

    // Insert workout session
    await execute(
      `INSERT INTO workout_sessions (
        id, user_id, start_time, end_time, accumulated_active_time,
        pause_intervals_json, workout_title, effort_rating, notes,
        fatigue_level, injury_flag, injury_notes,
        planned_workout_id, interval_completions_json
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`,
      [
        id,
        req.user!.id,
        startTime,
        endTime,
        accumulatedActiveTime || 0,
        pauseIntervalsJson ? JSON.stringify(pauseIntervalsJson) : null,
        workoutTitle,
        effortRating,
        notes,
        fatigueLevel,
        injuryFlag,
        injuryNotes,
        plannedWorkoutId,
        intervalCompletionsJson ? JSON.stringify(intervalCompletionsJson) : null,
      ]
    );

    // Insert splits
    for (const split of splits) {
      await execute(
        `INSERT INTO workout_splits (
          id, session_id, km_index, split_time_seconds,
          avg_pace_seconds_per_km, avg_heart_rate, avg_cadence, avg_speed_mps
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [
          split.id || uuidv4(),
          id,
          split.kmIndex,
          split.splitTimeSeconds,
          split.avgPaceSecondsPerKm,
          split.avgHeartRate,
          split.avgCadence,
          split.avgSpeedMps,
        ]
      );
    }

    // Insert samples
    for (const sample of samples) {
      await execute(
        `INSERT INTO workout_samples (
          id, session_id, timestamp, speed_mps, pace_sec_per_km,
          total_distance_meters, cadence_spm, steps, heart_rate
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
        [
          sample.id || uuidv4(),
          id,
          sample.timestamp,
          sample.speedMps,
          sample.paceSecPerKm,
          sample.totalDistanceMeters,
          sample.cadenceSpm,
          sample.steps,
          sample.heartRate,
        ]
      );
    }

    res.status(201).json({ id, message: 'Workout saved successfully' });
  } catch (error) {
    console.error('Error saving workout:', error);
    res.status(500).json({ error: 'Failed to save workout' });
  }
});

// Update a workout
workoutsRouter.put('/:id', async (req, res) => {
  try {
    // Verify ownership
    const existing = await queryOne(
      'SELECT id FROM workout_sessions WHERE id = $1 AND user_id = $2',
      [req.params.id, req.user!.id]
    );

    if (!existing) {
      res.status(404).json({ error: 'Workout not found' });
      return;
    }

    const { workoutTitle, effortRating, notes, fatigueLevel, injuryFlag, injuryNotes } = req.body;

    await execute(
      `UPDATE workout_sessions SET
        workout_title = COALESCE($1, workout_title),
        effort_rating = COALESCE($2, effort_rating),
        notes = COALESCE($3, notes),
        fatigue_level = COALESCE($4, fatigue_level),
        injury_flag = COALESCE($5, injury_flag),
        injury_notes = COALESCE($6, injury_notes)
       WHERE id = $7`,
      [workoutTitle, effortRating, notes, fatigueLevel, injuryFlag, injuryNotes, req.params.id]
    );

    res.json({ message: 'Workout updated successfully' });
  } catch (error) {
    console.error('Error updating workout:', error);
    res.status(500).json({ error: 'Failed to update workout' });
  }
});

// Delete a workout
workoutsRouter.delete('/:id', async (req, res) => {
  try {
    const result = await execute(
      'DELETE FROM workout_sessions WHERE id = $1 AND user_id = $2',
      [req.params.id, req.user!.id]
    );

    res.json({ message: 'Workout deleted successfully' });
  } catch (error) {
    console.error('Error deleting workout:', error);
    res.status(500).json({ error: 'Failed to delete workout' });
  }
});

// Get workout feedback
workoutsRouter.get('/:id/feedback', async (req, res) => {
  try {
    const feedback = await queryOne(
      'SELECT * FROM workout_feedback WHERE workout_session_id = $1 AND user_id = $2',
      [req.params.id, req.user!.id]
    );

    if (!feedback) {
      res.status(404).json({ error: 'Feedback not found' });
      return;
    }

    res.json(feedback);
  } catch (error) {
    console.error('Error fetching feedback:', error);
    res.status(500).json({ error: 'Failed to fetch feedback' });
  }
});

// Save workout feedback
workoutsRouter.post('/:id/feedback', async (req, res) => {
  try {
    const {
      id = uuidv4(),
      plannedWorkoutId,
      completionStatus,
      paceAdherence,
      perceivedEffort,
      fatigueLevel,
      painLevel,
      painAreas,
      weightFeel,
      formBreakdown,
      notes,
    } = req.body;

    await execute(
      `INSERT INTO workout_feedback (
        id, user_id, workout_session_id, planned_workout_id, feedback_date,
        completion_status, pace_adherence, perceived_effort, fatigue_level,
        pain_level, pain_areas, weight_feel, form_breakdown, notes
      ) VALUES ($1, $2, $3, $4, NOW(), $5, $6, $7, $8, $9, $10, $11, $12, $13)
      ON CONFLICT (id) DO UPDATE SET
        completion_status = EXCLUDED.completion_status,
        pace_adherence = EXCLUDED.pace_adherence,
        perceived_effort = EXCLUDED.perceived_effort,
        fatigue_level = EXCLUDED.fatigue_level,
        pain_level = EXCLUDED.pain_level,
        pain_areas = EXCLUDED.pain_areas,
        weight_feel = EXCLUDED.weight_feel,
        form_breakdown = EXCLUDED.form_breakdown,
        notes = EXCLUDED.notes`,
      [
        id,
        req.user!.id,
        req.params.id,
        plannedWorkoutId,
        completionStatus,
        paceAdherence,
        perceivedEffort,
        fatigueLevel,
        painLevel,
        painAreas,
        weightFeel,
        formBreakdown,
        notes,
      ]
    );

    res.status(201).json({ id, message: 'Feedback saved successfully' });
  } catch (error) {
    console.error('Error saving feedback:', error);
    res.status(500).json({ error: 'Failed to save feedback' });
  }
});
