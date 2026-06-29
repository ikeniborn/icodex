#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/config/sandbox.sh"
source "$ROOT/lib/config/permissions.sh"

clear_env() { unset ICODEX_MODE ICODEX_SANDBOX ICODEX_APPROVAL ICODEX_PERMISSIONS; ICODEX_FULL_ACCESS=0; }

# --- resolve_mode: presets ---
clear_env
assert_eq "default mode is full-ask" "danger-full-access on-request ssh-on-request" "$(resolve_mode)"
clear_env; ICODEX_MODE=ro
assert_eq "ro preset" "read-only on-request dev-safe" "$(resolve_mode)"
clear_env; ICODEX_MODE=safe
assert_eq "safe preset" "workspace-write on-request dev-safe" "$(resolve_mode)"
clear_env; ICODEX_MODE=full-ask
assert_eq "full-ask preset" "danger-full-access on-request ssh-on-request" "$(resolve_mode)"
clear_env; ICODEX_MODE=full-auto
assert_eq "full-auto preset" "danger-full-access never none" "$(resolve_mode)"

# --- resolve_mode: granular overrides ---
clear_env; ICODEX_MODE=safe; ICODEX_APPROVAL=never
assert_eq "approval override" "workspace-write never dev-safe" "$(resolve_mode)"
clear_env; ICODEX_MODE=safe; ICODEX_PERMISSIONS=none
assert_eq "permissions override none" "workspace-write on-request none" "$(resolve_mode)"
clear_env; ICODEX_MODE=safe; ICODEX_SANDBOX=danger-full-access
assert_eq "sandbox override" "danger-full-access on-request dev-safe" "$(resolve_mode)"
clear_env; ICODEX_MODE=ro; ICODEX_FULL_ACCESS=1
assert_eq "full-access flag forces sandbox" "danger-full-access on-request dev-safe" "$(resolve_mode)"

# --- resolve_mode: validation ---
clear_env; ICODEX_MODE=bogus
( resolve_mode >/dev/null 2>&1 ); assert_eq "invalid mode nonzero" "1" "$?"
clear_env; ICODEX_APPROVAL=bogus
( resolve_mode >/dev/null 2>&1 ); assert_eq "invalid approval nonzero" "1" "$?"
clear_env; ICODEX_PERMISSIONS=bogus
( resolve_mode >/dev/null 2>&1 ); assert_eq "invalid permissions nonzero" "1" "$?"
clear_env; ICODEX_SANDBOX=bogus
( resolve_mode >/dev/null 2>&1 ); assert_eq "invalid sandbox nonzero" "1" "$?"

finish
