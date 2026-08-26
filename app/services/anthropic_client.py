import base64
import time
import logging
from dataclasses import dataclass
from typing import AsyncGenerator, Optional

import anthropic
from langfuse import Langfuse

from app.config import get_settings

logger = logging.getLogger(__name__)


class ClaudeRefusalError(Exception):
    """Raised when Claude's safety classifiers decline a request (stop_reason == "refusal").

    Rare false positives can occur on benign content; callers should surface a
    friendly "try rephrasing" message rather than a server error.
    """

    def __init__(self, category: str | None = None):
        self.category = category
        super().__init__(f"Claude declined the request (category={category})")


@dataclass
class GenerationMetrics:
    """Metrics about a completed Claude generation, for coaching_events audit logging."""
    model: str
    input_tokens: int
    output_tokens: int
    latency_ms: int
    output_text: str


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
        # Most recent generation metrics, populated by every generate_*/stream call.
        # Useful when callers need tokens/latency for coaching_events without changing
        # the streaming yield protocol.
        self.last_metrics: GenerationMetrics | None = None

    async def generate_plan_stream(
        self,
        system_prompt: str,
        user_prompt: str,
        name: Optional[str] = None,
        user_id: Optional[str] = None,
        session_id: Optional[str] = None,
        metadata: Optional[dict] = None,
        model: Optional[str] = None,
    ) -> AsyncGenerator[str, None]:
        """
        Stream a response from Claude, yielding text chunks.
        Logs the full generation to LangFuse after streaming completes.

        Args:
            model: Override the default model for this call. Use values from
                   app.services.coaching_models (HAIKU/SONNET/OPUS constants).
        """
        start = time.time()

        # Subscription path (Agent SDK, per-user credit) with API fallback
        from app.services import subscription_client
        if subscription_client.enabled() and subscription_client.user_eligible(user_id):
            try:
                sub_output: list = []
                async for chunk in subscription_client.generate_stream(
                        system_prompt, user_prompt, model=model or self.model):
                    sub_output.append(chunk)
                    yield chunk
                self.last_metrics = GenerationMetrics(
                    model=model or self.model, input_tokens=0, output_tokens=0,
                    latency_ms=int((time.time() - start) * 1000),
                    output_text="".join(sub_output))
                return
            except Exception as exc:
                logger.warning("subscription stream failed (%s) — falling back to API", exc)

        full_output = []
        input_tokens = 0
        output_tokens = 0
        active_model = model or self.model

        async with self.client.messages.stream(
            model=active_model,
            # cache_control: system prompts are static per race type, so repeat
            # calls read the cached prefix at ~10% of input price.
            system=[{
                "type": "text",
                "text": system_prompt,
                "cache_control": {"type": "ephemeral"},
            }],
            messages=[{"role": "user", "content": user_prompt}],
            max_tokens=32000,
        ) as stream:
            async for text in stream.text_stream:
                full_output.append(text)
                yield text

            # Get final message for usage stats
            final_message = await stream.get_final_message()
            input_tokens = final_message.usage.input_tokens
            output_tokens = final_message.usage.output_tokens
            if final_message.stop_reason == "refusal":
                details = getattr(final_message, "stop_details", None)
                raise ClaudeRefusalError(getattr(details, "category", None))

        latency_ms = (time.time() - start) * 1000
        full_output_text = "".join(full_output)
        self.last_metrics = GenerationMetrics(
            model=active_model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            latency_ms=round(latency_ms),
            output_text=full_output_text,
        )

        # Log to LangFuse
        try:
            generation = self.langfuse.start_generation(
                name=name or "anthropic-generation",
                model=active_model,
                input=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                output=full_output_text,
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
        model: Optional[str] = None,
    ) -> str:
        """
        Generate a full response without streaming.

        Args:
            model: Override the default model for this call.
        """
        start = time.time()
        active_model = model or self.model

        # Subscription path (Agent SDK, per-user credit) with API fallback
        from app.services import subscription_client
        if subscription_client.enabled() and subscription_client.user_eligible(user_id):
            try:
                text = await subscription_client.generate(
                    system_prompt, user_prompt, model=active_model)
                self.last_metrics = GenerationMetrics(
                    model=active_model, input_tokens=0, output_tokens=0,
                    latency_ms=int((time.time() - start) * 1000),
                    output_text=text)
                return text
            except Exception as exc:
                logger.warning("subscription path failed (%s) — falling back to API", exc)

        response = await self.client.messages.create(
            model=active_model,
            system=[{
                "type": "text",
                "text": system_prompt,
                "cache_control": {"type": "ephemeral"},
            }],
            messages=[{"role": "user", "content": user_prompt}],
            max_tokens=16000,
        )

        if response.stop_reason == "refusal":
            details = getattr(response, "stop_details", None)
            raise ClaudeRefusalError(getattr(details, "category", None))

        latency_ms = (time.time() - start) * 1000
        output_text = next(
            (block.text for block in response.content if block.type == "text"), ""
        )
        self.last_metrics = GenerationMetrics(
            model=active_model,
            input_tokens=response.usage.input_tokens,
            output_tokens=response.usage.output_tokens,
            latency_ms=round(latency_ms),
            output_text=output_text,
        )

        try:
            generation = self.langfuse.start_generation(
                name=name or "anthropic-generation",
                model=active_model,
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

    async def analyze_image(
        self,
        image_bytes: bytes,
        prompt: str,
        media_type: str = "image/jpeg",
        name: Optional[str] = None,
        user_id: Optional[str] = None,
        model: Optional[str] = None,
    ) -> str:
        """
        Send an image plus a prompt to Claude vision; return the text response.
        Used by Phase 6 nutrition photo parsing.

        Args:
            image_bytes: Raw image bytes.
            prompt: Instruction prompt for the vision model.
            media_type: MIME type — "image/jpeg" | "image/png" | "image/webp" | "image/gif".
            model: Override the model. Default uses self.model.
        """
        start = time.time()
        active_model = model or self.model
        encoded = base64.standard_b64encode(image_bytes).decode("utf-8")

        response = await self.client.messages.create(
            model=active_model,
            max_tokens=2048,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": encoded,
                            },
                        },
                        {"type": "text", "text": prompt},
                    ],
                }
            ],
        )

        if response.stop_reason == "refusal":
            details = getattr(response, "stop_details", None)
            raise ClaudeRefusalError(getattr(details, "category", None))

        latency_ms = (time.time() - start) * 1000
        output_text = next(
            (block.text for block in response.content if block.type == "text"), ""
        )
        self.last_metrics = GenerationMetrics(
            model=active_model,
            input_tokens=response.usage.input_tokens,
            output_tokens=response.usage.output_tokens,
            latency_ms=round(latency_ms),
            output_text=output_text,
        )

        try:
            generation = self.langfuse.start_generation(
                name=name or "anthropic-vision",
                model=active_model,
                input=[{"role": "user", "content": "[image] " + prompt[:200]}],
                output=output_text,
                usage_details={
                    "input": response.usage.input_tokens,
                    "output": response.usage.output_tokens,
                },
                metadata={
                    "provider": "anthropic",
                    "latency_ms": round(latency_ms),
                    "user_id": user_id,
                    "media_type": media_type,
                },
            )
            generation.end()
            self.langfuse.flush()
        except Exception:
            logger.exception("LangFuse logging failed for vision: %s", name)

        logger.info(
            "Claude vision: %s — %d input, %d output tokens, %.0fms",
            name, response.usage.input_tokens, response.usage.output_tokens, latency_ms,
        )
        return output_text
