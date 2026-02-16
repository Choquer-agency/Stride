"""Admin session-based authentication via signed cookies."""

from fastapi import Request, Depends, HTTPException
from fastapi.responses import RedirectResponse
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.models.user import User

COOKIE_NAME = "stride_admin_session"
MAX_AGE = 86400 * 7  # 7 days


def _get_serializer() -> URLSafeTimedSerializer:
    settings = get_settings()
    secret = settings.admin_session_secret or settings.jwt_secret_key
    return URLSafeTimedSerializer(secret)


def create_admin_session(user_id: str) -> str:
    """Create a signed session token for admin."""
    s = _get_serializer()
    return s.dumps({"uid": user_id})


def decode_admin_session(token: str) -> dict | None:
    """Decode and validate a session token. Returns None if invalid."""
    s = _get_serializer()
    try:
        return s.loads(token, max_age=MAX_AGE)
    except (BadSignature, SignatureExpired):
        return None


async def get_admin_user(
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> User:
    """FastAPI dependency: require admin user from session cookie."""
    token = request.cookies.get(COOKIE_NAME)
    if not token:
        raise HTTPException(status_code=303, headers={"Location": "/admin/login"})

    data = decode_admin_session(token)
    if not data or "uid" not in data:
        raise HTTPException(status_code=303, headers={"Location": "/admin/login"})

    result = await db.execute(select(User).where(User.id == data["uid"]))
    user = result.scalar_one_or_none()

    if user is None or not user.is_admin:
        raise HTTPException(status_code=303, headers={"Location": "/admin/login"})

    return user
