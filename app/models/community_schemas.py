from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from uuid import UUID


# ── Achievement (forward declaration needed by RunBatchSyncResponse) ─────────


class NewlyUnlockedAchievement(BaseModel):
    """Achievement unlocked during a sync — returned in sync response."""
    id: str
    category: str
    title: str
    description: str
    icon: str
    tier: str


# ── Run Sync ─────────────────────────────────────────────────────────────────


class RunSyncPayload(BaseModel):
    """Single run payload matching iOS RunLog fields."""
    id: UUID
    completed_at: datetime
    distance_km: float
    duration_seconds: float
    avg_pace_sec_per_km: float
    km_splits_json: Optional[str] = None

    # User feedback
    feedback_rating: Optional[int] = None
    notes: Optional[str] = None

    # Plan context (denormalized)
    planned_workout_title: Optional[str] = None
    planned_workout_type: Optional[str] = None
    planned_distance_km: Optional[float] = None
    completion_score: Optional[int] = None
    plan_name: Optional[str] = None
    week_number: Optional[int] = None

    # Verification
    data_source: str = "manual"  # "bluetooth_ftms" | "manual"
    treadmill_brand: Optional[str] = None

    # Shoe tracking
    shoe_id: Optional[UUID] = None


class RunBatchSyncRequest(BaseModel):
    """Batch of runs to sync to server."""
    runs: list[RunSyncPayload]


class RunBatchSyncResponse(BaseModel):
    """Response after batch sync."""
    synced_count: int
    already_existed: int
    newly_unlocked: list[NewlyUnlockedAchievement] = []


# ── Run Response ─────────────────────────────────────────────────────────────


class RunResponse(BaseModel):
    """Server-side run record returned to the client."""
    id: UUID
    completed_at: datetime
    distance_km: float
    duration_seconds: float
    avg_pace_sec_per_km: float
    km_splits_json: Optional[str] = None
    feedback_rating: Optional[int] = None
    notes: Optional[str] = None
    planned_workout_title: Optional[str] = None
    planned_workout_type: Optional[str] = None
    planned_distance_km: Optional[float] = None
    completion_score: Optional[int] = None
    plan_name: Optional[str] = None
    week_number: Optional[int] = None
    data_source: str
    treadmill_brand: Optional[str] = None
    is_leaderboard_eligible: bool
    synced_at: datetime

    model_config = {"from_attributes": True}


# ── Leaderboard ──────────────────────────────────────────────────────────────


class LeaderboardEntry(BaseModel):
    """Single leaderboard row."""
    rank: int
    user_id: str
    display_name: str
    profile_photo_base64: Optional[str] = None
    value: float  # km for distance, seconds for best-time


class LeaderboardResponse(BaseModel):
    """Full leaderboard response with user's own position."""
    entries: list[LeaderboardEntry]
    your_rank: Optional[int] = None
    your_value: Optional[float] = None
    total_participants: int


# ── Achievements ────────────────────────────────────────────────────────────


class AchievementDefinitionResponse(BaseModel):
    """Single achievement definition."""
    id: str
    category: str
    title: str
    description: str
    icon: str
    threshold: int
    tier: str
    sort_order: int

    model_config = {"from_attributes": True}


class UserAchievementResponse(BaseModel):
    """A user's unlocked achievement."""
    achievement_id: str
    unlocked_at: datetime
    run_id: Optional[UUID] = None
    # Joined fields from definition
    category: Optional[str] = None
    title: Optional[str] = None
    description: Optional[str] = None
    icon: Optional[str] = None
    tier: Optional[str] = None


class AchievementMarkNotifiedRequest(BaseModel):
    """Mark achievements as notified."""
    achievement_ids: list[str]


class UserStreakResponse(BaseModel):
    """User's streak info."""
    current_streak_days: int
    longest_streak_days: int
    last_run_date: Optional[str] = None


# ── Challenges ──────────────────────────────────────────────────────────────


class ChallengeResponse(BaseModel):
    """Challenge summary for list views."""
    id: str
    title: str
    challenge_type: str
    distance_category: Optional[str] = None
    cumulative_target_km: Optional[float] = None
    starts_at: str
    ends_at: str
    participant_count: int = 0
    is_joined: bool = False
    your_best_time_seconds: Optional[int] = None
    your_total_distance_km: Optional[float] = None


class ChallengeDetailResponse(ChallengeResponse):
    """Challenge detail with leaderboard."""
    leaderboard: list[LeaderboardEntry] = []


# ── Events ─────────────────────────────────────────────────────────────────


class EventResponse(BaseModel):
    """Event summary for list views."""
    id: str
    title: str
    description: Optional[str] = None
    event_type: str
    distance_category: Optional[str] = None
    distance_km: Optional[float] = None
    starts_at: str
    ends_at: str
    registration_opens_at: Optional[str] = None
    registration_closes_at: Optional[str] = None
    max_participants: Optional[int] = None
    sponsor_name: Optional[str] = None
    sponsor_logo_url: Optional[str] = None
    banner_image_url: Optional[str] = None
    primary_color: Optional[str] = None
    accent_color: Optional[str] = None
    is_featured: bool = False
    participant_count: int = 0
    is_registered: bool = False
    your_best_time_seconds: Optional[int] = None
    your_total_distance_km: Optional[float] = None


class EventDetailResponse(EventResponse):
    """Event detail with leaderboard."""
    leaderboard: list[LeaderboardEntry] = []


class EventRegistrationResponse(BaseModel):
    """Registration status response."""
    registered: Optional[bool] = None
    error: Optional[str] = None


# ── Social ─────────────────────────────────────────────────────────────────


class UserSearchResult(BaseModel):
    """User search result."""
    id: str
    display_name: str
    profile_photo_base64: Optional[str] = None
    bio: Optional[str] = None
    is_following: bool = False


class UserProfileResponse(BaseModel):
    """Full user profile with stats."""
    id: str
    display_name: str
    profile_photo_base64: Optional[str] = None
    bio: Optional[str] = None
    is_following: bool = False
    follower_count: int = 0
    following_count: int = 0
    total_distance_km: float = 0.0
    total_runs: int = 0
    recent_activities: list[dict] = []


class ActivityFeedItem(BaseModel):
    """Single activity feed entry."""
    id: str
    user_id: str
    display_name: str
    profile_photo_base64: Optional[str] = None
    activity_type: str
    activity_data: dict = {}
    created_at: str


class TeamCreateRequest(BaseModel):
    """Create team request."""
    name: str
    description: Optional[str] = None


class TeamJoinRequest(BaseModel):
    """Join team by invite code."""
    invite_code: str


class TeamResponse(BaseModel):
    """Team summary."""
    id: str
    name: str
    description: Optional[str] = None
    photo_url: Optional[str] = None
    invite_code: Optional[str] = None
    member_count: int = 0
    is_member: bool = False


class TeamMemberResponse(BaseModel):
    """Team member with stats."""
    user_id: str
    display_name: str
    profile_photo_base64: Optional[str] = None
    role: str
    total_distance_km: float = 0.0


class TeamDetailResponse(TeamResponse):
    """Team detail with members and leaderboard."""
    members: list[TeamMemberResponse] = []
    leaderboard: list[TeamMemberResponse] = []
