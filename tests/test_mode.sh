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

# --- ensure_git_writable: grants .git write under a profile's :workspace_roots ---
gt="$(mktemp -d)"; gcfg="$gt/config.toml"
cat > "$gcfg" <<'EOF'
[permissions.dev-safe.filesystem]
":minimal" = "read"

[permissions.dev-safe.filesystem.":workspace_roots"]
"." = "write"
"**/.env" = "deny"

[permissions.ssh-on-request.filesystem.":workspace_roots"]
"." = "write"
EOF

ensure_git_writable "$gcfg" dev-safe
git_in_devsafe="$(awk '
  /^\[/ { insec = ($0 == "[permissions.dev-safe.filesystem.\":workspace_roots\"]") }
  insec && $0 == "\".git/\" = \"write\"" { c++ }
  END { print c + 0 }
' "$gcfg")"
assert_eq "git write under dev-safe workspace_roots" "1" "$git_in_devsafe"
dot_in_devsafe="$(awk '
  /^\[/ { insec = ($0 == "[permissions.dev-safe.filesystem.\":workspace_roots\"]") }
  insec && $0 == "\".\" = \"write\"" { c++ }
  END { print c + 0 }
' "$gcfg")"
assert_eq "dev-safe '.' write preserved" "1" "$dot_in_devsafe"
assert_eq "dev-safe env deny preserved" "1" "$(grep -cFx '"**/.env" = "deny"' "$gcfg")"

ensure_git_writable "$gcfg" ssh-on-request
git_in_ssh="$(awk '
  /^\[/ { insec = ($0 == "[permissions.ssh-on-request.filesystem.\":workspace_roots\"]") }
  insec && $0 == "\".git/\" = \"write\"" { c++ }
  END { print c + 0 }
' "$gcfg")"
assert_eq "git write under ssh-on-request workspace_roots" "1" "$git_in_ssh"

before_git="$(cat "$gcfg")"
ensure_git_writable "$gcfg" dev-safe
assert_eq "ensure_git_writable idempotent" "$before_git" "$(cat "$gcfg")"
rm -rf "$gt"

finish
