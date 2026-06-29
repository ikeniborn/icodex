#!/usr/bin/env bash
# Effective sandbox mode resolution and idempotent config write.
# Precedence (low -> high): workspace-write default < ICODEX_SANDBOX < --full-access.
# Run-mode resolution and idempotent config write: sandbox_mode, approval_policy,
# and the managed permission profile (default_permissions) are all managed here.

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

# Echo "sandbox approval permissions" for a preset name; return 1 if unknown.
_mode_preset() { # <mode>
  case "$1" in
    ro)        printf 'read-only on-request dev-safe\n' ;;
    safe)      printf 'workspace-write on-request dev-safe\n' ;;
    full-ask)  printf 'danger-full-access on-request ssh-on-request\n' ;;
    full-auto) printf 'danger-full-access never none\n' ;;
    *)         return 1 ;;
  esac
}

# Validate <value> against the remaining args (allowed set); return 0/1.
_mode_valid() { # <value> <allowed...>
  local v="$1" a; shift
  for a in "$@"; do [[ "$v" == "$a" ]] && return 0; done
  return 1
}

# Echo the effective "sandbox approval permissions" triple. Preset (default
# full-ask) < ICODEX_MODE < granular ICODEX_SANDBOX/APPROVAL/PERMISSIONS.
# log_error + return 1 on any invalid value.
resolve_mode() {
  local mode="${ICODEX_MODE:-full-ask}" preset sandbox approval permissions
  if ! preset="$(_mode_preset "$mode")"; then
    log_error "invalid ICODEX_MODE '$mode' (want: ro|safe|full-ask|full-auto)"; return 1
  fi
  read -r sandbox approval permissions <<<"$preset"

  # Sandbox field: an explicit ICODEX_SANDBOX or --full-access defers to
  # resolve_sandbox_mode (its precedence + validation); else the preset stands.
  if [[ -n "${ICODEX_SANDBOX:-}" ]] || (( ${ICODEX_FULL_ACCESS:-0} )); then
    sandbox="$(resolve_sandbox_mode)" || return 1
  fi

  if [[ -n "${ICODEX_APPROVAL:-}" ]]; then
    _mode_valid "$ICODEX_APPROVAL" untrusted on-failure on-request never \
      || { log_error "invalid ICODEX_APPROVAL '$ICODEX_APPROVAL' (want: untrusted|on-failure|on-request|never)"; return 1; }
    approval="$ICODEX_APPROVAL"
  fi

  if [[ -n "${ICODEX_PERMISSIONS:-}" ]]; then
    _mode_valid "$ICODEX_PERMISSIONS" dev-safe ssh-on-request none \
      || { log_error "invalid ICODEX_PERMISSIONS '$ICODEX_PERMISSIONS' (want: dev-safe|ssh-on-request|none)"; return 1; }
    permissions="$ICODEX_PERMISSIONS"
  fi

  printf '%s %s %s\n' "$sandbox" "$approval" "$permissions"
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

# Idempotently remove a top-level `key = ...` line (before the first [section]).
_remove_toml_toplevel() { # <config> <key>
  local config="$1" key="$2" tmp
  tmp="$(mktemp)"
  awk -v key="$key" '
    /^[[:space:]]*\[/ { insec = 1 }
    !insec && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") { next }
    { print }
  ' "$config" > "$tmp"
  cmp -s "$tmp" "$config" || cat "$tmp" > "$config"
  rm -f "$tmp"
}

# Resolve the run mode and write it into the per-project config: sandbox_mode +
# approval_policy (top-level upserts), default_permissions (upsert, or removed for
# `none`), and the .git writability grant for the active managed profile. Warns on
# danger-full-access and on a disabled managed layer.
apply_mode() {
  local config="$ICODEX_HOME_DIR/config.toml" triple sandbox approval permissions
  triple="$(resolve_mode)" || return 1
  read -r sandbox approval permissions <<<"$triple"
  _upsert_toml_toplevel "$config" sandbox_mode "$sandbox"
  _upsert_toml_toplevel "$config" approval_policy "$approval"
  if [[ "$permissions" == "none" ]]; then
    _remove_toml_toplevel "$config" default_permissions
    log_warn "permissions = none — managed permissions disabled; managed filesystem/network rules no longer apply (project: $(basename "$ICODEX_HOME_DIR"))"
  else
    _upsert_toml_toplevel "$config" default_permissions "$permissions"
    ensure_git_writable "$config" "$permissions"
  fi
  if [[ "$sandbox" == "danger-full-access" ]]; then
    log_warn "sandbox = danger-full-access — full filesystem access enabled (project: $(basename "$ICODEX_HOME_DIR"))"
  fi
  return 0
}
