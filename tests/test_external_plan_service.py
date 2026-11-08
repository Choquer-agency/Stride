"""Synthetic proposal invariants; no production database or real athletes."""
import asyncio
from datetime import date
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest
from starlette.testclient import TestClient

from app.coach_mcp import _caller, _grant, asgi_app, mounted_app
from app.services.external_plan_service import decide, mark_applied, plan_impact, validate_plan_text


VALID = "WEEK 1\n- Monday: Rest Day\n- Wednesday: Easy Run — Total: 8 km at 6:00–6:30/km\nWEEK 2\n- Tuesday: Tempo Run — Total: 10 km"


def test_weekday_anchor_and_timezone():
    rows = validate_plan_text(VALID, date(2026, 11, 4), "Pacific/Honolulu")
    assert [r["date"] for r in rows] == ["2026-11-04", "2026-11-10"]
    assert plan_impact(rows, rows)["weekly_km_changes"] == []


@pytest.mark.parametrize("content", ["", "WEEK 1\nhello", "WEEK 1\n- Monday: Run\nWEEK 1\n- Tuesday: Run"])
def test_invalid_plan_text_rejected(content):
    with pytest.raises(ValueError):
        validate_plan_text(content, date(2026, 11, 2), "Pacific/Honolulu")


def test_mcp_authentication_and_tool_discovery():
    class DB:
        calls = 0
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def scalar(self, statement):
            DB.calls += 1
            return SimpleNamespace(id=uuid4(), revoked_at=None) if DB.calls % 2 else 0
        def add(self, record): pass
        async def commit(self): pass
    headers = {"Authorization": "Bearer stride_" + "a" * 48,
               "Accept": "application/json, text/event-stream",
               "Mcp-Protocol-Version": "2025-11-25"}
    with TestClient(asgi_app) as client:
        response = client.post("/mcp", json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
        assert response.status_code == 401
        with patch("app.coach_mcp.async_session", new=lambda: DB()):
            response = client.post("/mcp", headers=headers,
                json={"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}})
        assert response.status_code == 200
        assert "propose_plan_change" in response.text
        class RevokedDB(DB):
            async def scalar(self, statement): return None
        with patch("app.coach_mcp.async_session", new=lambda: RevokedDB()):
            response = client.post("/mcp", headers=headers,
                json={"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}})
        assert response.status_code == 401


def test_mcp_mount_on_existing_https_service():
    from contextlib import asynccontextmanager
    from fastapi import FastAPI

    @asynccontextmanager
    async def lifespan(app):
        async with mounted_app.inner.router.lifespan_context(mounted_app.inner):
            yield

    app = FastAPI(lifespan=lifespan)
    app.mount("/mcp", mounted_app)
    with TestClient(app) as client:
        response = client.post("/mcp/", json={"jsonrpc": "2.0", "id": 1,
            "method": "tools/list", "params": {}})
        assert response.status_code == 401

        class DB:
            calls = 0
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
            async def scalar(self, statement):
                DB.calls += 1
                return SimpleNamespace(id=uuid4(), revoked_at=None) if DB.calls % 2 else 0
            def add(self, record): pass
            async def commit(self): pass

        with patch("app.coach_mcp.async_session", new=lambda: DB()):
            response = client.post("/mcp/", headers={
                "Authorization": "Bearer stride_" + "a" * 48,
                "Accept": "application/json, text/event-stream",
                "Mcp-Protocol-Version": "2025-11-25"},
                json={"jsonrpc": "2.0", "id": 1,
                      "method": "tools/list", "params": {}})
        assert response.status_code == 200
        assert "propose_plan_change" in response.text


def test_cross_athlete_access_denied():
    async def run():
        credential_id, athlete_id = uuid4(), uuid4()
        marker = _caller.set(credential_id)
        try:
            db = SimpleNamespace(get=AsyncMock(return_value=SimpleNamespace(revoked_at=None, can_read=True)),
                                 scalar=AsyncMock(return_value=None), add=MagicMock(), commit=AsyncMock())
            with pytest.raises(PermissionError):
                await _grant(db, athlete_id)
            db.add.assert_not_called()
        finally:
            _caller.reset(marker)
    asyncio.run(run())


def test_ambiguous_identity_cannot_be_proposed():
    from app.coach_mcp import propose_plan_change
    async def run():
        with pytest.raises(ValueError):
            await propose_plan_change("Bryce", "latest", VALID, "Shift an easy session", "unique-request-key")
    asyncio.run(run())


def test_stale_version_cannot_apply_and_duplicate_acceptance_is_safe():
    async def run():
        athlete, proposal_id, old, newer = uuid4(), uuid4(), uuid4(), uuid4()
        row = SimpleNamespace(id=proposal_id, athlete_id=athlete, status="delivered",
            expected_plan_id=old, before_text=VALID, after_text=VALID.replace("8 km", "9 km"),
            diff={"timezone": "Pacific/Honolulu"}, credential_id=uuid4())
        db = SimpleNamespace(scalar=AsyncMock(side_effect=[SimpleNamespace(id=athlete), row]),
            add=MagicMock(), flush=AsyncMock())
        with patch("app.services.external_plan_service.plan_store.get_active",
                   new=AsyncMock(return_value=SimpleNamespace(id=newer, raw_plan_content=VALID))):
            with pytest.raises(ValueError, match="version changed"):
                await decide(db, athlete_id=athlete, proposal_id=proposal_id, accept=True)
        db.add.assert_not_called()
        row.status = "applied"
        db.scalar = AsyncMock(side_effect=[SimpleNamespace(id=athlete), row])
        with patch("app.services.external_plan_service.plan_store.save_plan", new=AsyncMock()) as save:
            assert await decide(db, athlete_id=athlete, proposal_id=proposal_id, accept=True) is row
            save.assert_not_awaited()
    asyncio.run(run())


def test_rejection_leaves_active_plan_unchanged():
    async def run():
        athlete, proposal_id, version = uuid4(), uuid4(), uuid4()
        row = SimpleNamespace(id=proposal_id, athlete_id=athlete, status="proposed",
            expected_plan_id=version, before_text=VALID, credential_id=uuid4(), applied_plan_id=None)
        db = SimpleNamespace(scalar=AsyncMock(side_effect=[SimpleNamespace(id=athlete), row]),
            add=MagicMock(), flush=AsyncMock())
        active = SimpleNamespace(id=version, raw_plan_content=VALID)
        with patch("app.services.external_plan_service.plan_store.get_active", new=AsyncMock(return_value=active)), \
             patch("app.services.external_plan_service.plan_store.save_plan", new=AsyncMock()) as save:
            result = await decide(db, athlete_id=athlete, proposal_id=proposal_id, accept=False)
            assert result.status == "rejected"
            save.assert_not_awaited()
    asyncio.run(run())


def test_accept_creates_one_version_then_phone_ack_marks_applied():
    async def run():
        athlete, proposal_id, version, next_version = uuid4(), uuid4(), uuid4(), uuid4()
        row = SimpleNamespace(id=proposal_id, athlete_id=athlete, status="delivered",
            expected_plan_id=version, before_text=VALID,
            after_text=VALID.replace("8 km", "9 km"), diff={"timezone": "Pacific/Honolulu"},
            credential_id=uuid4(), reason="Make Wednesday nine kilometres", applied_plan_id=None)
        active = SimpleNamespace(id=version, raw_plan_content=VALID, start_date=date(2026, 11, 2),
            race_type="marathon", race_date=date(2027, 1, 16), race_name="Synthetic Race",
            goal_time=None, custom_distance_km=None, fitness_level=None,
            client_plan_id=None, athlete_profile=None)
        db = SimpleNamespace(scalar=AsyncMock(side_effect=[SimpleNamespace(id=athlete), row]),
            add=MagicMock(), flush=AsyncMock())
        with patch("app.services.external_plan_service.plan_store.get_active", new=AsyncMock(return_value=active)), \
             patch("app.services.external_plan_service.plan_store.save_plan",
                   new=AsyncMock(return_value=SimpleNamespace(id=next_version))) as save:
            result = await decide(db, athlete_id=athlete, proposal_id=proposal_id, accept=True)
            assert result.status == "accepted"
            assert result.applied_plan_id == next_version
            save.assert_awaited_once()
        db.scalar = AsyncMock(return_value=row)
        with patch("app.services.external_plan_service.plan_store.get_active",
                   new=AsyncMock(return_value=SimpleNamespace(id=next_version))):
            assert (await mark_applied(db, athlete_id=athlete, proposal_id=proposal_id,
                                       applied_plan_id=next_version)).status == "applied"
    asyncio.run(run())


def test_notification_failure_keeps_proposal_pending():
    from app.coach_mcp import propose_plan_change
    async def run():
        credential, athlete, version = uuid4(), uuid4(), uuid4()
        user = SimpleNamespace(timezone_name="Pacific/Honolulu")
        row = SimpleNamespace(id=uuid4(), status="proposed", diff={"unified": []})
        class DB:
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
            async def get(self, cls, key): return user
            async def commit(self): pass
        marker = _caller.set(credential)
        try:
            with patch("app.coach_mcp.async_session", new=lambda: DB()), \
                 patch("app.coach_mcp._grant", new=AsyncMock()), \
                 patch("app.coach_mcp.propose", new=AsyncMock(return_value=row)), \
                 patch("app.coach_mcp.push_service.send_push", new=AsyncMock(side_effect=RuntimeError("APNs unavailable"))):
                result = await propose_plan_change(str(athlete), str(version), VALID, "Shift one easy run", "test-unique-key")
                assert result["status"] == "proposed"
                assert result["approval"] == "athlete_phone_required"
        finally:
            _caller.reset(marker)
    asyncio.run(run())
