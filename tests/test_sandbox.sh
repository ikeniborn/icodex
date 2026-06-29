#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/config/sandbox.sh"

tmp="$(mktemp -d)"
ICODEX_HOME_DIR="$tmp/home"; mkdir -p "$ICODEX_HOME_DIR"
seed() { printf 'bypass_hook_trust = true\nsandbox_mode = "danger-full-access"\napproval_policy = "on-request"\n\n[features]\nmulti_agent = true\n' > "$ICODEX_HOME_DIR/config.toml"; }

# precedence: default is workspace-write
unset ICODEX_SANDBOX; ICODEX_FULL_ACCESS=0
assert_eq "default mode" "workspace-write" "$(resolve_sandbox_mode)"

# env overrides default
ICODEX_SANDBOX="read-only"
assert_eq "env mode" "read-only" "$(resolve_sandbox_mode)"

# flag overrides env
ICODEX_FULL_ACCESS=1
assert_eq "flag overrides env" "danger-full-access" "$(resolve_sandbox_mode)"

# invalid env -> non-zero
ICODEX_FULL_ACCESS=0; ICODEX_SANDBOX="bogus"
( resolve_sandbox_mode >/dev/null 2>&1 ); assert_eq "invalid env nonzero" "1" "$?"

# apply upserts the top-level key (replaces existing danger-full-access)
unset ICODEX_SANDBOX; ICODEX_FULL_ACCESS=0; seed
apply_sandbox_mode
assert_eq "sandbox upserted to default" "1" \
  "$(grep -cFx 'sandbox_mode = "workspace-write"' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "old danger value removed" "0" \
  "$(grep -cFx 'sandbox_mode = "danger-full-access"' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "approval_policy untouched" "1" \
  "$(grep -cFx 'approval_policy = "on-request"' "$ICODEX_HOME_DIR/config.toml")"

# idempotent: second apply is byte-identical
before="$(cat "$ICODEX_HOME_DIR/config.toml")"
apply_sandbox_mode
assert_eq "apply idempotent" "$before" "$(cat "$ICODEX_HOME_DIR/config.toml")"

# danger-full-access prints the warning
ICODEX_FULL_ACCESS=1; seed
warn="$(apply_sandbox_mode 2>&1 >/dev/null)"
assert_contains "warns on full access" "$warn" "full filesystem access enabled"

# upsert inserts the key when absent, before the first section
printf '[features]\nx = 1\n' > "$ICODEX_HOME_DIR/bare.toml"
_upsert_toml_toplevel "$ICODEX_HOME_DIR/bare.toml" sandbox_mode "workspace-write"
assert_eq "inserted before section" "1" \
  "$(grep -cFx 'sandbox_mode = "workspace-write"' "$ICODEX_HOME_DIR/bare.toml")"
head1="$(head -1 "$ICODEX_HOME_DIR/bare.toml")"
assert_eq "inserted at top" 'sandbox_mode = "workspace-write"' "$head1"

# --- _remove_toml_toplevel: drops a top-level key, no-op when absent ---
printf 'sandbox_mode = "danger-full-access"\ndefault_permissions = "ssh-on-request"\n\n[features]\ndefault_permissions = "keep-me"\n' > "$ICODEX_HOME_DIR/rm.toml"
_remove_toml_toplevel "$ICODEX_HOME_DIR/rm.toml" default_permissions
assert_eq "top-level key removed" "0" \
  "$(grep -cFx 'default_permissions = "ssh-on-request"' "$ICODEX_HOME_DIR/rm.toml")"
assert_eq "in-section key preserved" "1" \
  "$(grep -cFx 'default_permissions = "keep-me"' "$ICODEX_HOME_DIR/rm.toml")"
assert_eq "other top-level key preserved" "1" \
  "$(grep -cFx 'sandbox_mode = "danger-full-access"' "$ICODEX_HOME_DIR/rm.toml")"
before_rm="$(cat "$ICODEX_HOME_DIR/rm.toml")"
_remove_toml_toplevel "$ICODEX_HOME_DIR/rm.toml" default_permissions
assert_eq "remove idempotent when absent" "$before_rm" "$(cat "$ICODEX_HOME_DIR/rm.toml")"

rm -rf "$tmp"
finish
