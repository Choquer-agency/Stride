# Stride agent MCP

The Stride backend serves a Streamable HTTP MCP endpoint at `https://stridecoach.app/mcp/`. It uses one bearer token for all athletes and tools. The endpoint returns 503 until `STRIDE_AGENT_TOKEN` is set. No database migration or script-created credential is needed.

## Set up in Railway

1. Generate a long random secret locally, for example with `openssl rand -hex 32`.
2. In the Railway service for `stridecoach.app`, add `STRIDE_AGENT_TOKEN` with that value and redeploy after this PR is merged. Do not put the value in the repository or a client-side app.
3. In Grok Bot's remote MCP settings, set the server URL to `https://stridecoach.app/mcp/` and send `Authorization: Bearer <STRIDE_AGENT_TOKEN>` on every request. Keep the trailing slash.
4. Call `list_athletes`, then use an athlete's email as `athlete_email`. Omitting it selects Bryce.

The same tools remain available to the local stdio client through `scripts/stride_coach_mcp.py`.

## Tools

| Tool | Purpose |
| --- | --- |
| `list_athletes` | Athlete emails and plan/run overview |
| `get_coaching_context` | Profile, plan metadata, onboarding answers, check-ins, recent volume |
| `get_active_plan` | Full active plan text |
| `replace_in_plan` | Replace one exact snippet in the active plan |
| `update_plan` | Replace the entire active plan |
| `list_runs` | Run summaries with date filters and limit |
| `get_run` | Run details, splits, shoe, notes, matched workout, and HR samples |
| `hr_at` | Nearest HR sample at elapsed seconds or mm:ss |
| `log_run` | Add a manually reported run |
| `update_run` | Correct an existing run |
| `list_garmin_workouts` | Garmin activity summaries |
| `get_garmin_workout` | Splits, elevation, HR zones, training effect, VO2max, weather |
| `list_weekly_checkins` | Weekly questions and answers |
| `list_wellness` | Subjective wellness history |
| `list_garmin_daily_metrics` | Sleep, HRV, resting HR, body battery, stress |
| `list_garmin_periodic_metrics` | VO2max trend, training load, race predictors |
| `list_plan_history` | Plan versions and change notes, with optional full content |
| `list_plan_adjustments` | Existing adjustment history |

List tools cap results. `get_run` returns at most 200 evenly spaced HR samples by default; request `full_fidelity=true` for every stored sample, up to the 50000 sample safety limit. `list_plan_history` omits full plan text by default; set `include_content=true` to retrieve it.

Plan edits update the active `training_plans` row with `source='server_edit'`, a required `change_note`, and a fresh `updated_at`. On the next plan sync, the phone shows "Your coach updated your plan" and the athlete taps Apply. Keep `WEEK 1`, consecutive week headers at the start of lines, and day lines such as `- Monday: Easy Run - Total: 8 km`. Invalid plan text is rejected before saving. A full plan replacement must include every week. Plan history contains the stored generation, edit, and backfill versions; these agent edits update the current active row in place, as the local MCP already does.

## Rotate the token

Generate a new random value, replace `STRIDE_AGENT_TOKEN` in Railway, and redeploy. Update Grok Bot's bearer token to the new value. The old token stops working as soon as the new deployment is active. To disable the endpoint, remove the variable and redeploy; all MCP requests then return 503.
