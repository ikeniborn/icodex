#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/config/permissions.sh"

tmp="$(mktemp -d)"
cfg="$tmp/config.toml"
printf 'sandbox_mode = "workspace-write"\napproval_policy = "on-request"\n' > "$cfg"
root="/home/user/Project/some-repo"

ensure_project_trust "$cfg" "$root"
assert_eq "trust block added" "1" "$(grep -cF "[projects.\"$root\"]" "$cfg")"
assert_eq "trust level trusted" "1" "$(grep -cFx 'trust_level = "trusted"' "$cfg")"
assert_eq "approval_policy untouched" "1" "$(grep -cFx 'approval_policy = "on-request"' "$cfg")"

# idempotent: a second call adds no duplicate block
ensure_project_trust "$cfg" "$root"
assert_eq "trust block not duplicated" "1" "$(grep -cF "[projects.\"$root\"]" "$cfg")"

rm -rf "$tmp"
finish
