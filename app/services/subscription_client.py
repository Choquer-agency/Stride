"""Route coaching LLM calls through a Claude subscription (Agent SDK).

Anthropic's June 2026 plan update grants Pro/Max accounts a monthly Agent SDK
credit that explicitly covers "third-party apps that authenticate with your
Claude subscription through the Agent SDK". With CLAUDE_CODE_OAUTH_TOKEN set,
eligible users' coaching calls ride that credit; anything else (other users,
errors, missing token) falls back to the metered API in AnthropicClient.

Credits are per-user, so eligibility is gated by SUBSCRIPTION_USER_IDS.
"""

import logging
import os
from typing import AsyncIterator, Optional

logger = logging.getLogger(__name__)


def enabled() -> bool:
    return bool(os.environ.get("CLAUDE_CODE_OAUTH_TOKEN"))


def user_eligible(user_id: Optional[str]) -> bool:
    """Per-user gating — credits belong to one subscription."""
    if not user_id:
        return False
    allowed = os.environ.get("SUBSCRIPTION_USER_IDS", "")
    return user_id in {u.strip() for u in allowed.split(",") if u.strip()}


def _options(system_prompt: str, model: Optional[str], partial: bool):
    from claude_agent_sdk import ClaudeAgentOptions

    return ClaudeAgentOptions(
        system_prompt=system_prompt,
        model=model,
        max_turns=1,
        allowed_tools=[],
        include_partial_messages=partial,
        env={"CLAUDE_CODE_OAUTH_TOKEN": os.environ["CLAUDE_CODE_OAUTH_TOKEN"]},
    )


async def generate(system_prompt: str, user_prompt: str, model: Optional[str] = None) -> str:
    """Non-streaming completion via the subscription. Raises on failure —
    callers fall back to the API path."""
    from claude_agent_sdk import query

    chunks: list[str] = []
    async for message in query(prompt=user_prompt,
                               options=_options(system_prompt, model, partial=False)):
        if type(message).__name__ == "AssistantMessage":
            for block in message.content:
                text = getattr(block, "text", None)
                if text:
                    chunks.append(text)
    result = "".join(chunks)
    if not result.strip():
        raise RuntimeError("subscription path returned empty response")
    return result


async def generate_stream(system_prompt: str, user_prompt: str,
                          model: Optional[str] = None) -> AsyncIterator[str]:
    """Streaming completion via the subscription (partial message events)."""
    from claude_agent_sdk import query

    yielded = False
    async for message in query(prompt=user_prompt,
                               options=_options(system_prompt, model, partial=True)):
        name = type(message).__name__
        if name == "StreamEvent":
            event = getattr(message, "event", None) or {}
            if event.get("type") == "content_block_delta":
                text = (event.get("delta") or {}).get("text")
                if text:
                    yielded = True
                    yield text
        elif name == "AssistantMessage" and not yielded:
            # Partial events unavailable — emit the full text once
            for block in message.content:
                text = getattr(block, "text", None)
                if text:
                    yielded = True
                    yield text
    if not yielded:
        raise RuntimeError("subscription stream produced no output")
