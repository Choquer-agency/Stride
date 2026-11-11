"""Auth gates tested without network calls or a live database."""
import unittest
import uuid
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.database import get_db
from app.routes import auth
from app.services.auth_service import create_access_token, decode_access_token


class AppleOnlyAuthTests(unittest.TestCase):
    def setUp(self):
        self.user = SimpleNamespace(
            id=uuid.uuid4(), email="existing@example.com", name="Runner",
            auth_provider="email", apple_user_identifier="apple-sub",
            created_at=datetime.now(timezone.utc), has_completed_profile=True,
            date_of_birth=None, gender=None, height_cm=None,
        )
        self.db = AsyncMock()
        self.db.add = Mock()
        self.db.execute.return_value = SimpleNamespace(scalar_one_or_none=lambda: self.user)
        self.app = FastAPI()
        self.app.include_router(auth.router)
        async def database():
            yield self.db
        self.app.dependency_overrides[get_db] = database
        self.client = TestClient(self.app)

    def test_legacy_login_and_signup_denied_without_database(self):
        for path in ("register", "login", "google"):
            for body in ({}, {"email": "existing@example.com", "password": "password123", "id_token": "token"}):
                with self.subTest(path=path, body=body):
                    response = self.client.post(f"/auth/{path}", json=body)
                    self.assertEqual(response.status_code, 403)
                    self.assertIn("Apple", response.json()["detail"])
        self.db.execute.assert_not_called()

    def apple_request(self, claims, identifier="apple-sub", email="untrusted@example.com"):
        with patch.object(auth, "verify_apple_token", AsyncMock(return_value=claims)):
            return self.client.post("/auth/apple", json={
                "identity_token": "verified-by-mock", "user_identifier": identifier, "email": email,
            })

    def test_apple_login_keeps_existing_account(self):
        response = self.apple_request({"sub": "apple-sub", "email": self.user.email})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(decode_access_token(response.json()["access_token"]), self.user.id)
        self.db.add.assert_not_called()

    def test_apple_signup_creates_apple_account(self):
        self.db.execute.return_value = SimpleNamespace(scalar_one_or_none=lambda: None)
        async def refresh(user):
            user.id = uuid.uuid4()
            user.created_at = datetime.now(timezone.utc)
            user.has_completed_profile = False
            user.leaderboard_opt_in = False
        self.db.refresh.side_effect = refresh
        response = self.apple_request({"sub": "apple-sub", "email": "signed@example.com"})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["user"]["auth_provider"], "apple")
        self.assertEqual(response.json()["user"]["email"], "signed@example.com")

    def test_apple_subject_mismatch_denied_before_lookup(self):
        for subject in (None, "other-apple-sub"):
            response = self.apple_request({"sub": subject})
            self.assertEqual(response.status_code, 401)
        self.db.execute.assert_not_called()

    def test_email_linking_uses_signed_email(self):
        self.db.execute.side_effect = [
            SimpleNamespace(scalar_one_or_none=lambda: None),
            SimpleNamespace(scalar_one_or_none=lambda: self.user),
        ]
        response = self.apple_request({"sub": "apple-sub", "email": "signed@example.com"})
        self.assertEqual(response.status_code, 200, response.text)
        query = self.db.execute.call_args_list[1].args[0]
        self.assertIn("signed@example.com", query.compile().params.values())
        self.assertNotIn("untrusted@example.com", query.compile().params.values())

    def test_existing_email_provider_session_still_reads_profile(self):
        token = create_access_token(self.user.id)
        response = self.client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["auth_provider"], "email")

    def test_profile_update_still_available_to_existing_session(self):
        response = self.client.put("/auth/profile", json={"name": "Updated"}, headers={
            "Authorization": f"Bearer {create_access_token(self.user.id)}",
        })
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["name"], "Updated")


if __name__ == "__main__":
    unittest.main()
