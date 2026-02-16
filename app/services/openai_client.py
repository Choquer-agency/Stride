import os
from typing import AsyncGenerator, Optional
from app.config import get_settings

# Set LangFuse env vars before importing the patched client
_settings = get_settings()
os.environ["LANGFUSE_PUBLIC_KEY"] = _settings.langfuse_public_key
os.environ["LANGFUSE_SECRET_KEY"] = _settings.langfuse_secret_key
os.environ["LANGFUSE_HOST"] = _settings.langfuse_host

from langfuse.openai import AsyncOpenAI


class OpenAIClient:
    """Async OpenAI client for generating training plans."""

    def __init__(self):
        settings = get_settings()
        self.client = AsyncOpenAI(api_key=settings.openai_api_key)
        self.model = settings.openai_model

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
        Generate a training plan with streaming response.

        Yields:
            Chunks of the generated training plan text
        """
        # LangFuse-specific kwargs (name/metadata are extracted by the wrapper)
        langfuse_kwargs = {}
        if name:
            langfuse_kwargs["name"] = name
        # Merge session_id into metadata so it appears in LangFuse traces
        merged_metadata = {**(metadata or {})}
        if session_id:
            merged_metadata["session_id"] = session_id
        if user_id:
            merged_metadata["user_id"] = user_id
        if merged_metadata:
            langfuse_kwargs["metadata"] = merged_metadata

        # OpenAI-native kwargs
        openai_kwargs = {}
        if user_id:
            openai_kwargs["user"] = user_id  # OpenAI's native user param

        stream = await self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            stream=True,
            temperature=0.7,
            max_tokens=16000,
            **langfuse_kwargs,
            **openai_kwargs,
        )

        async for chunk in stream:
            if chunk.choices[0].delta.content:
                yield chunk.choices[0].delta.content

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
        Generate a training plan without streaming (for testing).
        """
        langfuse_kwargs = {}
        if name:
            langfuse_kwargs["name"] = name
        merged_metadata = {**(metadata or {})}
        if session_id:
            merged_metadata["session_id"] = session_id
        if user_id:
            merged_metadata["user_id"] = user_id
        if merged_metadata:
            langfuse_kwargs["metadata"] = merged_metadata

        openai_kwargs = {}
        if user_id:
            openai_kwargs["user"] = user_id

        response = await self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            temperature=0.7,
            max_tokens=16000,
            **langfuse_kwargs,
            **openai_kwargs,
        )

        return response.choices[0].message.content
