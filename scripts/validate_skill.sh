#!/usr/bin/env sh
set -eu

error() {
  echo "$*" >&2
  exit 1
}

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"

check_file() {
  path="$1"
  if [ ! -f "$repo_root/$path" ]; then
    error "Missing required file: $path"
  fi
}

check_command_optional() {
  command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'OK: found command %s\n' "$command_name"
  else
    printf 'WARN: command not found: %s\n' "$command_name"
  fi
}

for path in \
  "README.md" \
  "scripts/invite_copilot_reviewer.sh" \
  "scripts/get_latest_copilot_review.sh" \
  "copilot-review-invite/SKILL.md" \
  "copilot-review-invite/agents/openai.yaml" \
  "copilot-review-invite/scripts/invite_copilot_reviewer.sh" \
  "copilot-review-loop/SKILL.md" \
  "copilot-review-loop/agents/openai.yaml" \
  "copilot-review-loop/scripts/create_or_reuse_draft_pr.sh" \
  "copilot-review-loop/scripts/invite_copilot_reviewer.sh" \
  "copilot-review-loop/scripts/get_latest_copilot_review.sh" \
  "copilot-review-loop/scripts/run_copilot_review_loop.sh" \
  "copilot-review-loop/templates/triage_prompt.md" \
  "copilot-review-loop/templates/triage_schema.json" \
  "copilot-review-triage/SKILL.md" \
  "copilot-review-triage/agents/openai.yaml" \
  "copilot-review-triage/scripts/get_latest_copilot_review.sh" \
  "copilot-review-triage/templates/triage_prompt.md"
do
  check_file "$path"
done

if ! grep -q 'npx skills install -a codex https://github.com/Ma233/copilot-review' "$repo_root/README.md"; then
  error "README.md does not document GitHub installation with npx skills"
fi

if ! grep -q '\$copilot-review-invite' "$repo_root/README.md"; then
  error "README.md does not document the invite skill"
fi

if ! grep -q '\$copilot-review-triage' "$repo_root/README.md"; then
  error "README.md does not document the triage skill"
fi

if ! grep -q '\$copilot-review-loop' "$repo_root/README.md"; then
  error "README.md does not document the loop skill"
fi

if grep -q '\$copilot-review:' "$repo_root/README.md"; then
  error "README.md still references unsupported colon subcommands"
fi

if [ -e "$repo_root/SKILL.md" ]; then
  error "Root SKILL.md should be removed when only explicit invite and triage skills are supported"
fi

printf 'OK: repository contains required Codex skill files\n'
printf 'OK: README documents GitHub installation\n'

check_command_optional sh
check_command_optional gh
check_command_optional jq
check_command_optional git
check_command_optional codex

printf 'Validation complete.\n'
