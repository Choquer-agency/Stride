"""Apply the versioned, idempotent run metrics migration at startup."""

from pathlib import Path

from sqlalchemy import text


MIGRATION = Path(__file__).resolve().parent.parent / "migrations" / "20261115_run_metrics_webhooks.sql"


async def apply_run_metrics_migration(conn) -> None:
    script = "\n".join(line for line in MIGRATION.read_text().splitlines()
                       if not line.lstrip().startswith("--"))
    for statement in script.split(";"):
        sql = statement.strip()
        if sql:
            await conn.execute(text(sql))
