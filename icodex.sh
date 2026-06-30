#!/usr/bin/env bash
set -euo pipefail

# Resolve the real script path even when invoked through a symlink
# (e.g. ~/.local/bin/icodex), so modules are sourced from the repo, not the link dir.
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
ICODEX_ROOT="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
export ICODEX_ROOT

for m in core/logging core/init core/validation command/args \
         binary/detect binary/lockfile binary/install \
         config/isolated config/permissions config/sandbox config/env proxy/proxy symlink/symlink \
         plugin/superpowers caveman/caveman idd/idd launcher/launch; do
  # shellcheck source=/dev/null
  source "$ICODEX_ROOT/lib/$m.sh"
done

main() {
  # Precedence: built-in defaults < .codex_config (ICODEX_*) < CLI flags.
  load_config "$ICODEX_CONFIG"
  apply_api_key
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
    install) setup_shared_dirs; install_ensure          || exit 1; ensure_uv_dependency || exit 1; install_symlink; ensure_path_entry; exit 0 ;;
    update)  setup_shared_dirs; install_ensure --update || exit 1; ensure_uv_dependency || exit 1; install_symlink; ensure_path_entry; exit 0 ;;
  esac

  # default: run
  setup_codex_home
  apply_mode || exit 1
  ensure_project_trust "$ICODEX_HOME_DIR/config.toml" "$ICODEX_PROJECT_ROOT"
  ensure_launcher_binary_permission
  ensure_superpowers_wiring
  ensure_caveman_wiring
  ensure_idd_wiring
  install_ensure || exit 1
  ensure_uv_dependency || exit 1
  (( ICODEX_DISABLE_PROXY )) || proxy_ensure
  launch_codex ${ICODEX_PASSTHROUGH[@]+"${ICODEX_PASSTHROUGH[@]}"}
}

main "$@"
