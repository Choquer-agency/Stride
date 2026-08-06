"""
Replay a recorded Garmin webhook payload against the local backend.

Critical for Phase 1/2/3 development while real Garmin OAuth approval is pending.
Signs the request with HMAC-SHA256 using GARMIN_WEBHOOK_SECRET so the route
accepts it.

Usage:
    python scripts/garmin_simulator.py easy_run.json
    python scripts/garmin_simulator.py daily_metrics_normal.json --kind daily
    python scripts/garmin_simulator.py race_marathon.json --user-garmin-id ABC123
    python scripts/garmin_simulator.py easy_run.json --date 2026-04-15
    python scripts/garmin_simulator.py easy_run.json --base-url http://localhost:8000

Fixtures live in tests/fixtures/garmin/ — pass either an absolute path or just
the basename (auto-resolved against that directory).

Endpoints:
    workout         → /api/garmin/webhook/workout
    daily           → /api/garmin/webhook/daily-metrics
    periodic        → /api/garmin/webhook/periodic-metrics
"""

import argparse
import hashlib
import hmac
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

import httpx

from app.config import get_settings


FIXTURE_DIR = PROJECT_ROOT / "tests" / "fixtures" / "garmin"

ENDPOINTS = {
    "workout": "/api/garmin/webhook/workout",
    "daily": "/api/garmin/webhook/daily-metrics",
    "periodic": "/api/garmin/webhook/periodic-metrics",
}


def resolve_fixture(arg: str) -> Path:
    """Accept either an absolute path or a basename in tests/fixtures/garmin/."""
    p = Path(arg)
    if p.is_file():
        return p
    candidate = FIXTURE_DIR / arg
    if candidate.is_file():
        return candidate
    candidate = FIXTURE_DIR / f"{arg}.json"
    if candidate.is_file():
        return candidate
    raise FileNotFoundError(f"Fixture not found: {arg} (looked in {FIXTURE_DIR})")


def shift_dates(payload, target_date: str) -> object:
    """
    If --date is provided, replace any obvious date/timestamp field in the
    payload with the target date. Quick + dirty — handles the common cases
    used by the fixtures (calendar_date, start_time, calendarDate, startTime).
    """
    if isinstance(payload, dict):
        out = {}
        for k, v in payload.items():
            kl = k.lower()
            if kl in ("calendar_date", "calendardate", "date") and isinstance(v, str):
                out[k] = target_date
            elif kl in ("start_time", "starttime") and isinstance(v, str):
                out[k] = f"{target_date}T{v.split('T', 1)[1]}" if "T" in v else f"{target_date}T07:00:00Z"
            else:
                out[k] = shift_dates(v, target_date)
        return out
    if isinstance(payload, list):
        return [shift_dates(item, target_date) for item in payload]
    return payload


def detect_kind(payload, fname: str) -> str:
    """Guess workout/daily/periodic from filename + payload shape."""
    lower = fname.lower()
    if "daily" in lower or "metrics_" in lower or "hrv" in lower or "sleep" in lower:
        return "daily"
    if "periodic" in lower:
        return "periodic"
    if isinstance(payload, dict):
        if "calendar_date" in payload or "calendarDate" in payload or "hrv_overnight" in payload:
            return "daily"
        if "vo2max_running" in payload or "training_status" in payload:
            return "periodic"
    return "workout"


def sign(body: bytes) -> str:
    secret = get_settings().garmin_webhook_secret
    if not secret:
        print("WARNING: GARMIN_WEBHOOK_SECRET not set — signature will be empty and route will reject", file=sys.stderr)
        return ""
    return hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()


def main(args: argparse.Namespace) -> int:
    fixture_path = resolve_fixture(args.fixture)
    payload = json.loads(fixture_path.read_text(encoding="utf-8"))

    # Optional: override the user binding so the webhook resolves to a specific
    # local user without needing real Garmin tokens. Looks up users.garmin_user_id.
    if args.user_garmin_id:
        if isinstance(payload, dict):
            payload["user_id"] = args.user_garmin_id

    if args.date:
        payload = shift_dates(payload, args.date)

    kind = args.kind or detect_kind(payload, fixture_path.name)
    if kind not in ENDPOINTS:
        print(f"Unknown kind: {kind}", file=sys.stderr)
        return 2

    body = json.dumps(payload).encode("utf-8")
    signature = sign(body)
    url = f"{args.base_url}{ENDPOINTS[kind]}"

    headers = {"Content-Type": "application/json"}
    if signature:
        headers["X-Garmin-Signature"] = signature

    print(f"→ POST {url}")
    print(f"  fixture: {fixture_path.name}  kind: {kind}")
    print(f"  bytes: {len(body)}  signed: {bool(signature)}")
    if args.user_garmin_id:
        print(f"  user_garmin_id: {args.user_garmin_id}")

    try:
        with httpx.Client(timeout=30.0) as client:
            resp = client.post(url, content=body, headers=headers)
    except httpx.ConnectError:
        print(f"Cannot connect to {url}. Is uvicorn running? `uvicorn app.main:app --reload`", file=sys.stderr)
        return 3

    print(f"← {resp.status_code} {resp.reason_phrase}")
    if resp.status_code >= 400 or args.verbose:
        print(resp.text[:1000])
    return 0 if resp.status_code < 400 else 4


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Replay a Garmin webhook payload locally.")
    parser.add_argument("fixture", help="Fixture file (basename in tests/fixtures/garmin/ or absolute path)")
    parser.add_argument("--kind", choices=list(ENDPOINTS.keys()), help="Override endpoint kind (default: auto-detect)")
    parser.add_argument("--user-garmin-id", help="Stamp payload.user_id so the route resolves to a specific User.garmin_user_id")
    parser.add_argument("--date", help="Time-travel: shift dates in payload to this YYYY-MM-DD")
    parser.add_argument("--base-url", default="http://localhost:8000", help="Backend base URL")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show response body")
    args = parser.parse_args()
    sys.exit(main(args))
