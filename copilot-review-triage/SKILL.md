---
name: copilot-review-triage
description: Fetch the latest GitHub Copilot pull request review, triage the comments, and apply valid fixes. Use when the user wants to inspect, summarize, or address Copilot review feedback.
---

# Copilot Review Triage

Use the bundled script. Do not rebuild the `gh` calls manually.

Resolve scripts from this skill directory.
Use `templates/triage_prompt.md`.

```bash
SKILL_ROOT="<absolute-path-to-this-skill>"
SCRIPT="$SKILL_ROOT/scripts/get_latest_copilot_review.sh"
"$SCRIPT" [--branch <name>] [--repo <owner/repo>]
```

```bash
TRIAGE_TEMPLATE="$SKILL_ROOT/templates/triage_prompt.md"
```

This skill is for action, not display.

Rules:

- Run `scripts/get_latest_copilot_review.sh`.
- Use `templates/triage_prompt.md`.
- Classify each comment as `apply`, `verify`, or `ignore`.
- Implement `apply` items if the user asked for improvements.
- Reply with a short summary of applied, verified, and ignored items.
- Do not dump raw JSON unless the user explicitly asks for it.
- Paraphrase comments briefly instead of quoting them.
- Merge duplicate comments into one decision.
- Reject comments that are stale, incorrect, or too weak to justify a code change.
- Do not describe unsupported colon forms such as `$copilot-review:triage`.
