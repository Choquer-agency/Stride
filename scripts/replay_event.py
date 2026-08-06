"""
Replay a logged coaching event by re-running the prompt from coaching_events.llm_input.
Compares the new output to the original — useful for debugging regressions when prompts change.

Usage:
    python scripts/replay_event.py <event_id>
    python scripts/replay_event.py <event_id> --diff
    python scripts/replay_event.py <event_id> --model claude-haiku-4-5-20251001
"""

import argparse
import asyncio
import difflib
import sys
from pathlib import Path
from uuid import UUID

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from app.database import async_session
from app.models.coaching_event import CoachingEvent
from app.services.anthropic_client import AnthropicClient


async def main(args: argparse.Namespace) -> int:
    async with async_session() as db:
        event = await db.get(CoachingEvent, UUID(args.event_id))
        if not event:
            print(f"Event not found: {args.event_id}", file=sys.stderr)
            return 1

        if not event.llm_input or not event.llm_output:
            print(f"Event {event.id} has no llm_input/llm_output to replay (event_type={event.event_type})", file=sys.stderr)
            return 1

        print(f"Event: {event.id}")
        print(f"Type: {event.event_type}")
        print(f"Triggered: {event.triggered_at.isoformat()}")
        print(f"Prompt used: {event.prompt_used}")
        print(f"Original model: {event.llm_model_used}")
        print(f"Replay model:   {args.model or event.llm_model_used or '(default)'}")
        print(f"Input tokens:   {event.llm_input_tokens}, Output tokens: {event.llm_output_tokens}")
        print("---")

        # The llm_input column stores user_prompt only in our v2 schema
        # (system_prompt is reconstructed from prompt_used + memo at the time of replay).
        # For v2 simplicity, we treat the stored input as a single user prompt and pass
        # an empty system prompt — sufficient for diffing output drift, not for round-trip exactness.
        client = AnthropicClient()
        new_output = await client.generate_plan(
            system_prompt="",
            user_prompt=event.llm_input,
            name=f"replay-{event.event_type}",
            model=args.model or event.llm_model_used,
            metadata={"replayed_event_id": str(event.id)},
        )

    print("REPLAYED OUTPUT:")
    print(new_output)
    print("---")

    if args.diff:
        print("DIFF vs original:")
        original_lines = event.llm_output.splitlines()
        new_lines = new_output.splitlines()
        diff = difflib.unified_diff(
            original_lines, new_lines,
            fromfile="original", tofile="replay",
            lineterm="",
        )
        for line in diff:
            print(line)

    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Re-run a logged coaching event's prompt.")
    parser.add_argument("event_id", help="UUID of the coaching event to replay")
    parser.add_argument("--diff", action="store_true", help="Show unified diff vs original output")
    parser.add_argument("--model", default=None, help="Override the replay model (default: same as original)")
    args = parser.parse_args()
    sys.exit(asyncio.run(main(args)))
