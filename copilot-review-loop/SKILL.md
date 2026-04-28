---
name: copilot-review-loop
description: "Run an autonomous GitHub pull request workflow: commit all changes, ensure a draft PR exists, invite GitHub Copilot to review, poll for the latest review, apply useful fixes with Codex, push again, and repeat until high-value review work is exhausted, the max round count is reached, no comments remain, or human intervention is needed."
---

# Copilot Review Loop

Use the bundled runner script. Do not manually rebuild the loop in ad hoc shell commands.

Resolve the script from this skill directory.

```bash
SKILL_ROOT="<absolute-path-to-this-skill>"
SCRIPT="$SKILL_ROOT/scripts/run_copilot_review_loop.sh"
"$SCRIPT" [--branch <name>] [--repo <owner/repo>] [--base <branch>] [--max-rounds <count>]
```

This skill is for action, not display.

Rules:

- Run `scripts/run_copilot_review_loop.sh`.
- Use the default current branch unless the user names a branch.
- Prefer the script defaults unless the user asked for different polling or round limits.
- When creating a new PR, derive the title and description from the actual code diff and commit history, not from the surrounding chat.
- When possible, match the repository's recent PR title style and honor the project's `pull_request_template.md`.
- Let the runner keep polling until it reaches one of its own stop conditions; do not interrupt it just because Copilot has not replied yet.
- When the loop enters `waiting_for_review`, wait through the script's configured review timeout instead of assuming the run is stuck after a few minutes of silence.
- Treat the goal as high-value review convergence, not zero Copilot comments at any cost.
- Tell the user whether the loop stopped because it finished cleanly, hit the round limit, timed out waiting for Copilot, detected degraded low-value review churn, or needs human intervention.
- Keep the reply short and operational.
