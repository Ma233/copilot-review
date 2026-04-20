---
name: copilot-review-invite
description: Invite GitHub Copilot to review the current pull request. Use when the user wants to request a Copilot PR review or add @copilot as a reviewer.
---

# Copilot Review Invite

Use the bundled script. Do not rebuild the `gh` calls manually.

Resolve the script from this skill directory.

```bash
SKILL_ROOT="<absolute-path-to-this-skill>"
SCRIPT="$SKILL_ROOT/scripts/invite_copilot_reviewer.sh"
"$SCRIPT" [--branch <name>] [--repo <owner/repo>]
```

This skill is for action, not display.

Rules:

- Run `scripts/invite_copilot_reviewer.sh`.
- Report that Copilot was invited, including the PR number when available.
- Do not claim review comments exist yet unless the user separately asked to fetch them.
- Do not describe unsupported colon forms such as `$copilot-review:invite`.
- Keep the reply short and action-oriented.
