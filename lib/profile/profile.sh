#!/usr/bin/env bash
# Dispatch explicit profile-routed work through the Python App Server runner.

run_profile_task() {
  python3 "$ICODEX_ROOT/lib/profile/runner.py" run-task --target-root "$ICODEX_PROJECT_ROOT" --codex-home "$CODEX_HOME" --shared-root "$ICODEX_SHARED_DIR" --binary "$ICODEX_BIN" --topic "$ICODEX_PROFILE_TOPIC" --task "$ICODEX_PROFILE_TASK"
}

run_profile_orchestrator() {
  python3 "$ICODEX_ROOT/lib/profile/runner.py" orchestrate --target-root "$ICODEX_PROJECT_ROOT" --codex-home "$CODEX_HOME" --shared-root "$ICODEX_SHARED_DIR" --binary "$ICODEX_BIN" --topic "$ICODEX_PROFILE_TOPIC"
}
