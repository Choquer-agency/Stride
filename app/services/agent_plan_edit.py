"""The shared active-plan edit path for local and remote coaching tools."""

import re

from sqlalchemy import text


WEEK = re.compile(r"^WEEK\s+(\d+)\b", re.IGNORECASE)
DAY = re.compile(r"^\s*[-*•]?\s*(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\s*:\s*(.+)$", re.IGNORECASE)


def validate_plan(content: str) -> None:
    """Check the week and day markers that the iOS PlanParser needs."""
    if not isinstance(content, str) or not 20 <= len(content) <= 200_000:
        raise ValueError("Plan must contain 20 to 200000 characters")
    weeks = []
    days_by_week = {}
    current = None
    for line in content.splitlines():
        match = WEEK.match(line)
        if match:
            current = int(match.group(1))
            if current != len(weeks) + 1 or current > 104:
                raise ValueError("Week headers must start a line and number consecutively from WEEK 1")
            weeks.append(current)
            days_by_week[current] = 0
        elif re.match(r"^\s+WEEK\s+\d+\b", line, re.I):
            raise ValueError("Week headers must start at the beginning of a line")
        elif DAY.match(line):
            if current is None:
                raise ValueError("A day line appears before WEEK 1")
            days_by_week[current] += 1
        elif re.match(r"^\s*[-*•]?\s*(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\s*:", line, re.I):
            raise ValueError("A day line needs workout text after the colon")
    if not weeks:
        raise ValueError("Plan needs a WEEK 1 header at the start of a line")
    if any(count == 0 for count in days_by_week.values()):
        raise ValueError("Every week needs at least one day line, such as '- Monday: Easy Run'")


async def update_active_plan(conn, plan: dict, new_content: str, change_note: str) -> None:
    """Update the current row in place so PlanSyncService offers its Apply card."""
    validate_plan(new_content)
    if not change_note or not change_note.strip():
        raise ValueError("change_note is required and is shown to the athlete")
    result = await conn.execute(text(
        "UPDATE training_plans SET raw_plan_content = :c, source = 'server_edit', "
        "change_note = :n, updated_at = now() WHERE id = :i AND is_active = true"
    ), {"c": new_content, "n": change_note.strip(), "i": plan["id"]})
    if result.rowcount != 1:
        raise ValueError("Active plan changed; fetch it again before editing")


async def replace_in_active_plan(conn, plan: dict, find: str, replace: str, change_note: str) -> None:
    if not find:
        raise ValueError("find must be a nonempty exact snippet")
    count = plan["raw_plan_content"].count(find)
    if count != 1:
        raise ValueError(f"find must match exactly once; matched {count} times")
    await update_active_plan(conn, plan, plan["raw_plan_content"].replace(find, replace), change_note)
