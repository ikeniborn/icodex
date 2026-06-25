#!/usr/bin/env bash
set -euo pipefail

ICODEX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ICODEX_ROOT

for m in core/logging core/init core/validation command/args \
         binary/detect binary/lockfile binary/install \
         config/isolated config/env proxy/proxy launcher/launch; do
  # shellcheck source=/dev/null
  source "$ICODEX_ROOT/lib/$m.sh"
done

main() {
  # Precedence: built-in defaults < .codex_config (ICODEX_*) < CLI flags.
  load_config "$ICODEX_CONFIG"
  parse_args "$@"

  case "$ICODEX_CMD" in
    help)
      print_help; exit 0 ;;
    clear)
      proxy_clear "$ICODEX_CONFIG"; log_info "cleared $ICODEX_CONFIG"; exit 0 ;;
    version)
      printf 'icodex %s\n' "$(cat "$ICODEX_ROOT/VERSION" 2>/dev/null || echo dev)"
      if [[ -x "$ICODEX_BIN" ]]; then "$ICODEX_BIN" --version; else echo "codex: not installed"; fi
      exit 0 ;;
  esac

  require_tools || exit 1
  # --proxy overrides the persisted value and is saved for next time.
  if [[ -n "$ICODEX_SET_PROXY" ]]; then
    ICODEX_PROXY="$ICODEX_SET_PROXY"
    proxy_save "$ICODEX_CONFIG" "$ICODEX_PROXY"
  fi

  case "$ICODEX_CMD" in
    install) setup_codex_home; install_ensure;          exit $? ;;
    update)  setup_codex_home; install_ensure --update; exit $? ;;
  esac

  # default: run
  setup_codex_home
  install_ensure || exit 1
  (( ICODEX_NO_PROXY )) || proxy_apply
  launch_codex ${ICODEX_PASSTHROUGH[@]+"${ICODEX_PASSTHROUGH[@]}"}
}

main "$@"
