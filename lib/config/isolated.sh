#!/usr/bin/env bash
# Redirect all codex state into the project via CODEX_HOME.
setup_codex_home() {
  mkdir -p "$ICODEX_HOME_DIR/bin"
  export CODEX_HOME="$ICODEX_HOME_DIR"
}
