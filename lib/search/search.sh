#!/usr/bin/env bash
# Prepare session-only search overrides. Never persist credentials.
search_prepare_launch() {
  local routed="$1" preset="$2" mode value arg key command encoded
  shift 2
  ICODEX_SEARCH_ARGS=()
  if [[ "${ICODEX_SEARCH_ENV_ACTIVE:-false}" == true ]]; then
    if [[ "$ICODEX_SEARCH_OLD_URL_SET" == x ]]; then export FRAMEWORK_WEBSEARCH_URL="$ICODEX_SEARCH_OLD_URL"; else unset FRAMEWORK_WEBSEARCH_URL; fi
    if [[ "$ICODEX_SEARCH_OLD_TOKEN_SET" == x ]]; then export FRAMEWORK_WEBSEARCH_TOKEN="$ICODEX_SEARCH_OLD_TOKEN"; else unset FRAMEWORK_WEBSEARCH_TOKEN; fi
    ICODEX_SEARCH_ENV_ACTIVE=false
  fi
  mode="${ICODEX_SEARCH_MODE:-inherit}"
  if [[ "$routed" == true ]]; then
    mode="${ICODEX_ROUTER_SEARCH_MODE:-inherit}"
    if [[ -n "$preset" ]]; then
      if value="$(_router_preset_value "$preset" search_mode 2>/dev/null)"; then mode="$value"; fi
    fi
  fi
  case "$mode" in
    inherit) return 0 ;;
    native|framework|disabled) ;;
    *) log_error 'Invalid launcher search mode'; return 1 ;;
  esac
  for arg in "$@"; do
    case "$arg" in
      --search|-p|-p?*|--profile|--profile=*|web_search=*|web_search\ =*|-cweb_search*|-c*framework-search*|--config=web_search*|--config=*framework-search*)
        log_error 'Search arguments conflict with launcher search mode'; return 1 ;;
    esac
  done
  # Parse TOML before inspecting registrations; comments and alternate table forms are valid.
  if ! python3 - "${ICODEX_HOME_DIR:-}/config.toml" "$@" <<'PYCONFIG'
import pathlib, sys, tomllib

def check(node):
    if not isinstance(node, dict):
        return
    servers = node.get("mcp_servers", {})
    if isinstance(servers, dict) and "framework-search" in servers:
        raise ValueError
    for value in node.values():
        check(value)

try:
    path = pathlib.Path(sys.argv[1])
    config = tomllib.loads(path.read_text()) if path.is_file() else {}
    check(config)
    # Default profiles are also competing selectors.
    if config.get("profile"):
        raise ValueError
    args = iter(sys.argv[2:])
    for arg in args:
        if arg in ("-c", "--config"):
            override = next(args)
        elif arg.startswith("--config="):
            override = arg.split("=", 1)[1]
        elif arg.startswith("-c") and len(arg) > 2:
            override = arg[2:]
        else:
            continue
        parsed = tomllib.loads(override)
        check(parsed)
        if any(key in parsed for key in ("web_search", "profile", "profiles", "plugins", "features")):
            raise ValueError
except (ValueError, OSError, StopIteration):
    sys.exit(1)
PYCONFIG
  then
    log_error 'Search configuration conflicts with launcher search mode or cannot be validated'
    return 1
  fi
  value=disabled
  [[ "$mode" == native ]] && value=live
  ICODEX_SEARCH_ARGS=(-c "web_search=\"$value\"")
  [[ "$mode" == framework ]] || return 0
  command="${ICODEX_SEARCH_MCP_COMMAND:-}"
  key="${ICODEX_SEARCH_API_ENV_KEY:-}"
  if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || [[ -z "${!key:-}" ]] || [[ "$command" != /* ]] || [[ ! -x "$command" ]] || [[ -z "${ICODEX_SEARCH_API_URL:-}" ]]; then
    log_error 'Framework search requires executable, endpoint, and token variable'; return 1
  fi
  if ! python3 - "$ICODEX_SEARCH_API_URL" <<'PYURL'
import sys
from urllib.parse import urlsplit
try:
    url = urlsplit(sys.argv[1])
    port = url.port
    assert url.scheme == 'https' and url.hostname and not url.username and not url.password
    assert not url.query and not url.fragment and url.path == '/v1/websearch'
except (ValueError, AssertionError):
    sys.exit(1)
PYURL
  then
    log_error 'Framework search requires a valid HTTPS /v1/websearch endpoint'; return 1
  fi
  # JSON strings are valid TOML basic strings for executable paths.
  encoded="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$command")" || return 1
  ICODEX_SEARCH_ARGS+=(-c "mcp_servers.framework-search.command=$encoded" -c 'mcp_servers.framework-search.env_vars=["FRAMEWORK_WEBSEARCH_URL","FRAMEWORK_WEBSEARCH_TOKEN"]')
  ICODEX_SEARCH_OLD_URL_SET="${FRAMEWORK_WEBSEARCH_URL+x}"
  ICODEX_SEARCH_OLD_TOKEN_SET="${FRAMEWORK_WEBSEARCH_TOKEN+x}"
  ICODEX_SEARCH_OLD_URL="${FRAMEWORK_WEBSEARCH_URL:-}"
  ICODEX_SEARCH_OLD_TOKEN="${FRAMEWORK_WEBSEARCH_TOKEN:-}"
  ICODEX_SEARCH_ENV_ACTIVE=true
  export FRAMEWORK_WEBSEARCH_URL="$ICODEX_SEARCH_API_URL"
  export FRAMEWORK_WEBSEARCH_TOKEN="${!key}"
}
