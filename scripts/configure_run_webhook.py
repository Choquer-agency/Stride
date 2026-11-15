"""Admin-only command to set or clear one athlete's run webhook."""

import argparse
import asyncio
import getpass
import os
import sys
from pathlib import Path

from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
load_dotenv()

from sqlalchemy import func, select  # noqa: E402

from app.database import async_session  # noqa: E402
from app.models.user import User  # noqa: E402
from app.services.run_webhook import validate_webhook_config  # noqa: E402


async def configure(email: str, url: str | None, key: str | None, header: str, clear: bool) -> None:
    async with async_session() as db:
        user = await db.scalar(select(User).where(func.lower(User.email) == email.lower()).with_for_update())
        if user is None:
            raise ValueError("Athlete email not found")
        if clear:
            user.run_webhook_url = None
            user.run_webhook_key = None
            user.run_webhook_key_header = "Authorization"
        else:
            if not url or not key:
                raise ValueError("A webhook URL and key are required")
            validate_webhook_config(url, header)
            user.run_webhook_url = url
            user.run_webhook_key = key
            user.run_webhook_key_header = header
        await db.commit()
    print(f"Run webhook {'cleared' if clear else 'configured'} for {email}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("email", help="Athlete email")
    parser.add_argument("--url", help="HTTPS webhook URL")
    parser.add_argument("--header", default="Authorization", help="Header receiving Bearer <key>")
    parser.add_argument("--key-env", help="Read the key from this environment variable")
    parser.add_argument("--clear", action="store_true", help="Remove this athlete's webhook")
    args = parser.parse_args()
    key = None if args.clear else (os.environ.get(args.key_env) if args.key_env else getpass.getpass("Webhook key: "))
    asyncio.run(configure(args.email, args.url, key, args.header, args.clear))


if __name__ == "__main__":
    main()
