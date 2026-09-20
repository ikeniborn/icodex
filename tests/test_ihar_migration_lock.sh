#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/core/init.sh"
source "$ROOT/lib/config/isolated.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
home="$tmp/homes/project-123"
mkdir -p "$(dirname "$home")"

acquire_codex_home_lifecycle_lock "$home"
if flock -x -n "$home.ihar-lifecycle.lock" true 2>/dev/null; then
  echo "FAIL: migration exclusive lock entered during Codex lifecycle"
  exit 1
fi
eval "exec ${ICODEX_HOME_LIFECYCLE_FD}>&-"
unset ICODEX_HOME_LIFECYCLE_FD
flock -x -n "$home.ihar-lifecycle.lock" true
echo "PASS: Codex holds the shared migration lock for its lifecycle"

project="$tmp/project"
ICODEX_HOMES_DIR="$tmp/integration-homes"
mkdir -p "$project" "$ICODEX_HOMES_DIR"
project_root="$(cd "$project" && pwd -P)"
project_hash="$(printf '%s' "$project_root" | sha256sum | cut -c1-12)"
project_home="$ICODEX_HOMES_DIR/$(basename "$project_root")-$project_hash"
exec {exclusive_fd}>"$project_home.ihar-lifecycle.lock"
flock -x "$exclusive_fd"
if (cd "$project" && ICODEX_HOME_LOCK_TIMEOUT=0 setup_codex_home >/dev/null 2>&1); then
  echo "FAIL: setup_codex_home bypassed the migration lock"
  exit 1
fi
[[ ! -d "$project_home" ]]
exec {exclusive_fd}>&-
echo "PASS: Codex setup refuses an active migration"
