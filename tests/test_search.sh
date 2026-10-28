#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/search/search.sh"
log_error() { printf '%s\n' "$*" >&2; }
for mode in inherit native disabled; do
  ICODEX_SEARCH_MODE=$mode
  search_prepare_launch false ''
done
ICODEX_SEARCH_MODE=bogus
if search_prepare_launch false ''; then exit 1; fi
ICODEX_SEARCH_MODE=native
ICODEX_ROUTER_SEARCH_MODE=disabled
search_prepare_launch true ''
[[ ${ICODEX_SEARCH_ARGS[1]} == 'web_search="disabled"' ]]
search_prepare_launch false ''
[[ ${ICODEX_SEARCH_ARGS[1]} == 'web_search="live"' ]]
if search_prepare_launch false '' --search; then exit 1; fi
printf 'search tests passed\n'
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
source "$ROOT/lib/command/router.sh"
ICODEX_SHARED_DIR="$fixture"
printf '[presets.test]\nsearch_mode = "inherit"\n' > "$fixture/router.toml"
search_prepare_launch true test --search
[[ ${#ICODEX_SEARCH_ARGS[@]} == 0 ]]
printf '#!/bin/sh\nexit 0\n' > "$fixture/search command"
chmod +x "$fixture/search command"
ICODEX_SEARCH_MCP_COMMAND="$fixture/search command"
ICODEX_SEARCH_API_URL=https://search.example/v1/websearch
ICODEX_SEARCH_API_ENV_KEY=TEST_SEARCH_TOKEN
TEST_SEARCH_TOKEN=synthetic-secret
for routed in false true; do
  for mode in inherit native framework disabled; do
    ICODEX_SEARCH_MODE=$mode
    ICODEX_ROUTER_SEARCH_MODE=$mode
    search_prepare_launch "$routed" ''
    [[ "${ICODEX_SEARCH_ARGS[*]-}" != *synthetic-secret* ]]
    if [[ $mode == framework ]]; then
      [[ $FRAMEWORK_WEBSEARCH_TOKEN == synthetic-secret ]]
      [[ "${ICODEX_SEARCH_ARGS[*]}" == *'search command'* ]]
    fi
  done
done
ICODEX_SEARCH_MODE=inherit
search_prepare_launch false ''
[[ ${FRAMEWORK_WEBSEARCH_TOKEN+x} != x ]]
ICODEX_SEARCH_MODE=disabled
for conflict in --search --profile=test web_search=live; do
  if search_prepare_launch false '' "$conflict"; then exit 1; fi
done
ICODEX_HOME_DIR="$fixture/home"
mkdir -p "$ICODEX_HOME_DIR"
for definition in '[mcp_servers]\nframework-search = { command = "x" }' '[profiles.test.mcp_servers."framework-search"]\ncommand = "x"' 'mcp_servers = { "framework-search" = { command = "x" } }'; do
  printf '%b\n' "$definition" > "$ICODEX_HOME_DIR/config.toml"
  if search_prepare_launch false ''; then echo 'missed TOML registration'; exit 1; fi
done
printf '# framework-search is reserved\n[mcp_servers.other]\ncommand="x"\n' > "$ICODEX_HOME_DIR/config.toml"
search_prepare_launch false ''
source "$ROOT/lib/launcher/launch.sh"
source "$ROOT/lib/telemetry/telemetry.sh"
source "$ROOT/lib/telemetry/otel.sh"
source "$ROOT/lib/telemetry/langfuse.sh"
cat > "$fixture/record" <<'RECORDER'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$RECORD_ARGS"
[[ "$FRAMEWORK_WEBSEARCH_TOKEN" == synthetic-secret ]]
[[ "$FRAMEWORK_WEBSEARCH_URL" == https://search.example/v1/websearch ]]
RECORDER
chmod +x "$fixture/record"
ICODEX_BIN="$fixture/record"
export RECORD_ARGS="$fixture/args"
before=$(sha256sum "$ICODEX_HOME_DIR/config.toml")
ICODEX_SEARCH_MODE=framework
search_prepare_launch false ''
( launch_codex_with_optional_pii "${ICODEX_SEARCH_ARGS[@]}" 'space argument' )
! grep -q synthetic-secret "$RECORD_ARGS"
grep -qx 'space argument' "$RECORD_ARGS"
ICODEX_TELEMETRY=off
( launch_codex_wrapped "${ICODEX_SEARCH_ARGS[@]}" 'wrapped argument' )
! grep -q synthetic-secret "$RECORD_ARGS"
grep -qx 'wrapped argument' "$RECORD_ARGS"
[[ "$before" == "$(sha256sum "$ICODEX_HOME_DIR/config.toml")" ]]
# Additional endpoint/path boundary checks use the resolved framework fixture.

if search_prepare_launch false '' -c 'mcp_servers.framework-search.command="x"'; then exit 1; fi
ICODEX_SEARCH_MODE=framework
for bad in http://search.example/v1/websearch https://user:pass@search.example/v1/websearch https://search.example/wrong; do
  ICODEX_SEARCH_API_URL="$bad"
  if search_prepare_launch false ''; then exit 1; fi
done
ICODEX_SEARCH_API_URL=https://search.example/v1/websearch
search_prepare_launch false '' 'explain framework-search usage'
ICODEX_SEARCH_MODE=disabled
search_prepare_launch false '' -c 'features.unrelated_feature=true'
