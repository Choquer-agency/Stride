-- Safe to apply repeatedly. Existing run and user rows retain their values.
ALTER TABLE runs ADD COLUMN IF NOT EXISTS elevation_gain_m DOUBLE PRECISION;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS elevation_loss_m DOUBLE PRECISION;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS metrics_json JSONB;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS webhook_claimed_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS webhook_payload_hash VARCHAR(64);
ALTER TABLE users ADD COLUMN IF NOT EXISTS run_webhook_url TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS run_webhook_key TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS run_webhook_key_header VARCHAR(100) DEFAULT 'Authorization';
