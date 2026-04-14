---
name: copilot-review
description: Fetch the latest GitHub Copilot review data for the pull request associated with a branch by using gh. Use when Codex needs to find a PR from a branch, inspect GitHub review metadata, retrieve the last Copilot-authored review, or script this workflow in repositories that use GitHub CLI authentication.
---

# Copilot Review

Use the bundled script. Do not rebuild the `gh` calls manually.

Resolve `scripts/get_latest_copilot_review.sh` from this skill directory, not from the user's current working directory.

```bash
SKILL_ROOT="<absolute-path-to-this-skill>"
SCRIPT="$SKILL_ROOT/scripts/get_latest_copilot_review.sh"
"$SCRIPT" [--branch <name>] [--repo <owner/repo>]
```

## Output

Print one JSON object with `pull_request` and `review`.

Exit non-zero if no PR or no Copilot review exists.
