import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { query, queryOne, execute } from '../db.js';

export const profileRouter = Router();

// Get user profile
profileRouter.get('/', async (req, res) => {
  try {
    const profile = await queryOne(
      'SELECT * FROM user_profiles WHERE user_id = $1',
      [req.user!.id]
    );

    if (!profile) {
      // Create default profile
      const id = uuidv4();
      await execute(
        `INSERT INTO user_profiles (id, user_id, available_equipment)
         VALUES ($1, $2, ARRAY['none', 'dumbbells', 'resistance_bands'])`,
        [id, req.user!.id]
      );

      res.json({
        id,
        userId: req.user!.id,
        availableEquipment: ['none', 'dumbbells', 'resistance_bands'],
      });
      return;
    }

    res.json(profile);
  } catch (error) {
    console.error('Error fetching profile:', error);
    res.status(500).json({ error: 'Failed to fetch profile' });
  }
});

// Update user profile
profileRouter.put('/', async (req, res) => {
  try {
    const { availableEquipment } = req.body;

    await execute(
      `UPDATE user_profiles SET
        available_equipment = $1,
        updated_at = NOW()
       WHERE user_id = $2`,
      [availableEquipment, req.user!.id]
    );

    res.json({ message: 'Profile updated successfully' });
  } catch (error) {
    console.error('Error updating profile:', error);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

// Get training preferences
profileRouter.get('/preferences', async (req, res) => {
  try {
    const prefs = await queryOne(
      'SELECT * FROM training_preferences WHERE user_id = $1',
      [req.user!.id]
    );

    if (!prefs) {
      // Create default preferences
      const id = uuidv4();
      await execute(
        `INSERT INTO training_preferences (id, user_id, weekly_run_days, weekly_gym_days)
         VALUES ($1, $2, 4, 2)`,
        [id, req.user!.id]
      );

      res.json({
        id,
        userId: req.user!.id,
        weeklyRunDays: 4,
        weeklyGymDays: 2,
        preferredRestDays: [1],
        preferredLongRunDay: 0,
        includeCrossTraining: false,
      });
      return;
    }

    res.json(prefs);
  } catch (error) {
    console.error('Error fetching preferences:', error);
    res.status(500).json({ error: 'Failed to fetch preferences' });
  }
});

// Update training preferences
profileRouter.put('/preferences', async (req, res) => {
  try {
    const {
      weeklyRunDays,
      weeklyGymDays,
      preferredRestDays,
      preferredLongRunDay,
      maxWeeklyKm,
      includeCrossTraining,
      availableDays,
      restDays,
      allowDoubleDays,
    } = req.body;

    await execute(
      `UPDATE training_preferences SET
        weekly_run_days = COALESCE($1, weekly_run_days),
        weekly_gym_days = COALESCE($2, weekly_gym_days),
        preferred_rest_days = COALESCE($3, preferred_rest_days),
        preferred_long_run_day = COALESCE($4, preferred_long_run_day),
        max_weekly_km = COALESCE($5, max_weekly_km),
        include_cross_training = COALESCE($6, include_cross_training),
        available_days = COALESCE($7, available_days),
        rest_days = COALESCE($8, rest_days),
        allow_double_days = COALESCE($9, allow_double_days),
        updated_at = NOW()
       WHERE user_id = $10`,
      [
        weeklyRunDays,
        weeklyGymDays,
        preferredRestDays,
        preferredLongRunDay,
        maxWeeklyKm,
        includeCrossTraining,
        availableDays,
        restDays,
        allowDoubleDays,
        req.user!.id,
      ]
    );

    res.json({ message: 'Preferences updated successfully' });
  } catch (error) {
    console.error('Error updating preferences:', error);
    res.status(500).json({ error: 'Failed to update preferences' });
  }
});
