import time
import logging
from typing import AsyncGenerator, Optional

import anthropic
from langfuse import Langfuse

from app.config import get_settings

logger = logging.getLogger(__name__)


class AnthropicClient:
    """Async Anthropic client with LangFuse observability."""

    def __init__(self):
        settings = get_settings()
        self.client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
        self.model = settings.anthropic_model
        self.langfuse = Langfuse(
            public_key=settings.langfuse_public_key,
            secret_key=settings.langfuse_secret_key,
            host=settings.langfuse_host,
        )

    async def generate_plan_stream(
        self,
        system_prompt: str,
        user_prompt: str,
        name: Optional[str] = None,
        user_id: Optional[str] = None,
        session_id: Optional[str] = None,
        metadata: Optional[dict] = None,
    ) -> AsyncGenerator[str, None]:
        """
        Stream a response from Claude, yielding text chunks.
        Logs the full generation to LangFuse after streaming completes.
        """
        start = time.time()
        full_output = []
        input_tokens = 0
        output_tokens = 0

        async with self.client.messages.stream(
            model=self.model,
            system=system_prompt,
            messages=[{"role": "user", "content": user_prompt}],
            temperature=0.7,
            max_tokens=16000,
        ) as stream:
            async for text in stream.text_stream:
                full_output.append(text)
                yield text

            # Get final message for usage stats
            final_message = await stream.get_final_message()
            input_tokens = final_message.usage.input_tokens
            output_tokens = final_message.usage.output_tokens

        latency_ms = (time.time() - start) * 1000

        # Log to LangFuse
        try:
            generation = self.langfuse.start_generation(
                name=name or "anthropic-generation",
                model=self.model,
                input=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                output="".join(full_output),
                usage_details={
                    "input": input_tokens,
                    "output": output_tokens,
                },
                metadata={
                    **(metadata or {}),
                    "provider": "anthropic",
                    "latency_ms": round(latency_ms),
                    "session_id": session_id,
                    "user_id": user_id,
                },
            )
            generation.end()
            self.langfuse.flush()
        except Exception:
            logger.exception("LangFuse logging failed for: %s", name)

        logger.info(
            "Claude complete: %s — %d input, %d output tokens, %.0fms",
            name, input_tokens, output_tokens, latency_ms,
        )

    async def generate_plan(
        self,
        system_prompt: str,
        user_prompt: str,
        name: Optional[str] = None,
        user_id: Optional[str] = None,
        session_id: Optional[str] = None,
        metadata: Optional[dict] = None,
    ) -> str:
        """
        Generate a full response without streaming.
        """
        start = time.time()

        response = await self.client.messages.create(
            model=self.model,
            system=system_prompt,
            messages=[{"role": "user", "content": user_prompt}],
            temperature=0.7,
            max_tokens=16000,
        )

        latency_ms = (time.time() - start) * 1000
        output_text = response.content[0].text

        try:
            generation = self.langfuse.start_generation(
                name=name or "anthropic-generation",
                model=self.model,
                input=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                output=output_text,
                usage_details={
                    "input": response.usage.input_tokens,
                    "output": response.usage.output_tokens,
                },
                metadata={
                    **(metadata or {}),
                    "provider": "anthropic",
                    "latency_ms": round(latency_ms),
                    "session_id": session_id,
                    "user_id": user_id,
                },
            )
            generation.end()
            self.langfuse.flush()
        except Exception:
            logger.exception("LangFuse logging failed for: %s", name)

        logger.info(
            "Claude complete: %s — %d input, %d output tokens, %.0fms",
            name, response.usage.input_tokens, response.usage.output_tokens, latency_ms,
        )
        return output_text
