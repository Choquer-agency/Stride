#!/usr/bin/env python3
"""
Generate all pre-recorded voice coach MP3 clips via ElevenLabs API.
Run once, commit the output. Never call the API for these phrases again.

Usage: python3 scripts/generate_voice_clips.py
"""

import os
import time
import json
import subprocess

API_KEY = "sk_6c250411f6eed3dafe6b56c013dd12e26160505c379286af"
VOICE_ID = "fDeOZu1sNd7qahm2fV4k"
MODEL_ID = "eleven_flash_v2_5"
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "StrideApp", "Audio")

VOICE_SETTINGS = {
    "stability": 0.6,
    "similarity_boost": 0.8,
    "style": 0.3,
    "use_speaker_boost": True,
}

DELAY_BETWEEN_REQUESTS = 0.35


def generate_clip(filename: str, text: str):
    """Call ElevenLabs API via curl and save MP3."""
    filepath = os.path.join(OUTPUT_DIR, filename)

    if os.path.exists(filepath) and os.path.getsize(filepath) > 1000:
        return "skip"

    url = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}"
    body = json.dumps({
        "text": text,
        "model_id": MODEL_ID,
        "voice_settings": VOICE_SETTINGS,
    })

    result = subprocess.run(
        [
            "curl", "-s", "-X", "POST", url,
            "-H", f"xi-api-key: {API_KEY}",
            "-H", "Content-Type: application/json",
            "-H", "Accept: audio/mpeg",
            "-d", body,
            "-o", filepath,
            "-w", "%{http_code}",
        ],
        capture_output=True, text=True, timeout=30,
    )

    status = result.stdout.strip()
    if status == "200" and os.path.exists(filepath) and os.path.getsize(filepath) > 500:
        size_kb = os.path.getsize(filepath) / 1024
        return f"ok ({size_kb:.0f}KB)"
    else:
        # Remove bad file
        if os.path.exists(filepath):
            os.remove(filepath)
        return f"fail (HTTP {status})"


def build_clip_list():
    """Return list of (filename, text) tuples for all Tier 1 clips."""
    clips = []

    # ── Countdown ──
    clips.append(("countdown_1.mp3", "Three... two... one... go."))
    clips.append(("countdown_2.mp3", "Starting in three... two... one... let's go."))

    # ── Kilometer labels (1-100) ──
    for i in range(1, 101):
        clips.append((f"km_{i}.mp3", f"Kilometer {i}."))

    # ── Mile labels (1-100) ──
    for i in range(1, 101):
        clips.append((f"mile_{i}.mp3", f"Mile {i}."))

    # ── Connectors / Labels ──
    clips.append(("pace.mp3", "Pace:"))
    clips.append(("total_time.mp3", "Total time:"))
    clips.append(("average_pace.mp3", "Average pace so far:"))
    clips.append(("total_distance.mp3", "Total distance:"))
    clips.append(("best_split.mp3", "Best split:"))
    clips.append(("slowest_split.mp3", "Slowest split:"))
    clips.append(("average_heart_rate.mp3", "Average heart rate:"))
    clips.append(("total_elevation.mp3", "Total elevation gain:"))
    clips.append(("calories_burned.mp3", "Calories burned: approximately"))
    clips.append(("average_cadence.mp3", "Average cadence:"))
    clips.append(("steps_per_minute.mp3", "steps per minute."))
    clips.append(("max_heart_rate.mp3", "Max heart rate:"))
    clips.append(("beats_per_minute.mp3", "beats per minute."))
    clips.append(("meters.mp3", "meters."))
    clips.append(("kilometers.mp3", "kilometers."))
    clips.append(("per_kilometer.mp3", "per kilometer."))
    clips.append(("per_mile.mp3", "per mile."))
    clips.append(("minutes_label.mp3", "minutes."))
    clips.append(("seconds_label.mp3", "seconds."))

    # ── Pace Alerts ──
    clips.append(("pace_too_slow.mp3", "You're falling behind target pace. Pick it up."))
    clips.append(("pace_slightly_slow.mp3", "Slightly behind pace. Try to push a bit."))
    clips.append(("pace_too_fast.mp3", "Running too fast. Slow down to conserve energy."))
    clips.append(("pace_on_target.mp3", "You're right on target pace."))
    clips.append(("pace_back_on.mp3", "Back on pace. Nice."))
    clips.append(("pace_dropped.mp3", "Pace has dropped in the last kilometer. Try to hold steady."))
    clips.append(("pace_sped_up.mp3", "You've sped up — make sure that's intentional."))
    clips.append(("pace_swing.mp3", "Big pace swing there. Try to settle into a rhythm."))

    # ── Pause / Resume / Stop ──
    clips.append(("run_paused.mp3", "Run paused."))
    clips.append(("run_resumed.mp3", "Run resumed."))
    clips.append(("auto_pause_on.mp3", "Auto-pause activated."))
    clips.append(("auto_pause_off.mp3", "Auto-pause deactivated. You're moving again."))
    clips.append(("run_ended.mp3", "Run ended."))
    clips.append(("run_saved.mp3", "Run saved."))
    clips.append(("run_discarded.mp3", "Run discarded."))
    clips.append(("paused_reminder.mp3", "Still paused. Tap resume when you're ready."))

    # ── Encouragement ──
    clips.append(("encourage_strong_start.mp3", "Strong start."))
    clips.append(("encourage_locked_in.mp3", "You're locked in."))
    clips.append(("encourage_own_it.mp3", "This is your run. Own it."))
    clips.append(("encourage_grinding.mp3", "Keep grinding — you've got this."))
    clips.append(("encourage_halfway.mp3", "Halfway home."))
    clips.append(("encourage_hardest_done.mp3", "The hardest part is already behind you."))
    clips.append(("encourage_big_effort.mp3", "Big effort. Stay with it."))
    clips.append(("encourage_negative_split.mp3", "Negative split — your second half is faster than your first. That's the way to do it."))
    clips.append(("encourage_consistent.mp3", "You've been consistent. Keep it up."))

    # ── Time Checkpoints ──
    clips.append(("thirty_minutes.mp3", "Thirty minutes down."))
    clips.append(("one_hour.mp3", "One hour in. Keep it rolling."))

    # ── Post-Run Summary ──
    clips.append(("run_complete.mp3", "Run complete. Nice work."))
    clips.append(("summary_intro.mp3", "That's a wrap. Here's your summary."))

    # ── Workout Compliance ──
    clips.append(("compliance_nailed.mp3", "You nailed the workout. Every interval was within range."))
    clips.append(("compliance_most_on_target.mp3", "Most intervals were on target."))
    clips.append(("compliance_tempo_good.mp3", "Your tempo pace was right on the money."))
    clips.append(("compliance_recovery_fast.mp3", "Recovery pace was a little fast. Try to actually recover on those — you'll get more out of the hard efforts."))
    clips.append(("compliance_warmup_short.mp3", "You cut the warmup short. Give yourself more time to ease in next time."))
    clips.append(("compliance_cooldown.mp3", "Cool down complete."))

    # ── Recovery / Next Steps ──
    clips.append(("recovery_easy_day.mp3", "Based on today's effort, tomorrow should be an easy day or rest."))
    clips.append(("recovery_ready.mp3", "You're recovered enough for another hard session tomorrow if you want it."))
    clips.append(("recovery_stretch.mp3", "Stretch it out while you're still warm."))
    clips.append(("recovery_hydrate.mp3", "Make sure you hydrate and get some food in within the next thirty minutes."))
    clips.append(("recovery_earned_it.mp3", "Take it easy the rest of today. You earned it."))

    # ── Workout Type Intros ──
    clips.append(("type_recovery.mp3", "This is a recovery run. Keep it easy."))
    clips.append(("type_long_run.mp3", "This is a long run."))
    clips.append(("type_interval.mp3", "This is an interval session."))
    clips.append(("type_tempo.mp3", "This is a tempo run."))
    clips.append(("type_fartlek.mp3", "This is a fartlek. I'll call out the fast and easy segments as we go."))
    clips.append(("type_progression.mp3", "This is a progression run. We'll start easy and bring the pace down each kilometer."))

    # ── Workout Preview connectors ──
    clips.append(("todays_workout.mp3", "Today's workout:"))
    clips.append(("heres_the_plan.mp3", "Here's the plan."))
    clips.append(("target_distance_today.mp3", "Total target distance today:"))
    clips.append(("target_time_today.mp3", "Total target time today:"))

    # ── Goal Reminders ──
    clips.append(("weekly_goal_hit.mp3", "You've hit your weekly goal."))
    clips.append(("one_more_run.mp3", "One more run this week and you hit your streak."))
    clips.append(("kilometers_away.mp3", "kilometers away from your weekly goal."))
    clips.append(("kilometers_to_go.mp3", "kilometers to go for your weekly target."))

    # ── Halfway ──
    clips.append(("halfway_there.mp3", "Halfway there."))
    clips.append(("time_label.mp3", "Time:"))

    # ── Personal Records ──
    clips.append(("new_pr.mp3", "New personal record."))
    clips.append(("new_fastest_km.mp3", "That's a new fastest kilometer."))
    clips.append(("fastest.mp3", "Fastest"))
    clips.append(("longest_run.mp3", "New personal record. Longest run."))
    clips.append(("longest_duration.mp3", "New personal record. Longest duration."))
    clips.append(("new_monthly_record.mp3", "New monthly distance record."))
    clips.append(("this_month.mp3", "this month."))
    clips.append(("fastest_split.mp3", "You just set a new fastest split for kilometer"))
    clips.append(("fastest_this_year.mp3", "Fastest split this year."))

    # ── Streak / Consistency ──
    clips.append(("runs_this_week.mp3", "runs this week."))
    clips.append(("thats.mp3", "That's"))
    clips.append(("day_running_streak.mp3", "day running streak."))
    clips.append(("youre_on_a.mp3", "You're on a"))
    clips.append(("impressive_consistency.mp3", "Impressive consistency."))

    # ── Training Plan Progress ──
    clips.append(("week_label.mp3", "Week"))
    clips.append(("of_your_plan.mp3", "of your training plan."))
    clips.append(("weeks_to_race.mp3", "weeks to race day."))
    clips.append(("taper_starts.mp3", "Taper starts next week. The hard work is done."))
    clips.append(("on_track.mp3", "You're on track for your goal."))
    clips.append(("trust_process.mp3", "This block is building your aerobic base. Trust the process."))

    # ── Comparison phrases ──
    clips.append(("faster_than_last.mp3", "That's faster than your last run at this distance."))
    clips.append(("slower_than_last.mp3", "That's slower than your last run at this distance."))
    clips.append(("solid_consistency.mp3", "Solid consistency."))
    clips.append(("more_distance_today.mp3", "You covered more distance today than any run this week."))
    clips.append(("fitness_improving.mp3", "Your fitness is improving."))

    # ── Numbers (1-60 for time composition) ──
    number_words = {
        1: "one", 2: "two", 3: "three", 4: "four", 5: "five",
        6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten",
        11: "eleven", 12: "twelve", 13: "thirteen", 14: "fourteen", 15: "fifteen",
        16: "sixteen", 17: "seventeen", 18: "eighteen", 19: "nineteen", 20: "twenty",
        21: "twenty one", 22: "twenty two", 23: "twenty three", 24: "twenty four",
        25: "twenty five", 26: "twenty six", 27: "twenty seven", 28: "twenty eight",
        29: "twenty nine", 30: "thirty", 31: "thirty one", 32: "thirty two",
        33: "thirty three", 34: "thirty four", 35: "thirty five", 36: "thirty six",
        37: "thirty seven", 38: "thirty eight", 39: "thirty nine", 40: "forty",
        41: "forty one", 42: "forty two", 43: "forty three", 44: "forty four",
        45: "forty five", 46: "forty six", 47: "forty seven", 48: "forty eight",
        49: "forty nine", 50: "fifty", 51: "fifty one", 52: "fifty two",
        53: "fifty three", 54: "fifty four", 55: "fifty five", 56: "fifty six",
        57: "fifty seven", 58: "fifty eight", 59: "fifty nine", 60: "sixty",
    }
    for num, word in number_words.items():
        clips.append((f"num_{num}.mp3", f"{word}."))

    # ── Time unit words for composition ──
    clips.append(("minute.mp3", "minute"))
    clips.append(("minute_s.mp3", "minutes"))
    clips.append(("second.mp3", "second"))
    clips.append(("second_s.mp3", "seconds"))
    clips.append(("hour.mp3", "hour"))
    clips.append(("hour_s.mp3", "hours"))

    return clips


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    clips = build_clip_list()

    print(f"\nGenerating {len(clips)} voice clips to {OUTPUT_DIR}\n")

    success = 0
    failed = 0
    skipped = 0
    failed_list = []

    for i, (filename, text) in enumerate(clips, 1):
        filepath = os.path.join(OUTPUT_DIR, filename)
        if os.path.exists(filepath) and os.path.getsize(filepath) > 1000:
            print(f"[{i}/{len(clips)}] SKIP: {filename}")
            skipped += 1
            continue

        print(f"[{i}/{len(clips)}] Generating: {filename}")
        result = generate_clip(filename, text)
        if result == "skip":
            skipped += 1
        elif result.startswith("ok"):
            print(f"  {result}")
            success += 1
        else:
            print(f"  FAIL: {result}")
            failed += 1
            failed_list.append((filename, text))

        time.sleep(DELAY_BETWEEN_REQUESTS)

    print(f"\n{'='*50}")
    print(f"Done! Generated: {success}, Skipped: {skipped}, Failed: {failed}")
    print(f"Total clips: {len(clips)}")

    if failed_list:
        print(f"\nFailed clips:")
        for fn, txt in failed_list:
            print(f"  - {fn}: {txt}")

    # Report total size
    total_size = sum(
        os.path.getsize(os.path.join(OUTPUT_DIR, f))
        for f in os.listdir(OUTPUT_DIR)
        if f.endswith(".mp3")
    )
    print(f"Total bundle size: {total_size / (1024*1024):.1f} MB")


if __name__ == "__main__":
    main()
