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

check_file "SKILL.md"
check_file "README.md"
check_file "agents/openai.yaml"
check_file "scripts/copilot_review.sh"
check_file "scripts/get_latest_copilot_review.sh"
check_file "scripts/invite_copilot_reviewer.sh"

if ! grep -q '^---' "$repo_root/SKILL.md"; then
  error "SKILL.md is missing front matter"
fi

if ! grep -q 'npx skills install -a codex https://github.com/Ma233/copilot-review' "$repo_root/README.md"; then
  error "README.md does not document GitHub installation with npx skills"
fi

if ! grep -q '\$copilot-review:invite' "$repo_root/SKILL.md"; then
  error "SKILL.md does not document the invite subcommand"
fi

if ! grep -q '\$copilot-review:triage' "$repo_root/SKILL.md"; then
  error "SKILL.md does not document the triage subcommand"
fi

printf 'OK: repository contains required Codex skill files\n'
printf 'OK: README documents GitHub installation\n'

check_command_optional sh
check_command_optional gh
check_command_optional jq
check_command_optional git

printf 'Validation complete.\n'
