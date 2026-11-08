"""Manual provisioning for the isolated coach MCP service. Never run casually on production."""
import argparse
import asyncio
import hashlib
import secrets
from datetime import datetime, timezone
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import select

from app.database import async_session
from app.models.coach_access import CoachAccessAudit, CoachAthleteGrant, CoachCredential
from app.models.user import User


async def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("create")
    create.add_argument("--owner-id", type=UUID, required=True)
    create.add_argument("--athlete-id", type=UUID, action="append", required=True)
    create.add_argument("--label", required=True)
    create.add_argument("--propose", action="store_true")
    revoke = commands.add_parser("revoke")
    revoke.add_argument("--credential-id", type=UUID, required=True)
    revoke_athlete = commands.add_parser("revoke-athlete")
    revoke_athlete.add_argument("--credential-id", type=UUID, required=True)
    revoke_athlete.add_argument("--athlete-id", type=UUID, required=True)
    tz = commands.add_parser("set-timezone")
    tz.add_argument("--athlete-id", type=UUID, required=True)
    tz.add_argument("--timezone", required=True)
    args = parser.parse_args()
    async with async_session() as db:
        if args.command == "create":
            owner = await db.get(User, args.owner_id)
            if not owner or not 1 <= len(args.label) <= 100:
                raise ValueError("Owner or label invalid")
            athletes = set(args.athlete_id)
            for athlete_id in athletes:
                if await db.get(User, athlete_id) is None:
                    raise ValueError(f"Unknown athlete {athlete_id}")
            token = "stride_" + secrets.token_urlsafe(48)
            cred = CoachCredential(owner_user_id=args.owner_id,
                token_hash=hashlib.sha256(token.encode()).hexdigest(),
                label=args.label, can_read=True, can_propose=args.propose)
            db.add(cred)
            await db.flush()
            for athlete_id in athletes:
                db.add(CoachAthleteGrant(credential_id=cred.id, athlete_id=athlete_id,
                    can_read=True, can_propose=args.propose))
                db.add(CoachAccessAudit(credential_id=cred.id, athlete_id=athlete_id,
                    action="grant_created"))
            await db.commit()
            print(f"credential_id={cred.id}\napi_key={token}")  # shown once; never stored in plaintext
        elif args.command == "revoke":
            cred = await db.get(CoachCredential, args.credential_id)
            if cred is None:
                raise ValueError("Credential not found")
            cred.revoked_at = datetime.now(timezone.utc)
            db.add(CoachAccessAudit(credential_id=cred.id, action="credential_revoked"))
            await db.commit()
            print(f"revoked={cred.id}")
        elif args.command == "revoke-athlete":
            grant = await db.scalar(select(CoachAthleteGrant).where(
                CoachAthleteGrant.credential_id == args.credential_id,
                CoachAthleteGrant.athlete_id == args.athlete_id))
            if grant is None:
                raise ValueError("Grant not found")
            grant.revoked_at = datetime.now(timezone.utc)
            db.add(CoachAccessAudit(credential_id=args.credential_id,
                athlete_id=args.athlete_id, action="grant_revoked"))
            await db.commit()
            print(f"grant_revoked={args.credential_id}:{args.athlete_id}")
        else:
            ZoneInfo(args.timezone)
            athlete = await db.get(User, args.athlete_id)
            if athlete is None:
                raise ValueError("Athlete not found")
            athlete.timezone_name = args.timezone
            await db.commit()
            print(f"timezone_set={athlete.id}")


if __name__ == "__main__":
    asyncio.run(main())
