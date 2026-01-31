-- Neon PostgreSQL Schema for Stride Running App
-- Run this in your Neon console to set up all required tables

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- USERS (Authentication)
-- =============================================================================

-- Users table - stores Apple Sign-In users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    apple_user_id TEXT NOT NULL UNIQUE,  -- Apple's unique user identifier
    email TEXT,
    display_name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_apple_user_id ON users(apple_user_id);

-- =============================================================================
-- USER PROFILE & PREFERENCES
-- =============================================================================

-- User training profile (equipment, preferences)
CREATE TABLE user_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    available_equipment TEXT[] DEFAULT ARRAY['none', 'dumbbells', 'resistance_bands'],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Training preferences
CREATE TABLE training_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    weekly_run_days INT DEFAULT 4,
    weekly_gym_days INT DEFAULT 2,
    preferred_rest_days INT[] DEFAULT ARRAY[1], -- 0=Sunday, 1=Monday, etc.
    preferred_long_run_day INT DEFAULT 0,
    max_weekly_km DOUBLE PRECISION,
    include_cross_training BOOLEAN DEFAULT FALSE,
    -- Availability (new system)
    available_days INT[] DEFAULT ARRAY[0, 2, 3, 4, 5, 6],
    rest_days INT[] DEFAULT ARRAY[1],
    allow_double_days BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- GOALS
-- =============================================================================

CREATE TABLE goals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('race', 'customTime', 'completion')),
    target_time_seconds DOUBLE PRECISION, -- nil for completion goals
    event_date DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    title TEXT,
    notes TEXT,
    race_distance TEXT, -- '5K', '10K', 'Half Marathon', 'Marathon', 'Custom'
    custom_distance_km DOUBLE PRECISION,
    baseline_status TEXT DEFAULT 'unknown' CHECK (baseline_status IN ('unknown', 'sufficient', 'required')),
    baseline_assessment_id UUID,
    estimated_vdot DOUBLE PRECISION,
    -- Training paces (cached from assessment)
    easy_pace_min DOUBLE PRECISION,
    easy_pace_max DOUBLE PRECISION,
    long_run_pace_min DOUBLE PRECISION,
    long_run_pace_max DOUBLE PRECISION,
    threshold_pace DOUBLE PRECISION,
    interval_pace DOUBLE PRECISION,
    repetition_pace DOUBLE PRECISION,
    race_pace DOUBLE PRECISION
);

CREATE INDEX idx_goals_user_id ON goals(user_id);
CREATE INDEX idx_goals_active ON goals(user_id, is_active);

-- =============================================================================
-- BASELINE ASSESSMENTS
-- =============================================================================

CREATE TABLE baseline_assessments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assessment_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    method TEXT NOT NULL CHECK (method IN ('recentRace', 'timeTrial', 'guidedTest', 'garminSync', 'autoCalculated')),
    vdot DOUBLE PRECISION NOT NULL,
    test_distance_km DOUBLE PRECISION,
    test_time_seconds DOUBLE PRECISION,
    -- Training paces
    easy_pace_min DOUBLE PRECISION NOT NULL,
    easy_pace_max DOUBLE PRECISION NOT NULL,
    long_run_pace_min DOUBLE PRECISION NOT NULL,
    long_run_pace_max DOUBLE PRECISION NOT NULL,
    threshold_pace DOUBLE PRECISION NOT NULL,
    interval_pace DOUBLE PRECISION NOT NULL,
    repetition_pace DOUBLE PRECISION NOT NULL,
    race_pace DOUBLE PRECISION,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_baseline_user_id ON baseline_assessments(user_id);

-- Pace feedback for assessments
CREATE TABLE pace_feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    assessment_id UUID NOT NULL REFERENCES baseline_assessments(id) ON DELETE CASCADE,
    feedback_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    rating TEXT NOT NULL CHECK (rating IN ('too_easy', 'just_right', 'too_hard')),
    notes TEXT
);

-- =============================================================================
-- TRAINING PLANS
-- =============================================================================

CREATE TABLE training_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    goal_id UUID NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_modified TIMESTAMPTZ DEFAULT NOW(),
    start_date DATE NOT NULL,
    event_date DATE NOT NULL,
    generation_method TEXT NOT NULL CHECK (generation_method IN ('rule_based', 'llm_generated', 'hybrid')),
    total_weeks INT NOT NULL,
    weekly_run_days INT NOT NULL,
    weekly_gym_days INT NOT NULL,
    -- Availability snapshot (JSON for complex nested data)
    availability_json JSONB,
    -- Generation context (JSON for complex nested data)
    generation_context_json JSONB,
    -- Goal feasibility (JSON)
    goal_feasibility_json JSONB,
    -- Phases (JSON array)
    phases_json JSONB NOT NULL
);

CREATE INDEX idx_training_plans_user_id ON training_plans(user_id);
CREATE INDEX idx_training_plans_goal_id ON training_plans(goal_id);

-- Week plans within a training plan
CREATE TABLE week_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    training_plan_id UUID NOT NULL REFERENCES training_plans(id) ON DELETE CASCADE,
    week_number INT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    phase_json JSONB NOT NULL,
    target_weekly_km DOUBLE PRECISION NOT NULL
);

CREATE INDEX idx_week_plans_training_plan_id ON week_plans(training_plan_id);

-- Planned workouts
CREATE TABLE planned_workouts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    week_plan_id UUID NOT NULL REFERENCES week_plans(id) ON DELETE CASCADE,
    workout_date DATE NOT NULL,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    completed BOOLEAN DEFAULT FALSE,
    actual_workout_id UUID, -- Reference to workout_sessions
    target_distance_km DOUBLE PRECISION,
    target_duration_seconds DOUBLE PRECISION,
    target_pace_seconds_per_km DOUBLE PRECISION,
    -- Complex nested data stored as JSON
    intervals_json JSONB,
    exercise_program_json JSONB,
    warmup_block_json JSONB,
    cooldown_block_json JSONB
);

CREATE INDEX idx_planned_workouts_week_plan_id ON planned_workouts(week_plan_id);
CREATE INDEX idx_planned_workouts_date ON planned_workouts(workout_date);

-- =============================================================================
-- WORKOUT SESSIONS (Completed workouts)
-- =============================================================================

CREATE TABLE workout_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    accumulated_active_time DOUBLE PRECISION DEFAULT 0,
    -- Pause intervals as JSON array
    pause_intervals_json JSONB,
    -- User-editable fields
    workout_title TEXT,
    effort_rating INT CHECK (effort_rating >= 1 AND effort_rating <= 10),
    notes TEXT,
    -- Weekly adaptation tracking
    fatigue_level INT CHECK (fatigue_level >= 1 AND fatigue_level <= 5),
    injury_flag BOOLEAN,
    injury_notes TEXT,
    -- Guided workout tracking
    planned_workout_id UUID,
    interval_completions_json JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_workout_sessions_user_id ON workout_sessions(user_id);
CREATE INDEX idx_workout_sessions_start_time ON workout_sessions(start_time DESC);

-- Workout samples (individual data points during workout)
CREATE TABLE workout_samples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ NOT NULL,
    speed_mps DOUBLE PRECISION NOT NULL,
    pace_sec_per_km DOUBLE PRECISION NOT NULL,
    total_distance_meters DOUBLE PRECISION NOT NULL,
    cadence_spm DOUBLE PRECISION,
    steps INT,
    heart_rate INT
);

CREATE INDEX idx_workout_samples_session_id ON workout_samples(session_id);
CREATE INDEX idx_workout_samples_timestamp ON workout_samples(session_id, timestamp);

-- Workout splits (kilometer splits)
CREATE TABLE workout_splits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
    km_index INT NOT NULL,
    split_time_seconds DOUBLE PRECISION NOT NULL,
    avg_pace_seconds_per_km DOUBLE PRECISION NOT NULL,
    avg_heart_rate INT,
    avg_cadence DOUBLE PRECISION,
    avg_speed_mps DOUBLE PRECISION
);

CREATE INDEX idx_workout_splits_session_id ON workout_splits(session_id);

-- =============================================================================
-- WORKOUT FEEDBACK
-- =============================================================================

CREATE TABLE workout_feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    workout_session_id UUID NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
    planned_workout_id UUID,
    feedback_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completion_status TEXT NOT NULL CHECK (completion_status IN ('completedAsPlanned', 'completedModified', 'skipped', 'stoppedEarly')),
    pace_adherence TEXT CHECK (pace_adherence IN ('onTarget', 'slightlyOff', 'offTarget')),
    perceived_effort INT NOT NULL CHECK (perceived_effort >= 1 AND perceived_effort <= 10),
    fatigue_level INT NOT NULL CHECK (fatigue_level >= 1 AND fatigue_level <= 5),
    pain_level INT NOT NULL CHECK (pain_level >= 0 AND pain_level <= 10),
    pain_areas TEXT[], -- Array of injury area strings
    weight_feel TEXT CHECK (weight_feel IN ('tooLight', 'justRight', 'tooHeavy')),
    form_breakdown BOOLEAN,
    notes TEXT
);

CREATE INDEX idx_workout_feedback_user_id ON workout_feedback(user_id);
CREATE INDEX idx_workout_feedback_session_id ON workout_feedback(workout_session_id);

-- =============================================================================
-- ADAPTATION RECORDS
-- =============================================================================

CREATE TABLE adaptation_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    week_start_date DATE NOT NULL,
    week_end_date DATE NOT NULL,
    -- Analysis snapshot
    completion_rate DOUBLE PRECISION NOT NULL,
    avg_pace_variance DOUBLE PRECISION,
    avg_hr_drift DOUBLE PRECISION,
    avg_rpe DOUBLE PRECISION,
    avg_fatigue DOUBLE PRECISION,
    injury_count INT NOT NULL DEFAULT 0,
    overall_status TEXT NOT NULL,
    -- Adaptation summary
    adjustment_count INT NOT NULL DEFAULT 0,
    volume_change_percent DOUBLE PRECISION,
    intensity_change_percent DOUBLE PRECISION,
    -- Coach message
    coach_title TEXT NOT NULL,
    coach_summary TEXT NOT NULL,
    coach_details TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    message_severity TEXT NOT NULL,
    -- User interaction
    viewed BOOLEAN DEFAULT FALSE,
    dismissed BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_adaptation_records_user_id ON adaptation_records(user_id);
CREATE INDEX idx_adaptation_records_timestamp ON adaptation_records(timestamp DESC);

-- =============================================================================
-- HELPER FUNCTION: Update timestamp trigger
-- =============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply trigger to tables with updated_at
CREATE TRIGGER update_user_profiles_updated_at
    BEFORE UPDATE ON user_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_training_preferences_updated_at
    BEFORE UPDATE ON training_preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_training_plans_updated_at
    BEFORE UPDATE ON training_plans
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
