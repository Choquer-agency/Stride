# Garmin Health API integration

## Status

- **Application submitted**: ☐ — submission required before Phase 1 can ship to production
- **Approval received**: ☐
- **Production credentials in env**: ☐

Approval window is **2–4 weeks**. Submit on Day 0 of v2; build against mocked payloads in the meantime via `scripts/garmin_simulator.py`.

## Day 0 action

1. Apply at [https://developer.garmin.com/gc-developer-program/health-api/](https://developer.garmin.com/gc-developer-program/health-api/) (NOT Connect IQ — that's for watch faces).
2. App description: "Stride is an AI-powered running coach. We use the Health API to ingest the athlete's workouts and recovery metrics so the coach can adapt the training plan based on actual performance and recovery."
3. Required scopes (request all of these):
   - `ACTIVITY_DATA` — workouts, splits, HR zones
   - `WELLNESS_DATA` — HRV, sleep, RHR, body battery, stress
   - `BODY_COMPOSITION` — needed by the wellness payload, even though we don't surface body comp data
4. Redirect URIs to register:
   - Production: `https://api.stride.app/api/garmin/callback`
   - Development: `http://localhost:8000/api/garmin/callback`
5. Webhook URLs to register (HMAC-signed):
   - Production: `https://api.stride.app/api/garmin/webhook/workout` and `.../webhook/daily-metrics` and `.../webhook/periodic-metrics`
   - Garmin sandbox: same paths against staging Railway URL
6. Save: client ID + client secret + webhook signing secret. Add to environment as below.

## Environment variables

```
GARMIN_CLIENT_ID=...
GARMIN_CLIENT_SECRET=...
GARMIN_WEBHOOK_SECRET=...                      # HMAC verification
GARMIN_REDIRECT_URI=https://api.stride.app/api/garmin/callback
```

## Webhook security

- Verify `X-Garmin-Signature` header on every push using HMAC-SHA256 with `GARMIN_WEBHOOK_SECRET`.
- Reject unsigned or mismatched payloads with 401.
- Idempotency via unique constraint on `garmin_workouts.garmin_activity_id` and `garmin_daily_metrics(user_id, date)`.
- Rotate `GARMIN_WEBHOOK_SECRET` quarterly. Update in env, redeploy, then update in Garmin developer portal (sequential — there is no rotation grace window).

## Activity types ingested

| Garmin activity_type | Stride bucket | Anomaly checks? |
|---|---|---|
| `running`, `treadmill_running`, `track_running`, `trail_running` | running | yes |
| `cycling`, `road_biking`, `mountain_biking`, `indoor_cycling`, `e_bike` | cycling | no (cross-training) |
| `strength_training`, `weight_training` | strength | no (logged into strength_sessions) |
| `walking`, `hiking`, `swimming`, `pool_swimming`, `yoga`, `pilates`, `mobility` | other | no (recovery context only) |

Unknown types fall through to `other`.

## Local development without real credentials

Use `scripts/garmin_simulator.py` to replay recorded payloads to local webhook endpoints:

```bash
python scripts/garmin_simulator.py tests/fixtures/garmin/easy_run.json
```

Fixtures live in `tests/fixtures/garmin/` and cover easy/tempo/long/race runs, treadmill, cycling, strength, walks, plus daily metrics with HRV drops, RHR rises, and poor sleep scenarios.

## Production switchover

When approval lands:

1. Replace dev credentials in Railway env with production values
2. Disconnect the dev Garmin account from any test users
3. Reconnect with the production-approved app on Bryce's real watch
4. Verify a real workout sync end-to-end — `garmin_workouts` row + matched `Run` row + post-run check fires

Then unplug `garmin_simulator.py` from any cron-style usage (it stays as a dev/debug tool).
