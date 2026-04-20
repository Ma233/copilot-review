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

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

usage() {
  cat <<'EOF'
Usage: run_copilot_review_loop.sh [options]

Options:
  --branch <branch>          Branch name. Defaults to the current branch.
  --repo <owner/repo>        GitHub repository. Defaults to the current repository.
  --base <branch>            Base branch when creating a draft PR.
  --max-rounds <count>       Maximum fix rounds. Default: 3.
  --poll-interval <seconds>  Seconds between review polls. Default: 120.
  --review-timeout <seconds> Maximum time to wait for a new review. Default: 1800.
  --codex-model <model>      Optional Codex model override.
  --help                     Show this help.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required but not found in PATH" >&2
    exit 127
  fi
}

require_non_negative_integer() {
  value="$1"
  name="$2"
  case "$value" in
    ''|*[!0-9]*)
      error "$name must be a non-negative integer"
      ;;
  esac
}

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
skill_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"

branch=""
repo=""
base=""
max_rounds=3
poll_interval=120
review_timeout=1800
codex_model=""

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
    --max-rounds)
      [ "$#" -ge 2 ] || cli_error "Missing value for --max-rounds"
      max_rounds="$2"
      shift 2
      ;;
    --poll-interval)
      [ "$#" -ge 2 ] || cli_error "Missing value for --poll-interval"
      poll_interval="$2"
      shift 2
      ;;
    --review-timeout)
      [ "$#" -ge 2 ] || cli_error "Missing value for --review-timeout"
      review_timeout="$2"
      shift 2
      ;;
    --codex-model)
      [ "$#" -ge 2 ] || cli_error "Missing value for --codex-model"
      codex_model="$2"
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
require_command codex

if ! gh auth status >/dev/null 2>&1; then
  error "gh is installed but not authenticated. Run 'gh auth login' first."
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo_root" ] || error "This script must run inside a git repository."

cd "$repo_root"

require_non_negative_integer "$max_rounds" "--max-rounds"
require_non_negative_integer "$poll_interval" "--poll-interval"
require_non_negative_integer "$review_timeout" "--review-timeout"

if [ -z "$branch" ]; then
  branch="$(git branch --show-current 2>/dev/null || true)"
fi
[ -n "$branch" ] || error "Unable to determine branch. Pass --branch explicitly."

safe_branch="$(printf '%s' "$branch" | tr '/ ' '__')"
git_dir="$(git rev-parse --git-path . 2>/dev/null || true)"
[ -n "$git_dir" ] || error "Unable to determine git metadata directory."
state_dir="$git_dir/copilot-review-loop/$safe_branch"
mkdir -p "$state_dir"

state_file="$state_dir/state.json"
history_file="$state_dir/round_history.json"
review_history_file="$state_dir/review_history.json"
recent_context_file="$state_dir/recent_context.json"
review_file="$state_dir/latest_review.json"
summary_file="$state_dir/latest_summary.json"
prompt_file="$state_dir/latest_prompt.md"
last_message_file="$state_dir/latest_last_message.json"

if [ ! -f "$history_file" ]; then
  printf '[]\n' > "$history_file"
fi

if [ ! -f "$review_history_file" ]; then
  printf '[]\n' > "$review_history_file"
fi

write_state() {
  state_status="$1"
  state_round="$2"
  state_pr_number="$3"
  state_last_review_id="$4"
  state_note="$5"
  jq -n \
    --arg branch "$branch" \
    --arg repo "${repo:-}" \
    --arg status "$state_status" \
    --arg note "$state_note" \
    --argjson round "$state_round" \
    --argjson max_rounds "$max_rounds" \
    --arg pr_number "$state_pr_number" \
    --arg last_review_id "$state_last_review_id" \
    '{
      branch: $branch,
      repo: (if $repo == "" then null else $repo end),
      status: $status,
      note: $note,
      round: $round,
      max_rounds: $max_rounds,
      pull_request_number: (if $pr_number == "" then null else ($pr_number | tonumber) end),
      last_review_id: (if $last_review_id == "" then null else $last_review_id end)
    }' > "$state_file"
}

append_round_history() {
  history_round="$1"
  history_comment_count="$2"
  history_review_id="$3"
  history_entry_file="$4"

  tmp_history_file="$state_dir/round_history.tmp.json"
  jq \
    --argjson round "$history_round" \
    --argjson comment_count "$history_comment_count" \
    --arg review_id "$history_review_id" \
    '
      . + [
        (input | . + {
          round: $round,
          comment_count: $comment_count,
          review_id: $review_id
        })
      ]
    ' "$history_file" "$history_entry_file" > "$tmp_history_file"
  mv "$tmp_history_file" "$history_file"
}

append_review_history() {
  history_round="$1"

  tmp_review_history_file="$state_dir/review_history.tmp.json"
  jq \
    --argjson round "$history_round" \
    '
      . + [
        {
          round: $round,
          review_id: (input.review.id // ""),
          submitted_at: (input.review.submittedAt // null),
          comment_count: ((input.review.comments // []) | length),
          comments: (
            (input.review.comments // [])
            | map({
                path: (.path // null),
                line: (.line // null),
                body: .body,
                url: (.url // null)
              })
          )
        }
      ]
    ' "$review_history_file" "$review_file" > "$tmp_review_history_file"
  mv "$tmp_review_history_file" "$review_history_file"
}

build_recent_context() {
  current_round="$1"

  jq -n \
    --argjson current_round "$current_round" \
    --slurpfile rounds "$history_file" \
    --slurpfile reviews "$review_history_file" \
    '
      def recent($items; $count):
        if ($items | length) <= $count then $items else $items[-$count:] end;
      def low_value_rounds($items):
        [$items[] | select((.developer_value_score <= 1) or (.novelty_score <= 1))] | length;

      ($rounds[0]) as $all_rounds
      | ($reviews[0]) as $all_reviews
      | (recent($all_rounds; 4)) as $recent_rounds
      | (recent($all_reviews; 3)) as $recent_reviews
      | {
          total_recorded_rounds: ($all_rounds | length),
          consecutive_zero_apply_rounds: (
            if ($recent_rounds | length) >= 2 and
               ($recent_rounds[-1].applied_count == 0) and
               ($recent_rounds[-2].applied_count == 0)
            then 2
            else 0
            end
          ),
          consecutive_degraded_rounds: (
            if ($recent_rounds | length) >= 2 and
               ($recent_rounds[-1].loop_health == "degraded") and
               ($recent_rounds[-2].loop_health == "degraded")
            then 2
            else 0
            end
          ),
          low_value_rounds_in_recent_window: low_value_rounds($recent_rounds),
          repeated_comment_bodies_in_recent_reviews: (
            ($recent_reviews | map(.comments[]?.body) | map(ascii_downcase)) as $bodies
            | (($bodies | unique | length) < ($bodies | length))
          ),
          repeated_themes_in_recent_rounds: (
            ([$recent_rounds[] | .repeat_signals[]?]) as $signals
            | (($signals | unique | length) < ($signals | length))
          ),
          stricter_threshold_active: ($current_round >= 3)
        } as $signals
      | {
          current_round: $current_round,
          recent_rounds: $recent_rounds,
          recent_reviews: $recent_reviews,
          signals: $signals,
          degradation_reasons: [
            if $signals.consecutive_degraded_rounds >= 2 then
              "Two consecutive rounds were already classified as degraded."
            else empty end,
            if $signals.consecutive_zero_apply_rounds >= 2 then
              "The last two rounds produced no applied changes."
            else empty end,
            if $signals.low_value_rounds_in_recent_window >= 3 then
              "Recent rounds have mostly low novelty or low developer value."
            else empty end,
            if $signals.repeated_comment_bodies_in_recent_reviews then
              "Recent review comments repeat the same bodies or very similar wording."
            else empty end,
            if $signals.repeated_themes_in_recent_rounds then
              "Recent rounds keep revisiting the same review themes."
            else empty end,
            if $signals.stricter_threshold_active then
              "Late-round stricter thresholds are active."
            else empty end
          ]
        }
    ' > "$recent_context_file"
}

explain_degradation() {
  jq -r '
    if (.degradation_reasons | length) == 0 then
      "No explicit degradation reasons recorded."
    else
      (.degradation_reasons | join(" "))
    end
  ' "$recent_context_file"
}

history_indicates_degradation() {
  jq -e \
    '
      (.recent_rounds | length) as $count
      | if $count < 2 then
          false
        else
          (.recent_rounds[-1]) as $current
          | (.recent_rounds[-2:]) as $last2
          | (.recent_rounds[-3:]) as $last3
          | (
              ((.signals.consecutive_degraded_rounds >= 2)) or
              (($current.round >= 2) and ($current.loop_health == "degraded")) or
              ((.signals.stricter_threshold_active) and ($current.loop_health == "stalled") and (($current.developer_value_score <= 1) or ($current.novelty_score <= 1))) or
              (($count >= 2) and ($last2 | all(.applied_count == 0 and (.verify_count + .ignore_count) > 0))) or
              (($count >= 3) and ($last3 | all((.developer_value_score <= 1) or (.novelty_score <= 1)))) or
              (.signals.repeated_comment_bodies_in_recent_reviews and ($current.novelty_score <= 2)) or
              ((.signals.stricter_threshold_active) and .signals.repeated_themes_in_recent_rounds and ($current.developer_value_score <= 2))
            )
        end
    ' "$recent_context_file" >/dev/null 2>&1
}

has_worktree_changes() {
  [ -n "$(git status --porcelain)" ]
}

push_branch() {
  upstream_remote="$(git config --get "branch.${branch}.remote" 2>/dev/null || true)"
  upstream_merge="$(git config --get "branch.${branch}.merge" 2>/dev/null || true)"
  if [ -n "$upstream_remote" ] && [ -n "$upstream_merge" ]; then
    git push
  else
    remote_name="$(git config --get "branch.${branch}.pushRemote" 2>/dev/null || true)"
    if [ -z "$remote_name" ]; then
      remote_name="$(git config --get "remote.pushDefault" 2>/dev/null || true)"
    fi
    if [ -z "$remote_name" ] && git remote get-url origin >/dev/null 2>&1; then
      remote_name="origin"
    fi
    [ -n "$remote_name" ] || error "No explicit git remote configured for branch push. Configure branch.${branch}.remote/merge, branch.${branch}.pushRemote, or remote.pushDefault, or add an 'origin' remote."
    git push -u "$remote_name" "$branch"
  fi
}

commit_all_changes() {
  commit_round="$1"
  commit_reason="$2"
  if ! has_worktree_changes; then
    return 1
  fi

  git add -A
  if git diff --cached --quiet; then
    return 1
  fi

  if [ "$commit_round" -eq 0 ]; then
    commit_message="chore: start PR loop"
  else
    commit_message="chore: address Copilot review feedback (round $commit_round)"
  fi

  if [ -n "$commit_reason" ]; then
    commit_message="$commit_message

$commit_reason"
  fi

  git commit -m "$commit_message" >/dev/null
  return 0
}

create_or_reuse_pr() {
  if [ -n "$repo" ]; then
    if [ -n "$base" ]; then
      "$script_dir/create_or_reuse_draft_pr.sh" --branch "$branch" --repo "$repo" --base "$base"
    else
      "$script_dir/create_or_reuse_draft_pr.sh" --branch "$branch" --repo "$repo"
    fi
  else
    if [ -n "$base" ]; then
      "$script_dir/create_or_reuse_draft_pr.sh" --branch "$branch" --base "$base"
    else
      "$script_dir/create_or_reuse_draft_pr.sh" --branch "$branch"
    fi
  fi
}

invite_copilot() {
  if [ -n "$repo" ]; then
    "$script_dir/invite_copilot_reviewer.sh" --branch "$branch" --repo "$repo"
  else
    "$script_dir/invite_copilot_reviewer.sh" --branch "$branch"
  fi
}

fetch_latest_review() {
  if [ -n "$repo" ]; then
    "$script_dir/get_latest_copilot_review.sh" --branch "$branch" --repo "$repo"
  else
    "$script_dir/get_latest_copilot_review.sh" --branch "$branch"
  fi
}

build_prompt() {
  cat "$skill_root/templates/triage_prompt.md" > "$prompt_file"
  cat >> "$prompt_file" <<EOF

Repository root: $repo_root
Branch: $branch
Review payload file: $review_file
Recent loop context file: $recent_context_file

Task:
1. Read the review payload JSON from the file above.
2. Read the recent loop context JSON file above. It already summarizes the recent rounds, recent review comments, and degradation signals.
3. Triage each distinct Copilot comment as apply, verify, or ignore.
4. Implement only the feedback that is strong enough to apply safely now.
5. Set loop_health and recommended_action based on whether the review is still useful or has degraded into churn.
6. If the review requires ambiguous product decisions, cross-team context, or risky changes, stop and return human handoff.
7. Run focused validation when practical.
8. Do not create commits and do not push.

Return JSON that matches the provided schema exactly.
EOF
}

run_codex_fix() {
  build_prompt

  set +e
  if [ -n "$codex_model" ]; then
    codex exec \
      --full-auto \
      -C "$repo_root" \
      --output-schema "$skill_root/templates/triage_schema.json" \
      -o "$last_message_file" \
      --model "$codex_model" \
      - < "$prompt_file" > "$summary_file"
  else
    codex exec \
      --full-auto \
      -C "$repo_root" \
      --output-schema "$skill_root/templates/triage_schema.json" \
      -o "$last_message_file" \
      - < "$prompt_file" > "$summary_file"
  fi
  codex_status="$?"
  set -e
  return "$codex_status"
}

validate_summary_file() {
  jq -e '
    (.outcome | type) == "string" and
    (.loop_health | type) == "string" and
    (.recommended_action | type) == "string" and
    (.developer_value_score | type) == "number" and (.developer_value_score >= 0) and (.developer_value_score <= 5) and (.developer_value_score == floor) and
    (.novelty_score | type) == "number" and (.novelty_score >= 0) and (.novelty_score <= 5) and (.novelty_score == floor) and
    (.repeat_signals | type) == "array" and
    (.summary | type) == "string" and
    (.applied_count | type) == "number" and (.applied_count >= 0) and (.applied_count == floor) and
    (.verify_count | type) == "number" and (.verify_count >= 0) and (.verify_count == floor) and
    (.ignore_count | type) == "number" and (.ignore_count >= 0) and (.ignore_count == floor) and
    (.tests | type) == "array" and
    (.decisions | type) == "array" and
    ([.decisions[] | (.comment | type) == "string" and (.classification | type) == "string" and (.rationale | type) == "string" and (.theme | type) == "string"] | all)
  ' "$summary_file" >/dev/null 2>&1
}

wait_for_new_review() {
  last_review_id="$1"
  deadline=$(( $(date +%s) + review_timeout ))

  while [ "$(date +%s)" -lt "$deadline" ]; do
    review_json="$(fetch_latest_review 2>/dev/null || true)"
    if [ -n "$review_json" ]; then
      current_review_id="$(printf '%s\n' "$review_json" | jq -r '.review.id // empty')"
      if [ -n "$current_review_id" ] && [ "$current_review_id" != "$last_review_id" ]; then
        printf '%s\n' "$review_json" > "$review_file"
        return 0
      fi
    fi
    sleep "$poll_interval"
  done

  return 1
}

log "Working tree: $repo_root"
log "Branch: $branch"
write_state "running" 0 "" "" "starting"

if commit_all_changes 0 "Automated bootstrap commit for the Copilot PR loop."; then
  log "Created bootstrap commit."
  push_branch
  log "Pushed bootstrap commit."
else
  log "No local changes to commit before starting."
  push_branch
  log "Pushed branch state."
fi

pr_json="$(create_or_reuse_pr)"
pr_number="$(printf '%s\n' "$pr_json" | jq -r '.number')"
pr_url="$(printf '%s\n' "$pr_json" | jq -r '.url')"
current_review_json="$(fetch_latest_review 2>/dev/null || true)"
last_review_id="$(printf '%s\n' "$current_review_json" | jq -r '.review.id // empty' 2>/dev/null || true)"
write_state "running" 0 "$pr_number" "$last_review_id" "draft_pr_ready"
log "Draft PR ready: #$pr_number $pr_url"
round=1

while [ "$round" -le "$max_rounds" ]; do
  write_state "waiting_for_review" "$round" "$pr_number" "$last_review_id" "copilot_invited"
  invite_copilot >/dev/null
  log "Invited @copilot for round $round."

  if ! wait_for_new_review "$last_review_id"; then
    write_state "needs_human" "$round" "$pr_number" "$last_review_id" "timed_out_waiting_for_review"
    log "Timed out waiting for a new Copilot review."
    exit 1
  fi

  current_review_id="$(jq -r '.review.id' "$review_file")"
  comment_count="$(jq -r '.review.comments | length' "$review_file")"
  last_review_id="$current_review_id"
  append_review_history "$round"
  build_recent_context "$round"
  write_state "review_received" "$round" "$pr_number" "$last_review_id" "copilot_review_received"
  log "Received Copilot review $current_review_id with $comment_count comments."

  if [ "$comment_count" -eq 0 ]; then
    write_state "completed" "$round" "$pr_number" "$last_review_id" "review_has_no_comments"
    log "Copilot review is quiet. Loop finished."
    exit 0
  fi

  if ! run_codex_fix; then
    write_state "needs_human" "$round" "$pr_number" "$last_review_id" "codex_exec_failed"
    log "Codex failed while processing review feedback."
    exit 1
  fi

  if ! validate_summary_file; then
    write_state "needs_human" "$round" "$pr_number" "$last_review_id" "invalid_codex_summary_json"
    log "Codex produced an invalid summary JSON. Inspect $summary_file and $prompt_file."
    exit 1
  fi

  outcome="$(jq -r '.outcome' "$summary_file")"
  loop_health="$(jq -r '.loop_health' "$summary_file")"
  recommended_action="$(jq -r '.recommended_action' "$summary_file")"
  summary="$(jq -r '.summary' "$summary_file")"
  applied_count="$(jq -r '.applied_count' "$summary_file")"
  developer_value_score="$(jq -r '.developer_value_score' "$summary_file")"
  novelty_score="$(jq -r '.novelty_score' "$summary_file")"
  append_round_history "$round" "$comment_count" "$last_review_id" "$summary_file"
  build_recent_context "$round"
  write_state "codex_finished" "$round" "$pr_number" "$last_review_id" "$loop_health/$recommended_action"
  log "Codex outcome: $outcome, loop health: $loop_health, recommended action: $recommended_action. $summary"

  if [ "$outcome" = "human_handoff" ]; then
    write_state "needs_human" "$round" "$pr_number" "$last_review_id" "codex_requested_human_handoff"
    log "Codex requested human intervention."
    exit 1
  fi

  if [ "$recommended_action" = "stop_for_human" ]; then
    degradation_reason="$(explain_degradation)"
    write_state "needs_human" "$round" "$pr_number" "$last_review_id" "review_loop_degraded_for_human: $degradation_reason"
    log "Stopping for human review because the loop is no longer high value. $degradation_reason"
    exit 1
  fi

  if [ "$recommended_action" = "stop_no_value" ]; then
    degradation_reason="$(explain_degradation)"
    write_state "completed" "$round" "$pr_number" "$last_review_id" "review_loop_has_no_more_value: $degradation_reason"
    log "Stopping because the loop no longer provides enough developer value. $degradation_reason"
    exit 0
  fi

  if [ "$outcome" = "no_action_needed" ] || [ "$applied_count" -eq 0 ]; then
    write_state "completed" "$round" "$pr_number" "$last_review_id" "no_more_changes_needed"
    log "No code changes were needed after triage."
    exit 0
  fi

  if history_indicates_degradation; then
    degradation_reason="$(explain_degradation)"
    write_state "needs_human" "$round" "$pr_number" "$last_review_id" "review_loop_degraded_by_history: $degradation_reason"
    log "Stopping because recent rounds show repeated low-value review churn. $degradation_reason"
    exit 1
  fi

  if ! commit_all_changes "$round" "$summary"; then
    write_state "needs_human" "$round" "$pr_number" "$last_review_id" "codex_reported_changes_but_git_is_clean"
    log "Codex reported changes, but the git working tree is clean."
    exit 1
  fi

  push_branch
  log "Pushed round $round fixes."
  round=$((round + 1))
done

write_state "needs_human" "$max_rounds" "$pr_number" "$last_review_id" "max_rounds_reached"
log "Reached max rounds. Human review is now required."
exit 1
