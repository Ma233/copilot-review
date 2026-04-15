---
name: copilot-review
description: Fetch the latest Copilot PR review for a branch, triage the comments, and apply valid fixes instead of echoing raw review text.
---

# Copilot Review

Use the bundled script. Do not rebuild the `gh` calls manually.

Resolve `scripts/get_latest_copilot_review.sh` from this skill directory, not from the user's current working directory.
Use `templates/triage_prompt.md` as the default compact decision rubric to minimize token usage.

```bash
SKILL_ROOT="<absolute-path-to-this-skill>"
SCRIPT="$SKILL_ROOT/scripts/get_latest_copilot_review.sh"
"$SCRIPT" [--branch <name>] [--repo <owner/repo>]
```

```bash
TRIAGE_TEMPLATE="$SKILL_ROOT/templates/triage_prompt.md"
```

## Output

Print one JSON object with `pull_request` and `review`.

Exit non-zero if no PR or no Copilot review exists.

## Required Agent Behavior

This skill is for action, not display.

Workflow:

1. Fetch the review JSON.
2. Use `templates/triage_prompt.md`.
3. Classify each comment as `apply`, `verify`, or `ignore`.
4. Implement `apply` items if the user asked for improvements.
5. Reply with a short summary of applied, verified, and ignored items.

Rules:

- Do not dump raw JSON unless the user explicitly asks for it.
- Paraphrase comments briefly instead of quoting them.
- Merge duplicate comments into one decision.
- Reject comments that are stale, incorrect, or too weak to justify a code change.
