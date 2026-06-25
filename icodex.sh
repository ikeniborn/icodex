#!/usr/bin/env bash
set -euo pipefail

ICODEX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ICODEX_ROOT

for m in core/logging core/init core/validation command/args \
         binary/detect binary/lockfile binary/install \
         config/isolated proxy/proxy launcher/launch; do
  # shellcheck source=/dev/null
  source "$ICODEX_ROOT/lib/$m.sh"
done

main() {
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
  [[ -n "$ICODEX_SET_PROXY" ]] && proxy_save "$ICODEX_CONFIG" "$ICODEX_SET_PROXY"

  case "$ICODEX_CMD" in
    install) setup_codex_home; install_ensure;          exit $? ;;
    update)  setup_codex_home; install_ensure --update; exit $? ;;
  esac

  # default: run
  setup_codex_home
  install_ensure || exit 1
  (( ICODEX_NO_PROXY )) || proxy_apply "$ICODEX_CONFIG"
  launch_codex ${ICODEX_PASSTHROUGH[@]+"${ICODEX_PASSTHROUGH[@]}"}
}

main "$@"
