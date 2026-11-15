"""Agent MCP authorization and active-plan write behavior without a database."""

import asyncio
import os
import unittest
from contextlib import asynccontextmanager
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://test:test@localhost/test")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret")

from fastapi import FastAPI
from fastapi.testclient import TestClient
from mcp.server.transport_security import TransportSecuritySettings

from app import agent_mcp
from app.agent_mcp_auth import AgentTokenMiddleware
from app.services.agent_plan_edit import replace_in_active_plan, update_active_plan


VALID_PLAN = "WEEK 1 [BASE] (Dates: Jan 1 - Jan 7)\n- Monday: Easy Run - Total: 5 km\n"


class AgentTokenTests(unittest.TestCase):
    def setUp(self):
        inner = FastAPI()

        @inner.get("/mcp/")
        async def mcp_get():
            return {"ok": True}

        @inner.post("/mcp/")
        async def mcp_post():
            return {"ok": True}

        self.client = TestClient(AgentTokenMiddleware(inner))

    def test_missing_wrong_correct_and_disabled(self):
        with patch.dict(os.environ, {"STRIDE_AGENT_TOKEN": "a-secret-token"}):
            for method in (self.client.get, self.client.post):
                self.assertEqual(method("/mcp/").status_code, 401)
                self.assertEqual(method("/mcp/", headers={"Authorization": "Bearer wrong"}).status_code, 401)
                self.assertEqual(method("/mcp/", headers={"Authorization": "Bearer a-secret-token"}).status_code, 200)
        with patch.dict(os.environ, {"STRIDE_AGENT_TOKEN": ""}):
            self.assertEqual(self.client.get("/mcp/", headers={"Authorization": "Bearer a-secret-token"}).status_code, 503)

    def test_gate_includes_preflight_and_mount_prefix(self):
        with patch.dict(os.environ, {"STRIDE_AGENT_TOKEN": "token"}):
            self.assertEqual(self.client.options("/mcp/", headers={"Origin": "https://example.com"}).status_code, 401)
            self.assertEqual(self.client.get("/mcp").status_code, 401)

    def test_streamable_http_tools_are_available_behind_token(self):
        @asynccontextmanager
        async def lifespan(_app):
            async with agent_mcp.server.session_manager.run():
                yield

        app = FastAPI(lifespan=lifespan)
        app.add_middleware(AgentTokenMiddleware)
        app.mount("/mcp", agent_mcp.server.streamable_http_app(
            streamable_http_path="/", stateless_http=True, json_response=True,
            transport_security=TransportSecuritySettings(allowed_hosts=["testserver"]),
        ))
        headers = {"Authorization": "Bearer test-token", "Accept": "application/json, text/event-stream"}
        with patch.dict(os.environ, {"STRIDE_AGENT_TOKEN": "test-token"}), TestClient(app) as client:
            denied = client.post("/mcp/", json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
            self.assertEqual(denied.status_code, 401)
            result = client.post("/mcp/", headers=headers,
                json={"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
            self.assertEqual(result.status_code, 200, result.text)
            names = {tool["name"] for tool in result.json()["result"]["tools"]}
            self.assertIn("update_plan", names)
            self.assertIn("get_garmin_workout", names)

            @asynccontextmanager
            async def transaction():
                yield object()

            with patch.object(agent_mcp, "engine", SimpleNamespace(begin=transaction)), \
                 patch.object(agent_mcp, "_active_plan", AsyncMock(return_value={"id": "plan-id"})):
                invalid = client.post("/mcp/", headers=headers, json={
                    "jsonrpc": "2.0", "id": 3, "method": "tools/call",
                    "params": {"name": "update_plan", "arguments": {
                        "new_content": "No week header, just a long and malformed plan",
                        "change_note": "Bad plan",
                    }},
                })
            self.assertEqual(invalid.status_code, 200, invalid.text)
            self.assertTrue(invalid.json()["result"]["isError"])
            self.assertIn("WEEK 1", invalid.text)


class PlanWriteTests(unittest.TestCase):
    def test_full_update_sets_existing_sync_fields(self):
        conn = SimpleNamespace(execute=AsyncMock(return_value=SimpleNamespace(rowcount=1)))
        plan = {"id": "plan-id", "raw_plan_content": VALID_PLAN}
        asyncio.run(update_active_plan(conn, plan, VALID_PLAN.replace("5 km", "6 km"), "More volume"))
        sql, params = conn.execute.await_args.args
        self.assertIn("source = 'server_edit'", str(sql))
        self.assertIn("updated_at = now()", str(sql))
        self.assertEqual(params["i"], "plan-id")
        self.assertEqual(params["n"], "More volume")
        self.assertIn("6 km", params["c"])

    def test_replace_uses_same_write_path(self):
        conn = SimpleNamespace(execute=AsyncMock(return_value=SimpleNamespace(rowcount=1)))
        plan = {"id": "plan-id", "raw_plan_content": VALID_PLAN}
        asyncio.run(replace_in_active_plan(conn, plan, "5 km", "7 km", "Longer run"))
        self.assertEqual(conn.execute.await_args.args[1]["c"], VALID_PLAN.replace("5 km", "7 km"))

    def test_malformed_plan_and_missing_note_never_write(self):
        conn = SimpleNamespace(execute=AsyncMock())
        plan = {"id": "plan-id", "raw_plan_content": VALID_PLAN}
        for content, note in (("No week header, just prose and workouts", "note"),
                              ("WEEK 1\nNo dated workout text", "note"),
                              (VALID_PLAN, "")):
            with self.subTest(content=content, note=note):
                with self.assertRaisesRegex(ValueError, "Plan|week|change_note"):
                    asyncio.run(update_active_plan(conn, plan, content, note))
        conn.execute.assert_not_awaited()

    def test_replace_requires_one_match_and_valid_result(self):
        conn = SimpleNamespace(execute=AsyncMock())
        plan = {"id": "plan-id", "raw_plan_content": VALID_PLAN}
        with self.assertRaisesRegex(ValueError, "matched 0"):
            asyncio.run(replace_in_active_plan(conn, plan, "missing", "x", "note"))
        with self.assertRaisesRegex(ValueError, "WEEK 1"):
            asyncio.run(replace_in_active_plan(conn, plan, "WEEK 1", "BLOCK 1", "note"))
        conn.execute.assert_not_awaited()

    def test_local_entry_point_uses_shared_server(self):
        from app.agent_mcp import server
        from scripts.stride_coach_mcp import server as local_server
        self.assertIs(local_server, server)

    def test_remote_update_uses_shared_write_function(self):
        conn = object()

        @asynccontextmanager
        async def transaction():
            yield conn

        fake_engine = SimpleNamespace(begin=transaction)
        with patch.object(agent_mcp, "engine", fake_engine), \
             patch.object(agent_mcp, "_active_plan", AsyncMock(return_value={"id": "plan-id"})), \
             patch.object(agent_mcp, "update_active_plan", AsyncMock()) as shared_write:
            asyncio.run(agent_mcp.update_plan(VALID_PLAN, "Changed schedule", "runner@example.com"))
        shared_write.assert_awaited_once_with(conn, {"id": "plan-id"}, VALID_PLAN, "Changed schedule")


if __name__ == "__main__":
    unittest.main()
