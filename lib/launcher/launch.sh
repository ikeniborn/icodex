#!/usr/bin/env bash
# Final transparent exec of the isolated codex binary.
launch_codex() { # <args...>
  if [[ ! -x "$ICODEX_BIN" ]]; then
    log_error "codex binary missing — run: ./icodex.sh --install"
    return 1
  fi
  exec "$ICODEX_BIN" "$@"
}
