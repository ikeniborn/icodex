#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/command/router.sh"

tmp="$(mktemp -d)"
ICODEX_SHARED_DIR="$tmp"
export ICODEX_FRAMEWORK_EDGE_TOKEN=test-token

cat > "$tmp/router.toml" <<'TOML'
[presets.framework-glm]
model = "ollama-glm-5-3-cloud"
model_provider = "framework_gpu"

[presets.framework-glm.providers.framework_gpu]
name = "Framework GPU API"
base_url = "https://homelab.ikeniborn.ru/v1"
env_key = "ICODEX_FRAMEWORK_EDGE_TOKEN"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false

[presets.minimal]
model = "gpt-6-astra"
TOML

# Preset listing: top-level presets only, no nested provider tables.
list="$(router_list_presets)"
assert_eq "presets listed" "framework-glm
minimal" "$list"

# Unknown preset: loud error, rc 1.
if router_apply_preset nope 2>/dev/null; then rc=0; else rc=1; fi
assert_eq "unknown preset rejected" "1" "$rc"

# Invalid preset name (path-like) rejected.
if router_apply_preset "../evil" 2>/dev/null; then rc=0; else rc=1; fi
assert_eq "invalid preset name rejected" "1" "$rc"

# Missing presets file: loud error, rc 1.
rm "$tmp/router.toml"
if router_apply_preset framework-glm 2>/dev/null; then rc=0; else rc=1; fi
assert_eq "missing presets file rejected" "1" "$rc"

# Full preset: model + provider + provider parameters as -c overrides.
cat > "$tmp/router.toml" <<'TOML'
[presets.framework-glm]
model = "ollama-glm-5-3-cloud"
model_provider = "framework_gpu"

[presets.framework-glm.providers.framework_gpu]
name = "Framework GPU API"
base_url = "https://homelab.ikeniborn.ru/v1"
env_key = "ICODEX_FRAMEWORK_EDGE_TOKEN"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false

[presets.minimal]
model = "gpt-6-astra"
TOML
router_apply_preset framework-glm >/dev/null || assert_eq "full preset applies" "0" "1"
overrides="$(printf '%s\n' "${ICODEX_ROUTER_OVERRIDES[@]}" | paste -sd' ' -)"
assert_contains "model override" "$overrides" 'model="ollama-glm-5-3-cloud"'
assert_contains "provider override" "$overrides" 'model_provider="framework_gpu"'
assert_contains "provider name override" "$overrides" 'model_providers.framework_gpu.name="Framework GPU API"'
assert_contains "provider base_url override" "$overrides" 'model_providers.framework_gpu.base_url="https://homelab.ikeniborn.ru/v1"'
assert_contains "provider env_key override" "$overrides" 'model_providers.framework_gpu.env_key="ICODEX_FRAMEWORK_EDGE_TOKEN"'
assert_contains "provider wire_api override" "$overrides" 'model_providers.framework_gpu.wire_api="responses"'
assert_contains "boolean passes as TOML literal" "$overrides" 'model_providers.framework_gpu.requires_openai_auth=false'
assert_eq "override count exact" "16" "${#ICODEX_ROUTER_OVERRIDES[@]}"

# Minimal preset: model only.
router_apply_preset minimal >/dev/null
assert_eq "minimal override count" "2" "${#ICODEX_ROUTER_OVERRIDES[@]}"
assert_contains "minimal model override" "$(printf '%s\n' "${ICODEX_ROUTER_OVERRIDES[@]}")" 'model="gpt-6-astra"'

# env_key present but the secret missing: loud failure.
unset ICODEX_FRAMEWORK_EDGE_TOKEN
if router_apply_preset framework-glm 2>/dev/null; then rc=0; else rc=1; fi
assert_eq "missing env secret rejected" "1" "$rc"
export ICODEX_FRAMEWORK_EDGE_TOKEN=test-token

# Preset without any env_key: no environment requirement.
cat > "$tmp/router.toml" <<'TOML'
[presets.no-env]
model = "m"
model_provider = "builtin"
TOML
router_apply_preset no-env >/dev/null
assert_eq "no-env preset applies" "0" "$?"

# Provider referenced but defined only in the effective config (not the preset):
# no inline table, no env check — parameters come from config.toml.
cat > "$tmp/router.toml" <<'TOML'
[presets.config-provider]
model = "m2"
model_provider = "framework_gpu"
TOML
router_apply_preset config-provider >/dev/null
assert_eq "config-defined provider applies" "0" "$?"

# Args parsing: --router sets the preset name; passthrough intact.
source "$ROOT/lib/command/args.sh"
reset_args() {
  ICODEX_CMD="run"
  ICODEX_DISABLE_PROXY=0
  ICODEX_SET_PROXY=""
  ICODEX_PASSTHROUGH=()
  ICODEX_FULL_ACCESS=0
  ICODEX_ROUTER_PRESET=""
}
reset_args; parse_args --router framework-glm -- exec "hi"
assert_eq "router preset captured" "framework-glm" "$ICODEX_ROUTER_PRESET"
assert_eq "router keeps run cmd" "run" "$ICODEX_CMD"
assert_eq "router passthrough" "exec hi" "${ICODEX_PASSTHROUGH[*]}"

reset_args
read -r -a argv <<<"--router"
if ( parse_args "${argv[@]}" ) 2>/dev/null; then rc=0; else rc=1; fi
assert_eq "router without preset rejected" "1" "$rc"

assert_contains "help documents --router" "$(print_help)" "--router"

cd /
rm -rf "$tmp"
finish