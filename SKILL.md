---
name: copilot-review
description: Request or handle GitHub Copilot pull request reviews. Use when the user wants to invite Copilot as a reviewer, request a Copilot review, read Copilot review comments, or address Copilot review feedback. Supports optional explicit forms such as $copilot-review:invite and $copilot-review:triage.
---

# Copilot Review

Prefer intent-based use first. The user should not have to remember subcommands.

Map requests like these automatically:

- "invite copilot review"
- "request a copilot review on this PR"
- "check the latest copilot review comments"
- "address the copilot review feedback"

Explicit forms are still supported when the user wants precision:

- `$copilot-review:invite`: add `@copilot` as a reviewer on the current pull request
- `$copilot-review:triage`: fetch the latest Copilot review, classify comments, and apply valid fixes
- `$copilot-review`: ask a clarifying question instead of guessing

Intent routing:

- If the user asks to request or invite a review, run `invite`.
- If the user asks to inspect, summarize, fix, triage, or address feedback, run `triage`.
- If the user only says `$copilot-review`, ask a concise follow-up such as `Do you want to invite Copilot review, or triage the latest Copilot review feedback?`

Use the bundled scripts. Do not rebuild the `gh` calls manually.

Resolve scripts from this skill directory, not from the user's current working directory.

Do not run any script when the user only says `$copilot-review` and their intent is still ambiguous.

```bash
SKILL_ROOT="<absolute-path-to-this-skill>"
ENTRYPOINT="$SKILL_ROOT/scripts/copilot_review.sh"
"$ENTRYPOINT" invite [--branch <name>] [--repo <owner/repo>]
```

```bash
SKILL_ROOT="<absolute-path-to-this-skill>"
"$ENTRYPOINT" triage [--branch <name>] [--repo <owner/repo>]
```

```bash
TRIAGE_TEMPLATE="$SKILL_ROOT/templates/triage_prompt.md"
```

## `invite` Output

Print one JSON object with `pull_request`, `requested_reviewer`, and `status`.

Exit non-zero if no matching PR exists or the reviewer cannot be added.

## `triage` Output

Print one JSON object with `pull_request` and `review`.

Exit non-zero if no PR or no Copilot review exists.

## Required Agent Behavior

This skill is for action, not display.

### `invite`

Workflow:

1. Run `scripts/copilot_review.sh invite`.
2. Report that Copilot was invited, including the PR number when available.
3. Do not claim review comments exist yet unless the user separately asked to fetch them.

### `triage`

Workflow:

1. Run `scripts/copilot_review.sh triage`.
2. Use `templates/triage_prompt.md`.
3. Classify each comment as `apply`, `verify`, or `ignore`.
4. Implement `apply` items if the user asked for improvements.
5. Reply with a short summary of applied, verified, and ignored items.

Rules:

- Ask for clarification when the user invokes `$copilot-review` without enough intent to choose `invite` or `triage`.
- Do not dump raw JSON unless the user explicitly asks for it.
- Paraphrase comments briefly instead of quoting them.
- Merge duplicate comments into one decision.
- Reject comments that are stale, incorrect, or too weak to justify a code change.
