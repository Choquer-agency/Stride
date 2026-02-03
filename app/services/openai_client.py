from openai import AsyncOpenAI
from typing import AsyncGenerator
from app.config import get_settings


class OpenAIClient:
    """Async OpenAI client for generating training plans."""
    
    def __init__(self):
        settings = get_settings()
        self.client = AsyncOpenAI(api_key=settings.openai_api_key)
        self.model = settings.openai_model
    
    async def generate_plan_stream(
        self,
        system_prompt: str,
        user_prompt: str
    ) -> AsyncGenerator[str, None]:
        """
        Generate a training plan with streaming response.
        
        Args:
            system_prompt: The coaching system prompt
            user_prompt: The athlete's specific details and request
            
        Yields:
            Chunks of the generated training plan text
        """
        stream = await self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            stream=True,
            temperature=0.7,
            max_tokens=16000  # Training plans can be long
        )
        
        async for chunk in stream:
            if chunk.choices[0].delta.content:
                yield chunk.choices[0].delta.content
    
    async def generate_plan(
        self,
        system_prompt: str,
        user_prompt: str
    ) -> str:
        """
        Generate a training plan without streaming (for testing).
        
        Args:
            system_prompt: The coaching system prompt
            user_prompt: The athlete's specific details and request
            
        Returns:
            The complete generated training plan
        """
        response = await self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            temperature=0.7,
            max_tokens=16000
        )
        
        return response.choices[0].message.content
