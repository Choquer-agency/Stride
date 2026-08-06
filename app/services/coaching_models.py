"""
Central registry of which Claude model each coaching loop uses.

Per the v2 plan §14 LLM cost controls:
- Haiku: cheap deterministic-feeling tasks (memo updates, info-only summaries, ambient feedback)
- Sonnet: parsing, wellness interpretation, post-run check
- Opus: high-stakes coaching (plan adjustments, weekly/block reviews, race recap, chat, red flags)
- Fable: the flagship plan-generation moment only (rare per-user calls, highest quality)

These constants are passed as the `model=` arg to AnthropicClient.generate_plan_stream() /
generate_plan() / analyze_image() to override the default model per call.

Approximate per-call cost guidance (1k input / 1k output tokens):
- Haiku 4.5:  ~$0.001 / ~$0.005
- Sonnet 5:   ~$0.003 / ~$0.015
- Opus 5:     ~$0.005 / ~$0.025
- Fable 5:    ~$0.010 / ~$0.050
"""

# ── Model identifiers (latest available) ────────────────────────────────────
HAIKU = "claude-haiku-4-5"
SONNET = "claude-sonnet-5"
OPUS = "claude-opus-5"
FABLE = "claude-fable-5"


# ── Per-loop model assignment ───────────────────────────────────────────────

# Flagship — full training-plan generation and editing. Fable is Anthropic's most
# capable model; these calls are rare per user, so quality wins over cost here.
PLAN_MODEL = FABLE
PLAN_EDIT_MODEL = FABLE

# High-stakes coaching — use Opus for nuance
PLAN_ANALYSIS_MODEL = OPUS
WEEKLY_REVIEW_MODEL = OPUS
BLOCK_REVIEW_MODEL = OPUS
RACE_PREP_MODEL = OPUS
RACE_LOGISTICS_MODEL = OPUS
RACE_FUELING_MODEL = OPUS
POST_RACE_MODEL = OPUS
CHAT_MODEL = OPUS
RED_FLAG_MODEL = OPUS

# Mid-stakes — Sonnet handles
POST_RUN_CHECK_MODEL = SONNET
NUTRITION_PARSE_MODEL = SONNET
NUTRITION_COACH_MODEL = SONNET
WELLNESS_INTERPRET_MODEL = SONNET
WELLNESS_CONCERN_MODEL = SONNET
OFF_SEASON_MODEL = SONNET
PRE_RUN_COACH_MODEL = SONNET
POST_RUN_COACH_MODEL = SONNET

# Low-stakes / ambient — Haiku to save cost
MEMO_UPDATE_MODEL = HAIKU
POST_RUN_INFO_MODEL = HAIKU
CONSOLIDATION_MODEL = HAIKU
NUTRITION_MEAL_FEEDBACK_MODEL = HAIKU
CHAT_HISTORY_SUMMARIZE_MODEL = HAIKU
CHECKIN_QUESTIONS_MODEL = HAIKU


# ── Cost estimation (USD per 1k tokens) ─────────────────────────────────────
# Published Anthropic API rates as of 2026-Q3. Used to populate
# coaching_events.llm_cost_usd for budget reporting.
_COST_PER_1K = {
    HAIKU:  {"input": 0.001, "output": 0.005},
    SONNET: {"input": 0.003, "output": 0.015},
    OPUS:   {"input": 0.005, "output": 0.025},
    FABLE:  {"input": 0.010, "output": 0.050},
    # Legacy models, kept so historical coaching_events still price correctly.
    "claude-haiku-4-5-20251001": {"input": 0.001, "output": 0.005},
    "claude-sonnet-4-6": {"input": 0.003, "output": 0.015},
    "claude-opus-4-7": {"input": 0.005, "output": 0.025},
    "claude-opus-4-6": {"input": 0.005, "output": 0.025},
}


def estimate_cost_usd(model: str, input_tokens: int, output_tokens: int) -> float:
    """Best-effort USD cost for a Claude generation. Returns 0.0 for unknown models."""
    rates = _COST_PER_1K.get(model)
    if not rates:
        return 0.0
    return round(
        (input_tokens / 1000.0) * rates["input"] + (output_tokens / 1000.0) * rates["output"],
        4,
    )
