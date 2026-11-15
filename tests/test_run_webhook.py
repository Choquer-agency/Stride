"""Run webhook isolation, deduplication, failure behavior, and migration tests."""

import asyncio
import json
import os
import unittest
import uuid
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://test:test@localhost/test")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret")

from sqlalchemy.orm import Session

from app.models.community_schemas import RunBatchSyncRequest
from app.models.run import Run
from app.models.user import User
from app.routes import runs
from app.services import run_webhook
from app.services.run_metrics_migration import apply_run_metrics_migration


def run_and_user():
    user_id, run_id = uuid.uuid4(), uuid.uuid4()
    user = User(id=user_id, email="first@example.com", name="First",
                run_webhook_url="https://coach.example.com/run",
                run_webhook_key="private-key", run_webhook_key_header="Authorization")
    run = Run(id=run_id, user_id=user_id, completed_at=datetime.now(timezone.utc),
              distance_km=5.0, duration_seconds=1800, avg_pace_sec_per_km=360,
              data_source="gps", elevation_gain_m=42.0, elevation_loss_m=38.0,
              hr_samples_json=json.dumps([{"t": i, "bpm": 140 + i % 10} for i in range(60)]),
              metrics_json={"elevation_profile": [{"t": i, "elevation_m": 50 + i}
                                                  for i in range(60)],
                            "route_points": [{"latitude": 49.0, "longitude": -123.0, "altitude": 50}]})
    return run, user


class FakeResult:
    def __init__(self, value=None):
        self.value = value

    def first(self):
        return self.value

    def scalar_one_or_none(self):
        return self.value


class FakeDeliveryDB:
    def __init__(self, pair, claim):
        self.pair = pair
        self.claim = claim
        self.calls = 0
        self.commit = AsyncMock()

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_):
        return False

    async def execute(self, _statement):
        self.calls += 1
        if self.calls == 1:
            return FakeResult(self.pair)
        return FakeResult(self.claim)


class FakeHTTP:
    def __init__(self, status=200):
        self.post = AsyncMock(return_value=SimpleNamespace(status_code=status))

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_):
        return False


class RunWebhookTests(unittest.IsolatedAsyncioTestCase):
    async def test_only_own_athlete_is_sent_and_deduped(self):
        run, user = run_and_user()
        first_db = FakeDeliveryDB((run, user), run.id)
        second_db = FakeDeliveryDB((run, user), None)
        http = FakeHTTP()
        with patch.object(run_webhook, "async_session", side_effect=[first_db, second_db]), \
             patch.object(run_webhook.httpx, "AsyncClient", return_value=http):
            await run_webhook.deliver_run_webhook(run.id, user.id, "run.completed")
            await run_webhook.deliver_run_webhook(run.id, user.id, "run.completed")
        http.post.assert_awaited_once()
        args = http.post.await_args
        self.assertEqual(args.args[0], user.run_webhook_url)
        self.assertEqual(args.kwargs["headers"], {"Authorization": "Bearer private-key"})
        self.assertEqual(args.kwargs["json"]["athlete_email"], user.email)
        self.assertEqual(args.kwargs["json"]["event"], "run.completed")
        self.assertEqual(len(args.kwargs["json"]["data"]["hr_samples"]), 12)
        self.assertNotIn("private-key", json.dumps(args.kwargs["json"]))
        first_db.commit.assert_awaited_once()

    async def test_no_webhook_and_wrong_athlete_send_nothing(self):
        run, user = run_and_user()
        no_url = User(id=user.id, email=user.email, run_webhook_url=None)
        missing_db = FakeDeliveryDB((run, no_url), run.id)
        wrong_db = FakeDeliveryDB(None, run.id)
        http = FakeHTTP()
        with patch.object(run_webhook, "async_session", side_effect=[missing_db, wrong_db]), \
             patch.object(run_webhook.httpx, "AsyncClient", return_value=http):
            await run_webhook.deliver_run_webhook(run.id, user.id, "run.completed")
            await run_webhook.deliver_run_webhook(run.id, uuid.uuid4(), "run.completed")
        http.post.assert_not_awaited()
        missing_db.commit.assert_not_awaited()
        wrong_db.commit.assert_not_awaited()

    async def test_delivery_failure_retries_without_raising_or_leaking_key(self):
        run, user = run_and_user()
        claim_db = FakeDeliveryDB((run, user), run.id)
        release_db = FakeDeliveryDB(None, run.id)
        http = FakeHTTP(status=503)
        with patch.object(run_webhook, "async_session", side_effect=[claim_db, release_db]), \
             patch.object(run_webhook.httpx, "AsyncClient", return_value=http), \
             patch.object(run_webhook.asyncio, "sleep", AsyncMock()) as sleep, \
             self.assertLogs(run_webhook.logger, level="WARNING") as logs:
            await run_webhook.deliver_run_webhook(run.id, user.id, "run.completed")
        self.assertEqual(http.post.await_count, 3)
        self.assertEqual(sleep.await_count, 2)
        self.assertNotIn("private-key", " ".join(logs.output))
        release_db.commit.assert_awaited_once()

    async def test_queue_starts_after_commit_and_clears_on_rollback(self):
        run, user = run_and_user()
        sent = AsyncMock()
        with patch.object(run_webhook, "deliver_run_webhook", sent):
            db = Session()
            run_webhook.queue_run_webhook(db, run.id, user.id, "run.completed")
            run_webhook.queue_run_webhook(db, run.id, user.id, "run.updated")
            sent.assert_not_awaited()
            db.commit()
            await asyncio.sleep(0)
            sent.assert_awaited_once_with(run.id, user.id, "run.completed")
            db.close()

            db = Session()
            db.begin()
            run_webhook.queue_run_webhook(db, run.id, user.id, "run.completed")
            db.rollback()
            db.commit()
            await asyncio.sleep(0)
            self.assertEqual(sent.await_count, 1)
            db.close()

    def test_payload_is_bounded_but_stored_data_is_unchanged(self):
        run, user = run_and_user()
        run.metrics_json["elevation_profile"] = [
            {"t": i, "elevation_m": i, "padding": "x" * 100} for i in range(10_000)
        ]
        original_count = len(run.metrics_json["elevation_profile"])
        payload = run_webhook.build_payload(run, user, "run.completed")
        self.assertLessEqual(len(run_webhook._encoded(payload)), run_webhook.PAYLOAD_LIMIT)
        self.assertEqual(len(run.metrics_json["elevation_profile"]), original_count)
        self.assertTrue(payload["data"]["truncated_for_webhook"])

    def test_webhook_config_requires_https_and_safe_header(self):
        with self.assertRaises(ValueError):
            run_webhook.validate_webhook_config("http://coach.example.com/run")
        with self.assertRaises(ValueError):
            run_webhook.validate_webhook_config("https://127.0.0.1/run")
        with self.assertRaises(ValueError):
            run_webhook.validate_webhook_config("https://coach.example.com/run", "Bad\nHeader")


class RunSyncTests(unittest.IsolatedAsyncioTestCase):
    def payload(self, **extras):
        run_id = uuid.uuid4()
        data = {"id": str(run_id), "completed_at": datetime.now(timezone.utc).isoformat(),
                "distance_km": 5, "duration_seconds": 1800, "avg_pace_sec_per_km": 360,
                "data_source": "gps"}
        data.update(extras)
        return RunBatchSyncRequest(runs=[data]), run_id

    async def test_legacy_sync_is_accepted_and_queues_completion(self):
        request, run_id = self.payload()
        db = SimpleNamespace(execute=AsyncMock(return_value=FakeResult(run_id)),
                             scalar=AsyncMock(), info={})
        user = SimpleNamespace(id=uuid.uuid4())
        with patch.object(runs, "queue_run_webhook") as queued, \
             patch.object(runs, "compute_personal_bests", AsyncMock()), \
             patch.object(runs, "check_challenge_participation", AsyncMock()), \
             patch.object(runs, "check_event_participation", AsyncMock()), \
             patch.object(runs, "log_activity", AsyncMock()), \
             patch.object(runs, "check_achievements_after_sync", AsyncMock(return_value=[])), \
             patch.object(runs.analytics, "capture"):
            response = await runs.sync_runs(request, user, db)
        self.assertEqual(response.synced_count, 1)
        self.assertTrue(response.metrics_stored)
        queued.assert_called_once_with(db, run_id, user.id, "run.completed")
        self.assertNotIn("metrics_json", str(db.execute.await_args_list[0].args[0]))

    async def test_metrics_backfill_updates_only_rich_fields(self):
        request, run_id = self.payload(metrics_json={"route_points": [{"latitude": 49.0}]},
                                       elevation_gain_m=12, metrics_backfill_only=True)
        db = SimpleNamespace(execute=AsyncMock(side_effect=[FakeResult(None), FakeResult(run_id)]),
                             scalar=AsyncMock(), info={})
        user = SimpleNamespace(id=uuid.uuid4())
        with patch.object(runs, "queue_run_webhook") as queued, patch.object(runs.analytics, "capture"):
            response = await runs.sync_runs(request, user, db)
        self.assertEqual(response.already_existed, 1)
        queued.assert_called_once_with(db, run_id, user.id, "run.updated")
        update_sql = str(db.execute.await_args_list[1].args[0])
        self.assertIn("metrics_json", update_sql)
        self.assertNotIn("distance_km =", update_sql)


class MigrationTests(unittest.IsolatedAsyncioTestCase):
    async def test_versioned_migration_only_adds_optional_columns(self):
        conn = SimpleNamespace(execute=AsyncMock())
        await apply_run_metrics_migration(conn)
        sql = [str(call.args[0]) for call in conn.execute.await_args_list]
        self.assertEqual(len(sql), 8)
        self.assertTrue(all("ADD COLUMN IF NOT EXISTS" in statement for statement in sql))
        self.assertFalse(any("NOT NULL" in statement for statement in sql))
        self.assertTrue(any("metrics_json JSONB" in statement for statement in sql))
        self.assertTrue(any("run_webhook_key TEXT" in statement for statement in sql))


if __name__ == "__main__":
    unittest.main()
