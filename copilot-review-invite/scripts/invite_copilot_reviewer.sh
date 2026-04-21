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

parse_github_slug_from_url() {
  remote_url="$1"
  remote_url="${remote_url#git@github.com:}"
  remote_url="${remote_url#ssh://git@github.com/}"
  remote_url="${remote_url#https://github.com/}"
  remote_url="${remote_url#http://github.com/}"
  remote_url="${remote_url%.git}"

  case "$remote_url" in
    */*)
      printf '%s\n' "$remote_url"
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_head_remote() {
  branch_name="$1"
  branch_remote="$(git config --get "branch.${branch_name}.pushRemote" 2>/dev/null || true)"
  if [ -n "$branch_remote" ]; then
    printf '%s\n' "$branch_remote"
    return 0
  fi

  branch_remote="$(git config --get remote.pushDefault 2>/dev/null || true)"
  if [ -n "$branch_remote" ]; then
    printf '%s\n' "$branch_remote"
    return 0
  fi

  branch_remote="$(git config --get "branch.${branch_name}.remote" 2>/dev/null || true)"
  if [ -n "$branch_remote" ]; then
    printf '%s\n' "$branch_remote"
    return 0
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    printf '%s\n' origin
    return 0
  fi

  return 1
}

branch=""
repo=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --branch" >&2
        usage >&2
        exit 2
      fi
      branch="$2"
      shift 2
      ;;
    --repo)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --repo" >&2
        usage >&2
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

[ -n "$branch" ] || error "Unable to determine branch. Pass --branch explicitly."

if [ -n "$repo" ]; then
  export GH_REPO="$repo"
fi

target_repo="$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')"
head_owner=""

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  head_remote="$(resolve_head_remote "$branch" 2>/dev/null || true)"
  if [ -n "$head_remote" ]; then
    head_remote_url="$(git remote get-url "$head_remote" 2>/dev/null || true)"
    head_repo="$(parse_github_slug_from_url "$head_remote_url" 2>/dev/null || true)"
    if [ -n "$head_repo" ]; then
      head_owner="${head_repo%%/*}"
    fi
  fi
fi

pr_json=""
if [ -n "$head_owner" ]; then
  pr_json="$(
    gh api "repos/$target_repo/pulls?state=open&head=$head_owner:$branch&per_page=100" \
      --jq '
        if length == 0 then
          empty
        else
          sort_by(.updated_at)
          | last
          | {
              number: .number,
              url: .html_url,
              title: .title,
              headRefName: .head.ref
            }
        end
      '
  )"
fi

if [ -z "$pr_json" ]; then
  pr_json="$(
    gh pr list \
      --head "$branch" \
      --state open \
      --json number,url,title,headRefName,headRepositoryOwner,updatedAt \
      --limit 100 \
      --jq '
        map(select(.headRefName == "'"$branch"'"))
        | if length == 0 then
            empty
          else
            (map(.headRepositoryOwner.login) | unique) as $owners
            | if ($owners | length) > 1 then
                error("Multiple open pull requests found for branch " + "'"$branch"'" + " across different head repositories; run this script from the source checkout or configure the branch remote so the head owner can be determined.")
              else
                sort_by(.updatedAt)
                | last
                | {
                    number: .number,
                    url: .url,
                    title: .title,
                    headRefName: .headRefName
                  }
              end
          end
      '
  )"
fi

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
