---
name: copilot-review-pr
description: Create or reuse a draft pull request for the current branch. Use when the user wants a draft PR opened or refreshed before review.
---

# Copilot Review PR

Use the bundled script. Do not rebuild the `gh` calls manually.

Resolve the script from this skill directory.

```bash
SKILL_ROOT="<absolute-path-to-this-skill>"
SCRIPT="$SKILL_ROOT/scripts/create_or_reuse_draft_pr.sh"
"$SCRIPT" [--branch <name>] [--repo <owner/repo>] [--base <branch>] [--title <title>] [--body <body>]
```

This skill is for action, not display.

Rules:

- Run `scripts/create_or_reuse_draft_pr.sh`.
- Use the current branch unless the user names a different branch.
- Prefer script-generated title and body unless the user explicitly provides them.
- Report whether the draft PR was created or reused, including the PR number and URL when available.
- Do not describe unsupported colon forms such as `$copilot-review:pr`.
- Keep the reply short and operational.
