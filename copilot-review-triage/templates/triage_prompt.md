# Copilot Review Triage Template

Review the JSON payload from `get_latest_copilot_review.sh` and classify each comment as `apply`, `verify`, or `ignore`.

Guidelines:

- `apply`: The feedback is correct, actionable, and worth implementing now.
- `verify`: The feedback is plausible but needs confirmation in code, tests, or product requirements before changing anything.
- `ignore`: The feedback is stale, incorrect, already addressed, too vague, or not worth changing.

Output requirements:

- Summarize the latest Copilot review in concise English.
- Merge duplicate comments into one decision.
- For each distinct comment, provide:
  - `classification`
  - `reason`
  - `recommended_action`
- If the user asked to implement changes, apply only the `apply` items unless later verification makes a `verify` item clearly correct.
- Do not dump raw JSON unless the user explicitly asks for it.
