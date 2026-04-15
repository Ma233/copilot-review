# copilot-review

`copilot-review` is a Codex skill for fetching the latest GitHub Copilot review attached to the pull request associated with a branch, evaluating whether the review comments are actually meaningful, and applying the useful ones.

This repository is intended to be installed into Codex directly from GitHub.

## GitHub Install

Install with:

```text
$skill-installer install https://github.com/Ma233/copilot-review
```

After installation, restart Codex to pick up the new skill.

## Dependencies

The bundled runtime script is:

```bash
scripts/get_latest_copilot_review.sh
```

The bundled compact decision template is:

```bash
templates/triage_prompt.md
```

When Codex uses this skill, it should resolve that relative path from the installed skill root, not from the user's current working directory.

System command dependencies:

- `sh`: required to run the script
- `gh`: required, used to query GitHub repository, pull request, review, and review comment data
- `jq`: required, used to filter and shape GitHub API JSON responses
- `git`: conditionally required when the script needs to infer the current branch or resolve branch remote information from the local checkout

Authentication requirements:

- `gh` must already be installed and authenticated
- the caller must have access to the target GitHub repository and pull request metadata
- when using private repositories during GitHub-based installation, Codex's installer may rely on existing git credentials or `GITHUB_TOKEN` / `GH_TOKEN`

## Script Behavior

The script:

1. Resolves the target branch, defaulting to the current git branch.
2. Resolves the target repository, defaulting to the current GitHub repository when possible.
3. Finds the pull request associated with that branch.
4. Fetches all reviews for that pull request.
5. Selects the latest review whose author login contains `copilot`.
6. Fetches comments attached to that review.
7. Prints a single JSON object.

## Expected Agent Behavior

This skill is intended to support code improvement, not just review display.

When Codex invokes this skill, it should normally:

1. Fetch the latest Copilot review.
2. Use `templates/triage_prompt.md` to classify comments with minimal token overhead.
3. Decide which comments are valid, which are questionable, and which should be ignored.
4. Apply the valid feedback when the user asked for code improvements.
5. Report the applied and rejected comments with concise reasoning.

Codex should avoid returning raw review JSON or blindly echoing all comments unless the user explicitly asked to inspect the raw review data.

Use the current branch:

```bash
SKILL_ROOT="<absolute-path-to-installed-copilot-review-skill>"
SCRIPT_PATH="$SKILL_ROOT/scripts/get_latest_copilot_review.sh"
"$SCRIPT_PATH"
```

Use a specific branch:

```bash
"$SCRIPT_PATH" --branch feature/my-branch
```

Use a specific repository and branch:

```bash
"$SCRIPT_PATH" --repo owner/repo --branch feature/my-branch
```

## Output

The script prints one JSON object with:

- `pull_request`: PR metadata such as number, URL, title, and head branch
- `review`: the latest Copilot-authored review, including body, state, submitted time, inline comments, and both GitHub review ids

If no matching pull request exists, or if no Copilot review exists for that PR, the script exits non-zero and writes an error message to stderr.
