# Stride coach MCP release procedure

This connector reads only explicitly granted athletes and can create proposals.
Only the athlete's signed-in iOS app can accept or reject. There is no MCP
acceptance tool or implicit family access. The old `scripts/stride_coach_mcp.py`
is a local, broad-access script and must **not** be exposed or configured in Grok.

## Release gates

1. Review the code and test results. Back up the database.
2. With explicit production approval, run
   `scripts/migrations/20261107_external_plan_proposals.sql` once against the
   production database. The file is idempotent, but review it before execution.
3. Deploy the FastAPI app with the new `/api/external-plans/*` routes. The iOS
   build containing the Plan approval card must be distributed to athletes.
4. The production FastAPI app hosts the bearer-protected Streamable HTTP MCP
   endpoint at `https://stridecoach.app/mcp/`. It reuses the existing server
   environment, including `DATABASE_URL`, `JWT_SECRET_KEY`, `APNS_KEY_ID`,
   `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_USE_SANDBOX`, and either
   `APNS_KEY_PATH` or `APNS_KEY_BASE64`. None of these variables go into Grok.
   The standalone `app.coach_mcp:asgi_app` entrypoint remains available for a
   later dedicated deployment if traffic isolation is needed.
6. Configure each athlete's IANA timezone explicitly using
   `PYTHONPATH=. python scripts/manage_coach_access.py set-timezone --athlete-id <uuid> --timezone <IANA-name>`.
   This is the athlete's **plan timezone**, not the current travel timezone.
   Confirm it with the athlete before setting it. The tools refuse dated
   workouts and proposals when it is absent.
7. Provision a credential with only the intended athlete IDs:
   `PYTHONPATH=. python scripts/manage_coach_access.py create --owner-id <coach-user-uuid> --athlete-id <athlete-uuid> [--athlete-id <another-uuid>] --label grok-bot --propose`.
   Omit `--propose` for a read-only key. The API key is printed once. Deliver
   it via a secret manager, not chat or source control. Revoke with
   `PYTHONPATH=. python scripts/manage_coach_access.py revoke --credential-id <uuid>`.
   Remove one athlete with `PYTHONPATH=. python scripts/manage_coach_access.py
   revoke-athlete --credential-id <uuid> --athlete-id <uuid>`.
8. In Grok, add a Custom MCP connector at the HTTPS URL and select API-key /
   Bearer authentication. Supply the one-time `stride_...` key as the Bearer
   value. Grok's [custom connector instructions](https://docs.x.ai/grok/connectors)
   describe its setup screen. No `DATABASE_URL` or Stride login JWT is shared.

## Safe verification

Use a staging database and synthetic athletes first. Run
`venv/bin/python -m pytest -q tests/test_external_plan_service.py` and an
iOS device build. Confirm unauthenticated requests get HTTP 401, read-only keys
cannot propose, cross-athlete IDs fail, and revoked keys stop working.

After approval for a real verification, use a temporary credential granted
only to the consenting athlete. Connect Grok; call `list_athletes`, then
`read_planned_workouts` with that athlete's UUID and a narrow date range.
Check the returned version, dates, units and timezone against the phone.
Propose a small **future-only** test change using `propose_plan_change` with the
same athlete UUID, expected version, reason and unique idempotency key. Verify
the active plan version remains unchanged while status is `proposed` or
`delivered`. Review the full diff on the phone and accept. Verify status moves
to `accepted`, then `applied` after the phone sync acknowledgment; read the new
active version and verify the planned workout. A rejected proposal must leave
the old version active. Restore a test change through a second phone-approved
proposal, never by direct MCP edit. Revoke the temporary credential afterward.

## Current limits

- No real athlete or production verification has been performed. APNs delivery
  and physical-phone acceptance/sync require a staging deployment and device.
- The external proposal path uses a separate model from legacy coach-chat
  `plan_adjustments`; the legacy local-first acceptance path remains unchanged
  and must not be used as the external connector's approval mechanism.
- Credentials are scoped bearer API keys, as supported by Grok custom MCP
  connectors. They are hashed at rest and revocable by credential ID. This is
  not an OAuth authorization-code flow; use an OAuth identity provider if your
  Grok organization requires OAuth-only connectors.
