#!/usr/bin/env bash
# Persistent user configuration. The config file (.codex_config) holds plain
# KEY=value lines; only ICODEX_-prefixed keys are honored. Values are parsed and
# exported — the file is NOT sourced, so it can never execute arbitrary code.

# load_config <file> — export every ICODEX_<NAME>=value line from the file.
# Comments, blank lines, and non-ICODEX keys are ignored. Missing file: no-op.
load_config() { # <config_file>
  local file="$1" line key val
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"                       # tolerate CRLF
    [[ "$line" =~ ^ICODEX_[A-Z0-9_]+= ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    export "$key=$val"
  done < "$file"
}

# _config_set <file> <key> <value> — upsert KEY=value, preserving other lines.
# The file is (re)written with 0600 permissions from the start (creds-safe).
_config_set() { # <config_file> <key> <value>
  local file="$1" key="$2" val="$3" tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
  fi
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  ( umask 177; cat "$tmp" > "$file" )
  chmod 600 "$file"
  rm -f "$tmp"
}
