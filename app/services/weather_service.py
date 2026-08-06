"""
Weather forecast lookup via the National Weather Service free API.

Used by race_fueling_service to inform the race-day plan (heat dressing
adjustments, hydration ramp). Returns None on any failure — the prompt
gracefully omits weather when missing.

NWS API: https://www.weather.gov/documentation/services-web-api
- No API key required, free, no rate limit beyond reasonable use
- US-only (lat/lon must be inside the US). For races abroad, weather is None.
"""

import logging
from datetime import date, datetime
from typing import Optional

import httpx

logger = logging.getLogger(__name__)


_NWS_BASE = "https://api.weather.gov"
_USER_AGENT = "Stride/1.0 (hello@choquer.agency)"


async def fetch_weather(lat: float, lon: float, target_date: date) -> Optional[dict]:
    """
    Returns a dict like:
      {
        "high_temp_f": 62,
        "low_temp_f": 48,
        "wind_speed_mph": 8,
        "humidity_pct": 65,
        "conditions": "Mostly cloudy",
        "source": "NWS"
      }
    or None when the API can't help (location outside US, lookup error, no
    forecast that far out, etc.).
    """
    try:
        async with httpx.AsyncClient(timeout=15.0, headers={"User-Agent": _USER_AGENT}) as client:
            # Step 1: resolve lat/lon → forecast endpoint
            point_resp = await client.get(f"{_NWS_BASE}/points/{lat},{lon}")
            if point_resp.status_code != 200:
                logger.info("NWS points lookup failed: %s", point_resp.status_code)
                return None
            forecast_url = point_resp.json().get("properties", {}).get("forecast")
            if not forecast_url:
                return None

            # Step 2: pull forecast
            fc_resp = await client.get(forecast_url)
            if fc_resp.status_code != 200:
                return None
            periods = fc_resp.json().get("properties", {}).get("periods", [])

        # Match the period whose startTime is on target_date
        target_iso = target_date.isoformat()
        match = None
        for p in periods:
            start = p.get("startTime", "")
            if start.startswith(target_iso):
                match = p
                break
        if match is None:
            # NWS forecasts ~7 days out. Race may be further away.
            return None

        return {
            "high_temp_f": match.get("temperature") if match.get("isDaytime") else None,
            "low_temp_f": match.get("temperature") if not match.get("isDaytime") else None,
            "wind_speed_mph": _parse_wind(match.get("windSpeed", "")),
            "conditions": match.get("shortForecast"),
            "detailed_forecast": match.get("detailedForecast"),
            "source": "NWS",
        }
    except Exception:
        logger.exception("Weather lookup failed")
        return None


def _parse_wind(s: str) -> Optional[int]:
    """NWS wind format like '8 to 12 mph'. Take the higher number."""
    if not s:
        return None
    nums = [int(p) for p in s.split() if p.isdigit()]
    return max(nums) if nums else None
