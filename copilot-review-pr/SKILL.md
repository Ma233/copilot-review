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

Workflow:

1. Inspect the current branch, commit history, and worktree state.
2. If the user is asking to prepare the current work for review and the worktree has relevant uncommitted changes, stage and commit them before opening the PR.
3. If the branch has not been pushed yet, or local commits are ahead of the remote branch, push the branch before opening the PR.
4. Run `scripts/create_or_reuse_draft_pr.sh` only after the branch state is ready for GitHub PR creation.

Rules:

- Run `scripts/create_or_reuse_draft_pr.sh` after any needed commit and push steps.
- Use the current branch unless the user names a different branch.
- If a commit is needed and the user did not provide a message, write a concise commit message derived from the actual code changes.
- If the worktree contains obviously unrelated or partial changes, stop and ask before committing them.
- If no upstream exists yet, prefer `git push -u <remote> <branch>`. If an upstream already exists, prefer `git push`.
- Prefer script-generated title and body unless the user explicitly provides them.
- If GitHub reports that there are no commits between the base and head branches, explain that there is no PR diff left after commit/push checks instead of retrying blindly.
- Report whether the draft PR was created or reused, including the PR number and URL when available.
- Do not describe unsupported colon forms such as `$copilot-review:pr`.
- Keep the reply short and operational.
