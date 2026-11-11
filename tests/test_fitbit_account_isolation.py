"""Focused Fitbit OAuth boundary regressions; no live Google calls."""
import unittest
from unittest.mock import patch, AsyncMock, Mock
from urllib.parse import parse_qs, urlparse
from types import SimpleNamespace

from starlette.requests import Request
from app.routes import fitbit
from app.services.fitbit_service import GoogleHealthClient


class FitbitIsolationTests(unittest.IsolatedAsyncioTestCase):
    def test_account_selection_is_explicit(self):
        with patch('app.services.fitbit_service.get_settings', return_value=SimpleNamespace(google_health_client_id='test')):
            url = GoogleHealthClient.build_authorize_url(redirect_uri='https://example.com/callback', state='state')
        params = parse_qs(urlparse(url).query)
        self.assertEqual(set(params['prompt'][0].split()), {'consent', 'select_account'})
        self.assertEqual(params['access_type'], ['offline'])

    async def test_callback_rejects_other_browser_before_opening_database(self):
        serializer = SimpleNamespace(loads=lambda *a, **k: {'user_id': 'carson', 'browser_nonce': 'original'})
        request = Request({'type': 'http', 'headers': [(b'cookie', b'fitbit_oauth=another')]})
        with patch.object(fitbit, '_state_serializer', return_value=serializer), patch.object(fitbit, 'async_session') as session:
            response = await fitbit.callback(request, code='code', state='state')
        session.assert_not_called()
        self.assertIn(b'Authorization browser changed', response.body)
        self.assertEqual(response.headers['cache-control'], 'no-store')

    async def test_missing_refresh_token_does_not_mutate_existing_link(self):
        user = SimpleNamespace(fitbit_access_token='old-access', fitbit_refresh_token='old-refresh')
        db = AsyncMock()
        db.get.return_value = user
        context = AsyncMock()
        context.__aenter__.return_value = db
        client = Mock()
        client.exchange_code = AsyncMock(return_value={'access_token': 'new-account-access'})
        serializer = SimpleNamespace(loads=lambda *a, **k: {'user_id': 'carson', 'browser_nonce': 'original'})
        request = Request({'type': 'http', 'headers': [(b'cookie', b'fitbit_oauth=original')]})
        with patch.object(fitbit, '_consume_oauth_attempt', new=AsyncMock(return_value=True)), patch.object(fitbit, '_state_serializer', return_value=serializer), patch.object(fitbit, 'async_session', return_value=context), patch.object(fitbit.fitbit_service, 'GoogleHealthClient', return_value=client):
            response = await fitbit.callback(request, code='code', state='state')
        self.assertIn(b'offline access', response.body)
        self.assertEqual(user.fitbit_access_token, 'old-access')
        self.assertEqual(user.fitbit_refresh_token, 'old-refresh')
        db.commit.assert_not_called()

    async def test_consumed_callback_never_exchanges_code(self):
        db = AsyncMock()
        context = AsyncMock()
        context.__aenter__.return_value = db
        serializer = SimpleNamespace(loads=lambda *a, **k: {'user_id': 'carson', 'browser_nonce': 'original'})
        request = Request({'type': 'http', 'headers': [(b'cookie', b'fitbit_oauth=original')]})
        with patch.object(fitbit, '_consume_oauth_attempt', new=AsyncMock(return_value=False)), patch.object(fitbit, '_state_serializer', return_value=serializer), patch.object(fitbit, 'async_session', return_value=context), patch.object(fitbit.fitbit_service, 'GoogleHealthClient') as client:
            response = await fitbit.callback(request, code='code', state='state')
        client.assert_not_called()
        self.assertIn(b'already used or expired', response.body)

    async def test_database_conflict_rolls_back_and_does_not_start_backfill(self):
        from sqlalchemy.exc import IntegrityError
        user = SimpleNamespace(id='carson')
        db = AsyncMock()
        db.add = Mock()
        db.get.return_value = user
        result = Mock()
        result.scalars.return_value.first.return_value = None
        db.execute.return_value = result
        db.commit.side_effect = IntegrityError('update', {}, Exception('unique violation'))
        context = AsyncMock()
        context.__aenter__.return_value = db
        client = Mock()
        client.exchange_code = AsyncMock(return_value={'access_token': 'access', 'refresh_token': 'refresh'})
        client.get_identity = AsyncMock(return_value={'healthUserId': 'claimed'})
        serializer = SimpleNamespace(loads=lambda *a, **k: {'user_id': 'carson', 'browser_nonce': 'original'})
        request = Request({'type': 'http', 'headers': [(b'cookie', b'fitbit_oauth=original')]})
        with patch.object(fitbit, '_consume_oauth_attempt', new=AsyncMock(return_value=True)), patch.object(fitbit, '_state_serializer', return_value=serializer), patch.object(fitbit, 'async_session', return_value=context), patch.object(fitbit.fitbit_service, 'GoogleHealthClient', return_value=client), patch.object(fitbit.asyncio, 'create_task') as task:
            response = await fitbit.callback(request, code='code', state='state')
        db.rollback.assert_awaited_once()
        task.assert_not_called()
        self.assertIn(b'could not be linked', response.body)

    def test_provider_error_is_escaped_and_cookie_cleared(self):
        response = fitbit._callback_html(success=False, message='<script>secret</script>')
        self.assertNotIn(b'<script>secret', response.body)
        self.assertIn('Max-Age=0', response.headers['set-cookie'])


if __name__ == '__main__':
    unittest.main()
