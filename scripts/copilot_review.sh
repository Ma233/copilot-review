#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage: copilot_review.sh <invite|triage> [--branch <branch>] [--repo <owner/repo>]

Subcommands:
  invite   Add @copilot as a reviewer on the matching pull request.
  triage   Fetch the latest Copilot review for the matching pull request.
EOF
}

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [ "$#" -eq 0 ]; then
  echo "Missing subcommand: choose 'invite' or 'triage'." >&2
  usage >&2
  exit 2
fi

subcommand="$1"

case "$subcommand" in
  invite)
    shift
    exec "$script_dir/invite_copilot_reviewer.sh" "$@"
    ;;
  triage)
    shift
    exec "$script_dir/get_latest_copilot_review.sh" "$@"
    ;;
  --help|-h|help)
    usage
    ;;
  *)
    echo "Unknown subcommand: $subcommand" >&2
    usage >&2
    exit 2
    ;;
esac
