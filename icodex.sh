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
         config/isolated config/permissions config/sandbox config/env config/ca_trust proxy/proxy symlink/symlink \
         plugin/superpowers plugin/loen caveman/caveman idd/idd iwiki/iwiki \
         pii-proxy/detect pii-proxy/install pii-proxy/status launcher/launch; do
  # shellcheck source=/dev/null
  source "$ICODEX_ROOT/lib/$m.sh"
done

main() {
  # Precedence: built-in defaults < .codex_config (ICODEX_*) < CLI flags.
  load_config "$ICODEX_CONFIG"
  apply_api_key
  apply_iwiki_env
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
    check-pii-proxy)
      check_pii_proxy_status
      exit 0 ;;
  esac

  require_tools || exit 1
  # Repair curl's TLS trust on hosts whose OpenSSL can't decode GOST CA certs,
  # so both the installer's downloads and curl subprocesses inside codex work.
  ensure_ca_trust
  # --proxy overrides the persisted value and is saved for next time.
  if [[ -n "$ICODEX_SET_PROXY" ]]; then
    ICODEX_PROXY="$ICODEX_SET_PROXY"
    proxy_save "$ICODEX_CONFIG" "$ICODEX_PROXY"
  fi

  case "$ICODEX_CMD" in
    install) setup_shared_dirs; install_ensure          || exit 1; ensure_uv_dependency || exit 1; ensure_cli_tools || exit 1; install_symlink; ensure_path_entry; exit 0 ;;
    update)  setup_shared_dirs; install_ensure --update || exit 1; ensure_uv_dependency || exit 1; ensure_cli_tools || exit 1; update_pii_nlp_models || exit 1; install_symlink; ensure_path_entry; exit 0 ;;
    install-pii-proxy)
      setup_shared_dirs
      validate_pii_config || exit 1
      install_isolated_pii_proxy || exit 1
      exit 0 ;;
  esac

  # default: run
  setup_codex_home
  apply_mode || exit 1
  ensure_project_trust "$ICODEX_HOME_DIR/config.toml" "$ICODEX_PROJECT_ROOT"
  ensure_launcher_binary_permission
  ensure_superpowers_wiring
  ensure_loen_wiring
  ensure_caveman_wiring
  ensure_idd_wiring
  ensure_iwiki_wiring
  ensure_iwiki_binding
  install_ensure || exit 1
  ensure_uv_dependency || exit 1
  ensure_cli_tools || exit 1
  (( ICODEX_DISABLE_PROXY )) || proxy_ensure
  ICODEX_USE_PII_PROXY_RESOLVED=false
  if [[ "${ICODEX_USE_PII_PROXY:-false}" == "true" || "$ICODEX_USE_PII_PROXY_FLAG" == "1" ]]; then
    ICODEX_USE_PII_PROXY_RESOLVED=true
    validate_pii_config || exit 1
    detect_pii_proxy || { log_error "PII proxy not installed — run: ./icodex.sh --install-pii-proxy"; exit 1; }
  fi
  launch_codex_with_optional_pii ${ICODEX_PASSTHROUGH[@]+"${ICODEX_PASSTHROUGH[@]}"}
}

main "$@"
