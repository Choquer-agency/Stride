"""Exercise actual SQL boundaries on independent connections, without Google.

SQLite is a local concurrency regression, not a substitute for a PostgreSQL
migration rehearsal against production's existing rows.
"""
import asyncio
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import hashlib
import tempfile
import threading
import unittest

from sqlalchemy import Column, MetaData, String, Table, create_engine, select
from sqlalchemy.exc import IntegrityError

from app.models.fitbit_oauth_attempt import FitbitOAuthAttempt
from app.models.user import User
from app.routes.fitbit import _consume_oauth_attempt


class SessionAdapter:
    def __init__(self, connection):
        self.connection = connection

    async def execute(self, statement):
        return self.connection.execute(statement)

    async def commit(self):
        self.connection.commit()


class OAuthDatabaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.engine = create_engine('sqlite:///' + self.temp.name + '/oauth.db')
        self.metadata = MetaData()
        self.attempts = FitbitOAuthAttempt.__table__.to_metadata(self.metadata)
        # Use the real identity column declaration (including its unique index),
        # omitting unrelated PostgreSQL-only user columns.
        self.users = Table('users', self.metadata, Column('id', String, primary_key=True),
                           User.__table__.c.fitbit_health_user_id._copy(),
                           Column('access_token', String), Column('refresh_token', String))
        self.metadata.create_all(self.engine)

    def tearDown(self):
        self.engine.dispose()
        self.temp.cleanup()

    def add_attempt(self, nonce='nonce', user='user', seconds=300):
        with self.engine.begin() as conn:
            conn.execute(self.attempts.insert().values(
                nonce_hash=hashlib.sha256(nonce.encode()).hexdigest(), user_id=user,
                expires_at=datetime.now(timezone.utc) + timedelta(seconds=seconds)))

    def consume(self, nonce='nonce', user='user'):
        with self.engine.connect() as conn:
            return asyncio.run(_consume_oauth_attempt(SessionAdapter(conn), nonce, user))

    def test_consumption_is_durable_across_sessions_and_restart(self):
        self.add_attempt()
        self.assertTrue(self.consume())
        self.engine.dispose()
        self.assertFalse(self.consume())

    def test_expired_and_wrong_user_cannot_consume(self):
        self.add_attempt(seconds=-1)
        self.assertFalse(self.consume())
        self.add_attempt(nonce='valid')
        self.assertFalse(self.consume('valid', 'other-user'))
        self.assertTrue(self.consume('valid'))

    def test_concurrent_callbacks_have_exactly_one_winner(self):
        self.add_attempt()
        barrier = threading.Barrier(2)
        def run(_):
            barrier.wait()
            return self.consume()
        with ThreadPoolExecutor(2) as pool:
            self.assertEqual(sorted(pool.map(run, range(2))), [False, True])

    def test_concurrent_identity_claim_rolls_back_losing_token_pair(self):
        barrier = threading.Barrier(2)
        def claim(user):
            with self.engine.connect() as conn:
                # Both see an unclaimed identity before either writes.
                self.assertIsNone(conn.execute(select(self.users.c.id).where(
                    self.users.c.fitbit_health_user_id == 'same-health')).scalar())
                conn.commit()
                barrier.wait()
                try:
                    conn.execute(self.users.insert().values(id=user,
                        fitbit_health_user_id='same-health', access_token=user+'-access',
                        refresh_token=user+'-refresh'))
                    conn.commit()
                    return True
                except IntegrityError:
                    conn.rollback()
                    return False
        with ThreadPoolExecutor(2) as pool:
            self.assertEqual(sorted(pool.map(claim, ['carson', 'michelle'])), [False, True])
        with self.engine.connect() as conn:
            rows = conn.execute(select(self.users)).mappings().all()
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]['access_token'], rows[0]['id']+'-access')
            self.assertEqual(rows[0]['refresh_token'], rows[0]['id']+'-refresh')


if __name__ == '__main__':
    unittest.main()
