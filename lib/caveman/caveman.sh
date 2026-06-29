#!/usr/bin/env bash
# Wire caveman (token-compression) into the per-project Codex home at launch.
#
# Two idempotent actions, gated on ICODEX_CAVEMAN_MODE (lite|full|ultra; unset/off
# disables): (1) maintain a delimited caveman region in $CODEX_HOME/AGENTS.md;
# (2) register the caveman UserPromptSubmit hook by merging it into the home
# hooks.json (a real file when enabled, a symlink to the shared secret-guard file
# when disabled). Mirrors the launch-path, idempotent style of lib/plugin/superpowers.sh.

_CAVEMAN_REGION_START="<!-- icodex:caveman:start -->"
_CAVEMAN_REGION_END="<!-- icodex:caveman:end -->"

# Echo the active launch mode (lite|full|ultra), or empty when caveman is disabled.
_caveman_mode() {
  local m
  m="$(printf '%s' "${ICODEX_CAVEMAN_MODE:-}" | tr '[:upper:]' '[:lower:]')"
  case "$m" in
    lite|full|ultra) printf '%s\n' "$m" ;;
    *) printf '\n' ;;
  esac
}

# Echo the rendered caveman block (mode substituted) from the tracked template.
_caveman_render_block() { # <mode>
  local mode="$1" tpl="$ICODEX_SHARED_DIR/caveman/agents-block.md"
  [[ -f "$tpl" ]] || return 1
  sed "s/__CAVEMAN_MODE__/$mode/g" "$tpl"
}

# Insert/replace (or remove) the delimited caveman region in <file>. Idempotent.
_caveman_write_agents_region() { # <file> <block_or_empty>
  local file="$1" block="$2" tmp
  if [[ -z "$block" && ! -f "$file" ]]; then
    return 0  # nothing to remove and nothing to add
  fi
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    awk -v s="$_CAVEMAN_REGION_START" -v e="$_CAVEMAN_REGION_END" '
      $0 == s { skip=1; next }
      $0 == e { skip=0; next }
      !skip { print }
    ' "$file" > "$tmp"
  fi
  if [[ -n "$block" ]]; then
    printf '%s\n%s\n%s\n' "$_CAVEMAN_REGION_START" "$block" "$_CAVEMAN_REGION_END" >> "$tmp"
  fi
  if [[ ! -f "$file" ]] || ! cmp -s "$tmp" "$file"; then
    if [[ -s "$tmp" ]]; then
      cat "$tmp" > "$file"
    else
      rm -f "$file"
    fi
  fi
  rm -f "$tmp"
}

# Build the home hooks.json = shared hooks + caveman UserPromptSubmit entry. Idempotent.
_caveman_enable_hooks_json() {
  local shared="$ICODEX_SHARED_DIR/hooks.json" home="$ICODEX_HOME_DIR/hooks.json" tmp
  [[ -f "$shared" ]] || return 0
  tmp="$(mktemp)"
  python3 - "$shared" > "$tmp" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    cfg = json.load(fh)
hooks = cfg.setdefault("hooks", {})
ups = hooks.setdefault("UserPromptSubmit", [])
cmd = 'python3 "$CODEX_HOME/hooks/caveman-hook.py"'
present = any(h.get("command") == cmd
              for entry in ups for h in entry.get("hooks", []))
if not present:
    ups.append({"hooks": [{
        "type": "command",
        "command": cmd,
        "timeout": 10,
        "statusMessage": "caveman",
    }]})
json.dump(cfg, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
  if [[ -L "$home" || ! -f "$home" ]] || ! cmp -s "$tmp" "$home"; then
    rm -f "$home"
    cat "$tmp" > "$home"
  fi
  rm -f "$tmp"
}

# Restore the home hooks.json symlink to the shared file (caveman not registered).
_caveman_disable_hooks_json() {
  local shared="$ICODEX_SHARED_DIR/hooks.json" home="$ICODEX_HOME_DIR/hooks.json"
  [[ -L "$home" ]] && return 0
  rm -f "$home"
  ln -s "$shared" "$home"
}

# Orchestrate caveman wiring on the launch path.
ensure_caveman_wiring() {
  local agents="$ICODEX_HOME_DIR/AGENTS.md" mode block
  mode="$(_caveman_mode)"
  if [[ -z "$mode" ]]; then
    _caveman_write_agents_region "$agents" ""
    _caveman_disable_hooks_json
    return 0
  fi
  if ! block="$(_caveman_render_block "$mode")"; then
    log_warn "caveman template missing — skipping caveman wiring"
    return 0
  fi
  _caveman_write_agents_region "$agents" "$block"
  _caveman_enable_hooks_json
}
