from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.models.auth_schemas import (
    EmailRegisterRequest,
    EmailLoginRequest,
    GoogleAuthRequest,
    AppleAuthRequest,
    ProfileUpdateRequest,
    TokenResponse,
    UserResponse,
)
from app.services.auth_service import (
    hash_password,
    verify_password,
    create_access_token,
    verify_google_token,
    verify_apple_token,
    get_current_user,
)
from app.services import analytics

router = APIRouter(prefix="/auth", tags=["auth"])


def _build_token_response(user: User) -> TokenResponse:
    """Create a TokenResponse from a User model."""
    token = create_access_token(user.id)
    return TokenResponse(
        access_token=token,
        user=UserResponse.model_validate(user),
    )


# ── Email Auth ────────────────────────────────────────────────────────────────


@router.post("/register", response_model=TokenResponse)
async def register_email(
    request: EmailRegisterRequest, db: AsyncSession = Depends(get_db)
):
    """Register a new user with email and password."""
    # Check if email already exists
    result = await db.execute(select(User).where(User.email == request.email))
    if result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists",
        )

    user = User(
        email=request.email,
        name=request.name,
        auth_provider="email",
        hashed_password=hash_password(request.password),
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)

    uid = str(user.id)
    analytics.capture(uid, "user_signed_up", {"auth_provider": "email"})
    analytics.identify(uid, {"email": user.email, "name": user.name, "auth_provider": "email"})

    return _build_token_response(user)


@router.post("/login", response_model=TokenResponse)
async def login_email(
    request: EmailLoginRequest, db: AsyncSession = Depends(get_db)
):
    """Sign in with email and password."""
    result = await db.execute(select(User).where(User.email == request.email))
    user = result.scalar_one_or_none()

    if user is None or user.hashed_password is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    if not verify_password(request.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    analytics.capture(str(user.id), "user_signed_in", {"auth_provider": "email"})

    return _build_token_response(user)


# ── Google Auth ───────────────────────────────────────────────────────────────


@router.post("/google", response_model=TokenResponse)
async def auth_google(
    request: GoogleAuthRequest, db: AsyncSession = Depends(get_db)
):
    """Sign in or register with Google."""
    google_info = await verify_google_token(request.id_token)
    email = google_info["email"]

    # Find existing user or create new
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    is_new_user = user is None
    if is_new_user:
        user = User(
            email=email,
            name=google_info.get("name"),
            auth_provider="google",
        )
        db.add(user)
        await db.flush()
        await db.refresh(user)

    uid = str(user.id)
    if is_new_user:
        analytics.capture(uid, "user_signed_up", {"auth_provider": "google"})
        analytics.identify(uid, {"email": user.email, "name": user.name, "auth_provider": "google"})
    else:
        analytics.capture(uid, "user_signed_in", {"auth_provider": "google"})

    return _build_token_response(user)


# ── Apple Auth ────────────────────────────────────────────────────────────────


@router.post("/apple", response_model=TokenResponse)
async def auth_apple(
    request: AppleAuthRequest, db: AsyncSession = Depends(get_db)
):
    """Sign in or register with Apple."""
    apple_info = await verify_apple_token(request.identity_token)

    # Try to find by Apple user identifier first (most reliable)
    result = await db.execute(
        select(User).where(User.apple_user_identifier == request.user_identifier)
    )
    user = result.scalar_one_or_none()

    is_new_user = False
    if user is None:
        # Try by email (Apple provides email on first sign-in only)
        email = request.email or apple_info.get("email")
        if email:
            result = await db.execute(select(User).where(User.email == email))
            user = result.scalar_one_or_none()

        if user is None:
            is_new_user = True
            # Create new user
            if not email:
                # Apple didn't provide email — use a placeholder
                email = f"apple_{request.user_identifier}@privaterelay.appleid.com"
            user = User(
                email=email,
                name=request.full_name,
                auth_provider="apple",
                apple_user_identifier=request.user_identifier,
            )
            db.add(user)
            await db.flush()
            await db.refresh(user)
        else:
            # Link Apple identifier to existing email account
            user.apple_user_identifier = request.user_identifier

    uid = str(user.id)
    if is_new_user:
        analytics.capture(uid, "user_signed_up", {"auth_provider": "apple"})
        analytics.identify(uid, {"email": user.email, "name": user.name, "auth_provider": "apple"})
    else:
        analytics.capture(uid, "user_signed_in", {"auth_provider": "apple"})

    return _build_token_response(user)


# ── Profile ───────────────────────────────────────────────────────────────────


@router.get("/me", response_model=UserResponse)
async def get_profile(current_user: User = Depends(get_current_user)):
    """Return the current user's profile."""
    return UserResponse.model_validate(current_user)


@router.put("/profile", response_model=UserResponse)
async def update_profile(
    request: ProfileUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update profile fields. Sets has_completed_profile when key fields are filled."""
    was_complete = current_user.has_completed_profile

    if request.name is not None:
        current_user.name = request.name
    if request.date_of_birth is not None:
        current_user.date_of_birth = request.date_of_birth
    if request.gender is not None:
        current_user.gender = request.gender
    if request.height_cm is not None:
        current_user.height_cm = request.height_cm
    if request.profile_photo_base64 is not None:
        current_user.profile_photo_base64 = request.profile_photo_base64
    if request.leaderboard_opt_in is not None:
        current_user.leaderboard_opt_in = request.leaderboard_opt_in
    if request.display_name is not None:
        current_user.display_name = request.display_name

    # Mark profile as complete if key fields are filled
    if all([
        current_user.name,
        current_user.date_of_birth,
        current_user.gender,
        current_user.height_cm is not None,
    ]):
        current_user.has_completed_profile = True

    await db.flush()
    await db.refresh(current_user)

    uid = str(current_user.id)
    if not was_complete and current_user.has_completed_profile:
        analytics.capture(uid, "profile_completed", {"gender": current_user.gender})
        analytics.identify(uid, {
            "name": current_user.name,
            "gender": current_user.gender,
            "has_completed_profile": True,
        })

    return UserResponse.model_validate(current_user)
