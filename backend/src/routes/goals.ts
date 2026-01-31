import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { query, queryOne, execute } from '../db.js';

export const goalsRouter = Router();

// Get all goals for the user
goalsRouter.get('/', async (req, res) => {
  try {
    const goals = await query(
      'SELECT * FROM goals WHERE user_id = $1 ORDER BY created_at DESC',
      [req.user!.id]
    );

    res.json(goals);
  } catch (error) {
    console.error('Error fetching goals:', error);
    res.status(500).json({ error: 'Failed to fetch goals' });
  }
});

// Get active goal
goalsRouter.get('/active', async (req, res) => {
  try {
    const goal = await queryOne(
      'SELECT * FROM goals WHERE user_id = $1 AND is_active = true LIMIT 1',
      [req.user!.id]
    );

    if (!goal) {
      res.status(404).json({ error: 'No active goal' });
      return;
    }

    res.json(goal);
  } catch (error) {
    console.error('Error fetching active goal:', error);
    res.status(500).json({ error: 'Failed to fetch active goal' });
  }
});

// Get a specific goal
goalsRouter.get('/:id', async (req, res) => {
  try {
    const goal = await queryOne(
      'SELECT * FROM goals WHERE id = $1 AND user_id = $2',
      [req.params.id, req.user!.id]
    );

    if (!goal) {
      res.status(404).json({ error: 'Goal not found' });
      return;
    }

    res.json(goal);
  } catch (error) {
    console.error('Error fetching goal:', error);
    res.status(500).json({ error: 'Failed to fetch goal' });
  }
});

// Create a new goal
goalsRouter.post('/', async (req, res) => {
  try {
    const {
      id = uuidv4(),
      type,
      targetTimeSeconds,
      eventDate,
      isActive = true,
      title,
      notes,
      raceDistance,
      customDistanceKm,
      baselineStatus = 'unknown',
      baselineAssessmentId,
      estimatedVdot,
      easyPaceMin,
      easyPaceMax,
      longRunPaceMin,
      longRunPaceMax,
      thresholdPace,
      intervalPace,
      repetitionPace,
      racePace,
    } = req.body;

    // If setting this goal as active, deactivate others
    if (isActive) {
      await execute(
        'UPDATE goals SET is_active = false WHERE user_id = $1',
        [req.user!.id]
      );
    }

    await execute(
      `INSERT INTO goals (
        id, user_id, type, target_time_seconds, event_date, created_at,
        is_active, title, notes, race_distance, custom_distance_km,
        baseline_status, baseline_assessment_id, estimated_vdot,
        easy_pace_min, easy_pace_max, long_run_pace_min, long_run_pace_max,
        threshold_pace, interval_pace, repetition_pace, race_pace
      ) VALUES ($1, $2, $3, $4, $5, NOW(), $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21)`,
      [
        id,
        req.user!.id,
        type,
        targetTimeSeconds,
        eventDate,
        isActive,
        title,
        notes,
        raceDistance,
        customDistanceKm,
        baselineStatus,
        baselineAssessmentId,
        estimatedVdot,
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

    res.status(201).json({ id, message: 'Goal created successfully' });
  } catch (error) {
    console.error('Error creating goal:', error);
    res.status(500).json({ error: 'Failed to create goal' });
  }
});

// Update a goal
goalsRouter.put('/:id', async (req, res) => {
  try {
    const existing = await queryOne(
      'SELECT id FROM goals WHERE id = $1 AND user_id = $2',
      [req.params.id, req.user!.id]
    );

    if (!existing) {
      res.status(404).json({ error: 'Goal not found' });
      return;
    }

    const updates = req.body;

    // If setting this goal as active, deactivate others
    if (updates.isActive) {
      await execute(
        'UPDATE goals SET is_active = false WHERE user_id = $1 AND id != $2',
        [req.user!.id, req.params.id]
      );
    }

    // Build dynamic update query
    const fields: string[] = [];
    const values: unknown[] = [];
    let paramIndex = 1;

    const fieldMappings: Record<string, string> = {
      type: 'type',
      targetTimeSeconds: 'target_time_seconds',
      eventDate: 'event_date',
      isActive: 'is_active',
      title: 'title',
      notes: 'notes',
      raceDistance: 'race_distance',
      customDistanceKm: 'custom_distance_km',
      baselineStatus: 'baseline_status',
      baselineAssessmentId: 'baseline_assessment_id',
      estimatedVdot: 'estimated_vdot',
      easyPaceMin: 'easy_pace_min',
      easyPaceMax: 'easy_pace_max',
      longRunPaceMin: 'long_run_pace_min',
      longRunPaceMax: 'long_run_pace_max',
      thresholdPace: 'threshold_pace',
      intervalPace: 'interval_pace',
      repetitionPace: 'repetition_pace',
      racePace: 'race_pace',
    };

    for (const [key, column] of Object.entries(fieldMappings)) {
      if (key in updates) {
        fields.push(`${column} = $${paramIndex}`);
        values.push(updates[key]);
        paramIndex++;
      }
    }

    if (fields.length > 0) {
      values.push(req.params.id);
      await execute(
        `UPDATE goals SET ${fields.join(', ')} WHERE id = $${paramIndex}`,
        values
      );
    }

    res.json({ message: 'Goal updated successfully' });
  } catch (error) {
    console.error('Error updating goal:', error);
    res.status(500).json({ error: 'Failed to update goal' });
  }
});

// Delete a goal
goalsRouter.delete('/:id', async (req, res) => {
  try {
    await execute(
      'DELETE FROM goals WHERE id = $1 AND user_id = $2',
      [req.params.id, req.user!.id]
    );

    res.json({ message: 'Goal deleted successfully' });
  } catch (error) {
    console.error('Error deleting goal:', error);
    res.status(500).json({ error: 'Failed to delete goal' });
  }
});

// Set active goal
goalsRouter.post('/:id/activate', async (req, res) => {
  try {
    // Deactivate all goals
    await execute(
      'UPDATE goals SET is_active = false WHERE user_id = $1',
      [req.user!.id]
    );

    // Activate the specified goal
    await execute(
      'UPDATE goals SET is_active = true WHERE id = $1 AND user_id = $2',
      [req.params.id, req.user!.id]
    );

    res.json({ message: 'Goal activated successfully' });
  } catch (error) {
    console.error('Error activating goal:', error);
    res.status(500).json({ error: 'Failed to activate goal' });
  }
});

// Deactivate current goal
goalsRouter.post('/deactivate', async (req, res) => {
  try {
    await execute(
      'UPDATE goals SET is_active = false WHERE user_id = $1',
      [req.user!.id]
    );

    res.json({ message: 'Goal deactivated successfully' });
  } catch (error) {
    console.error('Error deactivating goal:', error);
    res.status(500).json({ error: 'Failed to deactivate goal' });
  }
});
