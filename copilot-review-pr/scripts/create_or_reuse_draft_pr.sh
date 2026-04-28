#!/usr/bin/env sh
set -eu

error() {
  echo "$*" >&2
  exit 1
}

cli_error() {
  echo "$*" >&2
  usage >&2
  exit 2
}

usage() {
  cat <<'EOF'
Usage: create_or_reuse_draft_pr.sh [--branch <branch>] [--repo <owner/repo>] [--base <branch>] [--title <title>] [--body <body>]

Create or reuse a draft pull request for a branch.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required but not found in PATH" >&2
    exit 127
  fi
}

cleanup_file() {
  path="$1"
  if [ -n "$path" ] && [ -f "$path" ]; then
    rm -f "$path"
  fi
}

is_loop_generated_subject() {
  subject="$1"
  case "$subject" in
    "chore: start PR loop"|\
    "chore: address Copilot review feedback (round "*) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_base_ref() {
  if [ -n "$base" ]; then
    printf '%s\n' "$base"
    return 0
  fi

  default_branch="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)"
  if [ -n "$default_branch" ] && [ "$default_branch" != "null" ]; then
    printf '%s\n' "$default_branch"
    return 0
  fi

  return 1
}

list_meaningful_commit_subjects() {
  base_ref="$1"
  merge_base="$(git merge-base "HEAD" "$base_ref" 2>/dev/null || true)"
  if [ -n "$merge_base" ]; then
    git log --format=%s --reverse "$merge_base..HEAD" 2>/dev/null || true
  else
    git log --format=%s --reverse "HEAD" 2>/dev/null || true
  fi | while IFS= read -r subject; do
    [ -n "$subject" ] || continue
    if is_loop_generated_subject "$subject"; then
      continue
    fi
    printf '%s\n' "$subject"
  done
}

build_pr_title() {
  base_ref="$1"
  title_subject="$(list_meaningful_commit_subjects "$base_ref" | head -n 1 || true)"
  if [ -n "$title_subject" ]; then
    printf '%s\n' "$title_subject"
  else
    printf '%s\n' "$branch"
  fi
}

build_pr_body() {
  base_ref="$1"
  subjects="$(list_meaningful_commit_subjects "$base_ref" || true)"
  if [ -n "$subjects" ]; then
    printf '## Summary\n\n'
    printf '%s\n' "$subjects" | awk '{ printf "- %s\n", $0 }'
  else
    printf '## Summary\n\n- Automated draft PR for branch %s.\n' "$branch"
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

count_commits_since_base() {
  base_ref="$1"
  [ -n "$base_ref" ] || return 1
  git rev-list --count "$base_ref..HEAD" 2>/dev/null || return 1
}

branch=""
repo=""
base=""
title=""
body=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch)
      [ "$#" -ge 2 ] || cli_error "Missing value for --branch"
      branch="$2"
      shift 2
      ;;
    --repo)
      [ "$#" -ge 2 ] || cli_error "Missing value for --repo"
      repo="$2"
      shift 2
      ;;
    --base)
      [ "$#" -ge 2 ] || cli_error "Missing value for --base"
      base="$2"
      shift 2
      ;;
    --title)
      [ "$#" -ge 2 ] || cli_error "Missing value for --title"
      title="$2"
      shift 2
      ;;
    --body)
      [ "$#" -ge 2 ] || cli_error "Missing value for --body"
      body="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      cli_error "Unknown argument: $1"
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

require_command git
target_repo="$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')"
head_owner=""
base_ref="$(resolve_base_ref 2>/dev/null || true)"
pr_title="$(build_pr_title "$base_ref")"
pr_body="$(build_pr_body "$base_ref")"

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

existing_pr=""
if [ -n "$head_owner" ]; then
  existing_pr="$(
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
              headRefName: .head.ref,
              isDraft: .draft
            }
        end
      '
  )"
fi

if [ -z "$existing_pr" ]; then
  existing_pr="$(
    gh pr list \
      --head "$branch" \
      --state open \
      --json number,url,title,headRefName,headRepositoryOwner,isDraft,updatedAt \
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
              end
          end
      '
  )"
fi

if [ -n "$existing_pr" ] && [ "$existing_pr" != "null" ]; then
  pr_number="$(printf '%s\n' "$existing_pr" | jq -r '.number')"
  if [ "$(printf '%s\n' "$existing_pr" | jq -r '.isDraft')" != "true" ]; then
    gh pr ready "$pr_number" --undo >/dev/null
  fi
  current_title="$(printf '%s\n' "$existing_pr" | jq -r '.title // empty')"
  if is_loop_generated_subject "$current_title" && [ "$pr_title" != "$current_title" ]; then
    gh pr edit "$pr_number" --title "$pr_title" >/dev/null
  fi
  gh pr view "$pr_number" --json number,url,title,headRefName,isDraft --jq '. + {status: "reused"}'
  exit 0
fi

if [ -n "$base_ref" ]; then
  commit_count="$(count_commits_since_base "$base_ref" 2>/dev/null || true)"
  if [ -n "$commit_count" ] && [ "$commit_count" -eq 0 ]; then
    error "No commits between $base_ref and $branch. Commit your changes and push the branch before creating a draft PR."
  fi
fi

set -- gh pr create --draft --head "$branch"

if [ -n "$base" ]; then
  set -- "$@" --base "$base"
fi

if [ -n "$body" ] && [ -z "$title" ]; then
  title="$branch"
fi

if [ -n "$title" ] || [ -n "$body" ]; then
  if [ -n "$title" ]; then
    set -- "$@" --title "$title"
  fi
  if [ -n "$body" ]; then
    set -- "$@" --body "$body"
  fi
else
  set -- "$@" --title "$pr_title" --body "$pr_body"
fi

create_error_file="$(mktemp)"
trap 'cleanup_file "$create_error_file"' EXIT HUP INT TERM

if pr_url="$("$@" 2>"$create_error_file")"; then
  :
else
  create_error="$(cat "$create_error_file" 2>/dev/null || true)"
  case "$create_error" in
    *"No commits between "*)
      if [ -n "$base_ref" ]; then
        error "No commits between $base_ref and $branch on GitHub. Commit your changes and push the branch before creating a draft PR."
      fi
      error "No commits between the base branch and $branch on GitHub. Commit your changes and push the branch before creating a draft PR."
      ;;
    *)
      printf '%s\n' "$create_error" >&2
      exit 1
      ;;
  esac
fi

[ -n "$pr_url" ] || error "Failed to create draft pull request."

gh pr view "$pr_url" --json number,url,title,headRefName,isDraft --jq '. + {status: "created"}'
