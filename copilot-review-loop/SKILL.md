---
name: copilot-review-loop
description: Run an autonomous GitHub pull request workflow: commit all changes, create or reuse a draft PR, invite GitHub Copilot to review, poll for the latest review, apply useful fixes with Codex, push again, and repeat until high-value review work is exhausted, the max round count is reached, no comments remain, or human intervention is needed.
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
- Treat the goal as high-value review convergence, not zero Copilot comments at any cost.
- Tell the user whether the loop stopped because it finished cleanly, hit the round limit, timed out waiting for Copilot, detected degraded low-value review churn, or needs human intervention.
- Keep the reply short and operational.
