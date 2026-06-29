#!/usr/bin/env bash
# Effective sandbox mode resolution and idempotent config write.
# Precedence (low -> high): workspace-write default < ICODEX_SANDBOX < --full-access.
# approval_policy is never touched here; only sandbox_mode is managed.

# Echo the effective sandbox mode; return 1 + log_error on an invalid ICODEX_SANDBOX.
resolve_sandbox_mode() {
  if (( ${ICODEX_FULL_ACCESS:-0} )); then
    printf 'danger-full-access\n'
    return 0
  fi
  local mode="${ICODEX_SANDBOX:-workspace-write}"
  case "$mode" in
    read-only|workspace-write|danger-full-access) printf '%s\n' "$mode" ;;
    *) log_error "invalid ICODEX_SANDBOX '$mode' (want: read-only|workspace-write|danger-full-access)"; return 1 ;;
  esac
}

# Idempotently upsert a top-level `key = "value"` line (before the first [section]).
_upsert_toml_toplevel() { # <config> <key> <value>
  local config="$1" key="$2" val="$3" tmp
  tmp="$(mktemp)"
  awk -v key="$key" -v val="$val" '
    BEGIN { done = 0 }
    /^[[:space:]]*\[/ {
      if (!done) { print key " = \"" val "\""; done = 1 }
      print; next
    }
    !done && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") {
      print key " = \"" val "\""; done = 1; next
    }
    { print }
    END { if (!done) print key " = \"" val "\"" }
  ' "$config" > "$tmp"
  cmp -s "$tmp" "$config" || cat "$tmp" > "$config"
  rm -f "$tmp"
}

# Resolve and write sandbox_mode into the per-project config; warn on full access.
apply_sandbox_mode() {
  local config="$ICODEX_HOME_DIR/config.toml" mode
  mode="$(resolve_sandbox_mode)" || return 1
  _upsert_toml_toplevel "$config" sandbox_mode "$mode"
  if [[ "$mode" == "danger-full-access" ]]; then
    log_warn "sandbox = danger-full-access — full filesystem access enabled (project: $(basename "$ICODEX_HOME_DIR"))"
  fi
  return 0
}
