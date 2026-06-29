#!/usr/bin/env bash
# Launch-time permission wiring for paths icodex itself needs inside Codex's
# sandbox, even when the target workspace is a different repository.

_toml_basic_string_escape() { # <value>
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

_ensure_filesystem_permission_entry() { # <config> <path> <access>
  local config="$1" path="$2" access="$3" escaped quoted_key tmp
  escaped="$(_toml_basic_string_escape "$path")"
  quoted_key="\"$escaped\""
  tmp="$(mktemp)"
  TOML_KEY="$quoted_key" awk -v access="$access" '
    BEGIN {
      key = ENVIRON["TOML_KEY"]
      section = "[permissions.dev-safe.filesystem]"
      line = key " = \"" access "\""
    }
    function emit_missing() {
      if (insec && !done) {
        print line
        done = 1
      }
    }
    /^\[/ {
      emit_missing()
      insec = ($0 == section)
      if (insec) found_section = 1
    }
    insec {
      trimmed = $0
      sub(/^[[:space:]]*/, "", trimmed)
      if (index(trimmed, key) == 1) {
        rest = substr(trimmed, length(key) + 1)
        if (rest ~ /^[[:space:]]*=/) {
          if (!done) {
            print line
            done = 1
          }
          next
        }
      }
    }
    { print }
    END {
      emit_missing()
      if (!found_section) {
        print ""
        print section
        print line
      }
    }
  ' "$config" > "$tmp"
  cmp -s "$tmp" "$config" || cat "$tmp" > "$config"
  rm -f "$tmp"
}

ensure_launcher_binary_permission() {
  local config="$ICODEX_HOME_DIR/config.toml"
  if [[ ! -f "$config" ]]; then
    log_error "missing $config — cannot configure launcher binary sandbox access"
    return 0
  fi
  _ensure_filesystem_permission_entry "$config" "$ICODEX_BIN" "read"
}

# Idempotently mark the launched project as trusted in the per-project config.
# Governs project trust only; it does not change approval_policy.
ensure_project_trust() { # <config> <project_root>
  local config="$1" root="$2" escaped
  [[ -f "$config" ]] || return 0
  escaped="$(_toml_basic_string_escape "$root")"
  grep -qF "[projects.\"$escaped\"]" "$config" && return 0
  printf '\n[projects."%s"]\ntrust_level = "trusted"\n' "$escaped" >> "$config"
}
