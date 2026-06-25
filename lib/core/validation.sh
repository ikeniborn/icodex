#!/usr/bin/env bash
# Preconditions: required external tools must be on PATH.
_has() { command -v "$1" >/dev/null 2>&1; }

require_tools() {
  local missing=()
  _has curl || missing+=("curl")
  _has tar  || missing+=("tar")
  if ! _has sha256sum && ! _has shasum; then
    missing+=("sha256sum|shasum")
  fi
  if (( ${#missing[@]} )); then
    log_error "missing required tools: ${missing[*]}"
    return 1
  fi
  return 0
}
