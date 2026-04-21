#!/usr/bin/env sh
set -eu

error() {
  echo "$*" >&2
  exit 1
}

cli_error() {
  echo "$*" >&2
  exit 2
}

usage() {
  cat <<'EOF'
Usage: get_latest_copilot_review.sh [--branch <name>] [--repo <owner/repo>]
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required but not found in PATH" >&2
    exit 127
  fi
}

collect_paginated_array() {
  endpoint="$1"
  gh api --paginate "$endpoint" | jq -s 'map(if type == "array" then .[] else . end)'
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
      [ "$#" -ge 2 ] || cli_error "Missing value for --branch"
      branch="$2"
      shift 2
      ;;
    --repo)
      [ "$#" -ge 2 ] || cli_error "Missing value for --repo"
      repo="$2"
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

require_command git
require_command gh
require_command jq

if ! gh auth status >/dev/null 2>&1; then
  error "gh is installed but not authenticated. Run 'gh auth login' first."
fi

if [ -n "$repo" ]; then
  export GH_REPO="$repo"
fi

if [ -z "$branch" ]; then
  branch="$(git branch --show-current 2>/dev/null || true)"
fi

[ -n "$branch" ] || error "Unable to determine branch. Pass --branch explicitly."

target_repo="$repo"
if [ -z "$target_repo" ]; then
  target_repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
fi

[ -n "$target_repo" ] || error "Unable to determine repository. Pass --repo explicitly."

head_owner=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
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
    gh api "repos/$target_repo/pulls?state=all&head=$head_owner:$branch&per_page=100" \
      --jq '
        if length == 0 then
          empty
        else
          (map(select(.state == "open")) | sort_by(.updated_at) | last) // (sort_by(.updated_at) | last)
          | {
              number: .number,
              url: .html_url,
              headRefName: .head.ref,
              baseRefName: .base.ref
            }
        end
      ' 2>/dev/null || true
  )"
fi

if [ -z "$pr_json" ]; then
  pr_json="$(
    gh pr list \
      --head "$branch" \
      --state all \
      --json number,url,headRefName,baseRefName,headRepositoryOwner,updatedAt,state \
      --limit 100 \
      --jq '
        map(select(.headRefName == "'"$branch"'"))
        | if length == 0 then
            empty
          else
            (map(.headRepositoryOwner.login) | unique) as $owners
            | if ($owners | length) > 1 then
                error("Multiple pull requests found for branch " + "'"$branch"'" + " across different head repositories; run this script from the source checkout or configure the branch remote so the head owner can be determined.")
              else
                (map(select(.state == "open")) | sort_by(.updatedAt) | last) // (sort_by(.updatedAt) | last)
              end
          end
      '
  )"
fi

[ -n "$pr_json" ] || error "No pull request found for branch: $branch"

pr_number="$(printf '%s\n' "$pr_json" | jq -r '.number')"

reviews_json="$(collect_paginated_array "repos/$target_repo/pulls/$pr_number/reviews?per_page=100")"

latest_review_json="$(
  printf '%s\n' "$reviews_json" | jq '
    map(
      select(
        (.user.login // "" | ascii_downcase | contains("copilot"))
        and (.state // "" | ascii_upcase) != "PENDING"
      )
    )
    | sort_by(.submitted_at // "", (.id // 0))
    | if length == 0 then null else last end
  '
)"

if [ "$(printf '%s\n' "$latest_review_json" | jq -r 'if . == null then "null" else "review" end')" = "null" ]; then
  jq -n \
    --argjson pr "$pr_json" \
    '{
      pull_request: {
        number: ($pr.number // null),
        url: ($pr.url // null),
        headRefName: ($pr.headRefName // null),
        baseRefName: ($pr.baseRefName // null)
      },
      review: null
    }'
  exit 0
fi

review_id="$(printf '%s\n' "$latest_review_json" | jq -r '.id')"
comments_json="$(collect_paginated_array "repos/$target_repo/pulls/$pr_number/reviews/$review_id/comments?per_page=100")"

jq -n \
  --argjson pr "$pr_json" \
  --argjson review "$latest_review_json" \
  --argjson comments "$comments_json" \
  '{
    pull_request: {
      number: ($pr.number // null),
      url: ($pr.url // null),
      headRefName: ($pr.headRefName // null),
      baseRefName: ($pr.baseRefName // null)
    },
    review: {
      id: (($review.id // null) | if . == null then null else tostring end),
      state: ($review.state // null),
      body: ($review.body // ""),
      submittedAt: ($review.submitted_at // null),
      url: ($review.html_url // null),
      author: {
        login: ($review.user.login // null)
      },
      comments: (
        $comments
        | map({
            id: ((.id // null) | if . == null then null else tostring end),
            path: (.path // null),
            line: (.line // null),
            side: (.side // null),
            body: (.body // ""),
            url: (.html_url // null),
            commitId: (.commit_id // null),
            createdAt: (.created_at // null),
            updatedAt: (.updated_at // null)
          })
      )
    }
  }'
