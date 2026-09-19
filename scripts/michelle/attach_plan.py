"""
Attach Michelle's coach-authored plan to her account.

Run AFTER she has signed up in the app:

    python scripts/michelle/attach_plan.py --email her@email.com
    # or, if she's simply the newest non-Bryce account:
    python scripts/michelle/attach_plan.py

Re-attach a revised plan.txt (new active row; her phone offers "Apply update"):

    python scripts/michelle/attach_plan.py --email her@email.com --source server_edit --note "What changed"

Inserts the generated plan as her active server-side plan; her phone adopts it
automatically the first time she opens the Plan tab (fresh-install adoption in
PlanSyncService). Also pins her weekly check-in to Monday (her rest day) and
sets her race persona for the coaching loops.
"""
import argparse
import asyncio
import json
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from dotenv import load_dotenv
load_dotenv(ROOT / ".env")

import sqlalchemy as sa

from app.database import async_session
from app.models.user import User  # noqa: F401 — registers `users` in metadata for the FK
from app.services import plan_store

HERE = Path(__file__).parent
BRYCE_EMAIL = "brycechoquer@me.com"


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--email", help="Michelle's account email (otherwise newest non-Bryce user)")
    parser.add_argument("--source", default="generated", choices=["generated", "server_edit"],
                        help="'server_edit' when re-attaching a revised plan.txt to an account that already has one")
    parser.add_argument("--note", default="Coach-authored starter plan — half marathon April 2027",
                        help="change_note shown in the app's 'Your coach updated your plan' card")
    args = parser.parse_args()

    plan_content = (HERE / "plan.txt").read_text()
    profile = json.loads((HERE / "athlete_profile.json").read_text())

    async with async_session() as db:
        if args.email:
            row = (await db.execute(
                sa.text("SELECT id, email, name FROM users WHERE lower(email) = lower(:e)"),
                {"e": args.email},
            )).first()
        else:
            row = (await db.execute(
                sa.text("SELECT id, email, name FROM users WHERE lower(email) != lower(:b) ORDER BY created_at DESC LIMIT 1"),
                {"b": BRYCE_EMAIL},
            )).first()

        if row is None:
            print("No matching user found — has she signed up in the app yet?")
            return

        user_id, email, name = row
        print(f"Attaching plan to: {name} <{email}> ({user_id})")

        await plan_store.save_plan(
            db,
            user_id,
            plan_content,
            source=args.source,
            race_type=profile["race_type"],
            race_date=date.fromisoformat(profile["race_date"]),
            race_name=profile.get("race_name"),
            goal_time=profile.get("goal_time"),
            start_date=date.fromisoformat(profile["start_date"]),
            fitness_level=profile.get("fitness_level"),
            change_note=args.note,
            athlete_profile=profile,
        )

        # Weekly check-in on Monday (her rest day); half-marathon coach persona.
        await db.execute(
            sa.text("UPDATE users SET checkin_day_of_week = 0, current_race_type = 'Half Marathon' WHERE id = :u"),
            {"u": user_id},
        )
        await db.commit()

    print("Done. Plan is active server-side — it will appear on her phone when she opens the Plan tab.")


if __name__ == "__main__":
    asyncio.run(main())
