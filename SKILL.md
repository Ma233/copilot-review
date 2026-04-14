---
name: copilot-review
description: Fetch the latest GitHub Copilot review data for the pull request associated with a branch by using gh. Use when Codex needs to find a PR from a branch, inspect GitHub review metadata, retrieve the last Copilot-authored review, or script this workflow in repositories that use GitHub CLI authentication.
---

# Copilot Review

Use the bundled shell script for deterministic retrieval instead of rebuilding ad hoc `gh api` commands.

## Dependencies

- `gh` installed and authenticated
- `jq` available in `PATH`
- `git` available when branch or remote metadata must be inferred from a local checkout

## Workflow

1. Confirm `gh` is installed and authenticated.
2. Run `scripts/get_latest_copilot_review.sh`.
3. Pass `--branch <name>` when the target branch is not the current branch.
4. Pass `--repo <owner/name>` when running outside the target repository or when the local checkout points at a fork.

## Commands

Return the latest Copilot review for the current branch:

```bash
./scripts/get_latest_copilot_review.sh
```

Return the latest Copilot review for a specific branch:

```bash
./scripts/get_latest_copilot_review.sh --branch feature/my-branch
```

Return the latest Copilot review for a specific repository:

```bash
./scripts/get_latest_copilot_review.sh --repo owner/repo --branch feature/my-branch
```

## Output

The script prints one JSON object with:

- `pull_request`: PR metadata
- `review`: the last review whose author login contains `copilot`, including inline comments

If no PR or Copilot review exists, the script exits non-zero with an error message on stderr.
