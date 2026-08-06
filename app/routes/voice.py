"""Authenticated proxy for short, dynamic coaching phrases."""

import httpx
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field

from app.config import get_settings
from app.models.user import User
from app.services.auth_service import get_current_user


router = APIRouter(prefix="/api/voice", tags=["voice"])


class SpeechRequest(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    voice_id: str | None = Field(default=None, min_length=10, max_length=64)


@router.post("/speech")
async def synthesize_speech(
    request: SpeechRequest,
    _current_user: User = Depends(get_current_user),
) -> Response:
    settings = get_settings()
    if not settings.elevenlabs_api_key:
        raise HTTPException(status_code=503, detail="Voice synthesis is not configured")

    voice_id = request.voice_id or settings.elevenlabs_voice_id
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
    payload = {
        "text": request.text.strip(),
        "model_id": "eleven_flash_v2_5",
        "voice_settings": {
            "stability": 0.35,
            "similarity_boost": 0.8,
            "style": 0.3,
            "use_speaker_boost": True,
        },
    }
    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            upstream = await client.post(
                url,
                json=payload,
                headers={
                    "xi-api-key": settings.elevenlabs_api_key,
                    "Accept": "audio/mpeg",
                },
            )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Voice provider unavailable") from exc

    if upstream.status_code != 200:
        raise HTTPException(status_code=502, detail="Voice provider rejected the request")
    return Response(content=upstream.content, media_type="audio/mpeg")
