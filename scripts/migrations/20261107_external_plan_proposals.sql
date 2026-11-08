-- Review and run manually during an approved release. Do not run on production
-- merely because application code has been deployed.
BEGIN;
ALTER TABLE users ADD COLUMN IF NOT EXISTS timezone_name varchar(64);
CREATE TABLE IF NOT EXISTS coach_credentials (
 id uuid PRIMARY KEY, owner_user_id uuid NOT NULL REFERENCES users(id),
 token_hash varchar(64) NOT NULL UNIQUE, label varchar(100) NOT NULL,
 can_read boolean NOT NULL DEFAULT true, can_propose boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now(), revoked_at timestamptz
);
CREATE TABLE IF NOT EXISTS coach_athlete_grants (
 id uuid PRIMARY KEY, credential_id uuid NOT NULL REFERENCES coach_credentials(id),
 athlete_id uuid NOT NULL REFERENCES users(id), can_read boolean NOT NULL DEFAULT true,
 can_propose boolean NOT NULL DEFAULT false, revoked_at timestamptz,
 UNIQUE (credential_id, athlete_id)
);
CREATE TABLE IF NOT EXISTS external_plan_proposals (
 id uuid PRIMARY KEY, credential_id uuid NOT NULL REFERENCES coach_credentials(id),
 athlete_id uuid NOT NULL REFERENCES users(id),
 expected_plan_id uuid NOT NULL REFERENCES training_plans(id),
 applied_plan_id uuid REFERENCES training_plans(id), idempotency_key varchar(100) NOT NULL,
 status varchar(20) NOT NULL DEFAULT 'proposed', reason varchar(1000) NOT NULL,
 before_text text NOT NULL, after_text text NOT NULL, diff jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), delivered_at timestamptz,
 decided_at timestamptz, applied_at timestamptz, UNIQUE (credential_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS ix_external_proposals_athlete_status ON external_plan_proposals(athlete_id,status);
CREATE TABLE IF NOT EXISTS coach_access_audit (
 id uuid PRIMARY KEY, credential_id uuid REFERENCES coach_credentials(id),
 athlete_id uuid REFERENCES users(id), proposal_id uuid REFERENCES external_plan_proposals(id),
 action varchar(50) NOT NULL, before_plan_id uuid, after_plan_id uuid,
 occurred_at timestamptz NOT NULL DEFAULT now()
);
COMMIT;
