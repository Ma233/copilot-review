# Copilot Review Loop Triage Template

Review the JSON payload from `get_latest_copilot_review.sh` and classify each distinct comment as `apply`, `verify`, or `ignore`.

Guidelines:

- `apply`: The feedback is correct, actionable, and worth implementing now.
- `verify`: The feedback is plausible but needs confirmation in code, tests, or product requirements before changing anything.
- `ignore`: The feedback is stale, incorrect, already addressed, too vague, or not worth changing.
- `loop_health=productive`: The review is still finding meaningful issues and the loop is converging.
- `loop_health=stalled`: The review still has some value, but most comments are weak, repetitive, or low yield.
- `loop_health=degraded`: The loop is churning on low-value comments, repeated polish, or marginal consistency nits and should stop.

Execution rules:

- Apply only `apply` items unless verification during implementation proves a `verify` item is clearly correct.
- If the review asks for something ambiguous, high-risk, or product-dependent, stop and request human intervention instead of guessing.
- Compare the current review with prior loop rounds when history is available. Identify repeated themes, low novelty, diminishing developer value, and whether the same review comments keep reappearing in slightly different forms.
- If the current review mostly contains repeated polish, consistency tweaks, or low-risk defensive suggestions, prefer `stalled` or `degraded` over continuing the loop blindly.
- Do not create a commit or push changes. The outer runner handles that.
- Run focused validation when the changed area has tests or a cheap build check.

Final response requirements:

- Output JSON that matches the provided schema.
- Include a `decisions` entry for each distinct comment with its classification and a short rationale.
- Set `recommended_action` to `continue`, `stop_for_human`, or `stop_no_value`.
- Set `developer_value_score` and `novelty_score` on a 0-5 scale.
- Add concise `repeat_signals` entries when the loop is revisiting the same themes.
- Be more willing to stop the loop as the round count grows. Early rounds can tolerate some polish comments; later rounds should require clearly high-value findings to continue.
- Keep `summary` concise and in English.
- Merge duplicate comments into one decision.
