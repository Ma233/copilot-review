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
2. Determine the PR diff against the base branch, then read the changed files and nearby code needed to understand the intent and behavior of the changes.
3. Write a concise PR title and description from that code-change analysis. The description should explain what changed and why it matters, not list commit subjects or restate file names mechanically.
4. If the user is asking to prepare the current work for review and the worktree has relevant uncommitted changes, stage and commit them before opening the PR.
5. If the branch has not been pushed yet, or local commits are ahead of the remote branch, push the branch before opening the PR.
6. Run `scripts/create_or_reuse_draft_pr.sh` only after the branch state is ready for GitHub PR creation, passing the analyzed title and description with `--title` and `--body`.

Rules:

- Run `scripts/create_or_reuse_draft_pr.sh` after any needed commit and push steps.
- Use the current branch unless the user names a different branch.
- If a commit is needed and the user did not provide a message, write a concise commit message derived from the actual code changes.
- If the worktree contains obviously unrelated or partial changes, stop and ask before committing them.
- If no upstream exists yet, prefer `git push -u <remote> <branch>`. If an upstream already exists, prefer `git push`.
- Always pass a PR title and body that you derived by analyzing the PR code changes. Treat the script-generated title and body only as a fallback for non-interactive script use.
- Do not build the PR body from a raw commit list, branch name, or a mechanical file list.
- If GitHub reports that there are no commits between the base and head branches, explain that there is no PR diff left after commit/push checks instead of retrying blindly.
- Report whether the draft PR was created or reused, including the PR number and URL when available.
- Do not describe unsupported colon forms such as `$copilot-review:pr`.
- Keep the reply short and operational.
