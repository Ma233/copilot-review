#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
skills_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"

exec "$skills_root/copilot-review-invite/scripts/invite_copilot_reviewer.sh" "$@"
