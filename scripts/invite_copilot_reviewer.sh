#!/usr/bin/env sh
set -eu

error() {
  echo "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: invite_copilot_reviewer.sh [--branch <branch>] [--repo <owner/repo>]

Invite GitHub Copilot to review the pull request associated with a branch.

Options:
  --branch <branch>   Branch name. Defaults to the current git branch.
  --repo <owner/repo> GitHub repository. Defaults to the current repository.
  --help              Show this help.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required but not found in PATH" >&2
    exit 127
  fi
}

branch=""
repo=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --branch" >&2
        exit 2
      fi
      branch="$2"
      shift 2
      ;;
    --repo)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --repo" >&2
        exit 2
      fi
      repo="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_command gh
require_command jq

if ! gh auth status >/dev/null 2>&1; then
  error "gh is installed but not authenticated. Run 'gh auth login' first."
fi

if [ -z "$branch" ]; then
  require_command git
  branch="$(git branch --show-current 2>/dev/null || true)"
fi

if [ -z "$branch" ]; then
  error "Unable to determine branch. Pass --branch explicitly."
fi

if [ -n "$repo" ]; then
  export GH_REPO="$repo"
fi

pr_json="$(
  gh pr list \
    --head "$branch" \
    --state open \
    --json number,url,title,headRefName \
    --limit 100 \
    --jq '
      map(select(.headRefName == "'"$branch"'"))
      | sort_by(.number)
      | last
      | if . == null then
          empty
        else
          {
            number: .number,
            url: .url,
            title: .title,
            headRefName: .headRefName
          }
        end
    '
)"

if [ -z "$pr_json" ] || [ "$pr_json" = "null" ]; then
  error "No open pull request found for branch: $branch"
fi

pr_number="$(printf '%s\n' "$pr_json" | jq -r '.number // empty')"

if [ -z "$pr_number" ]; then
  error "Failed to determine pull request number for branch: $branch"
fi

gh pr edit "$pr_number" --add-reviewer "@copilot" >/dev/null

printf '%s\n' "$pr_json" | jq -c '
  {
    pull_request: .,
    requested_reviewer: "@copilot",
    status: "requested"
  }
'
