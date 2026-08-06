"""
Send a test APNs push to a specific user. Verifies APNs setup end-to-end.

Usage:
    python scripts/send_test_push.py <user_id_or_email> "Title" "Body" [deep_link]
    python scripts/send_test_push.py bryce@example.com "Hello coach" "Testing push" stride://coach/inbox
    python scripts/send_test_push.py 6f4a8c7b-... "Critical" "Force critical send" --critical

Bypasses normal coaching-mode/quiet-hours checks via force_critical when --critical flag set.
"""

import argparse
import asyncio
import sys
from pathlib import Path
from uuid import UUID

# Allow running from anywhere — append project root to sys.path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from sqlalchemy import select
from app.database import async_session
from app.models.user import User
from app.services.push_service import send_push


async def find_user(identifier: str) -> User | None:
    async with async_session() as db:
        # Try as UUID first, then as email
        try:
            uid = UUID(identifier)
            return await db.get(User, uid)
        except ValueError:
            result = await db.execute(select(User).where(User.email == identifier))
            return result.scalar_one_or_none()


async def main(args: argparse.Namespace) -> int:
    user = await find_user(args.user)
    if not user:
        print(f"User not found: {args.user}", file=sys.stderr)
        return 1
    if not user.apns_device_token:
        print(f"User {user.email} has no apns_device_token. Open the app once to register.", file=sys.stderr)
        return 1

    async with async_session() as db:
        delivered, reason = await send_push(
            db, user,
            title=args.title,
            body=args.body,
            deep_link=args.deep_link,
            notification_type="test",
            loop_name=args.loop,
            force_critical=args.critical,
        )

    print(f"delivered={delivered} reason={reason}")
    return 0 if delivered else 2


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Send a test APNs push.")
    parser.add_argument("user", help="User UUID or email")
    parser.add_argument("title", help="Notification title")
    parser.add_argument("body", help="Notification body")
    parser.add_argument("deep_link", nargs="?", default=None, help="Optional stride:// deep link")
    parser.add_argument("--critical", action="store_true", help="Force critical (bypass shadow/quiet/rate)")
    parser.add_argument("--loop", default=None, help="Loop name to check coaching_modes against")
    args = parser.parse_args()
    sys.exit(asyncio.run(main(args)))
