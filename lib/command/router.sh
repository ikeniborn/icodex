#!/usr/bin/env bash
# One-run model provider + model routing via --router <preset>.
#
# Presets live in the shared store as `router.toml`, a plain TOML file whose
# top-level tables each name one preset:
#
#   [presets.framework-glm]
#   model = "ollama-glm-5-3-cloud"
#   model_provider = "framework_gpu"
#
# A preset may also carry provider parameters, written as dotted `model_providers.<id>.<key>`
# keys inside the preset table:
#
#   [presets.framework-glm.providers.framework_gpu]
#   base_url = "https://homelab.example/v1"
#   env_key = "ICODEX_FRAMEWORK_EDGE_TOKEN"
#   wire_api = "responses"
#
# At launch the selected preset is applied as one-run `-c` config overrides:
# nothing is written into the home config.toml, so a routed run never drifts
# the home. The provider table must already exist in the effective config
# (template-managed region or home copy) unless the preset defines it via
# `providers`. `env_key` names an environment variable that must be set at
# launch; its value is never stored anywhere by icodex.

# Resolve the router presets file: shared store router.toml.
_router_presets_file() {
  printf '%s\n' "$ICODEX_SHARED_DIR/router.toml"
}

# Echo the names of all presets defined in the presets file, one per line.
# Empty output (rc 0) when the file is absent or defines no presets.
router_list_presets() {
  local file
  file="$(_router_presets_file)"
  [[ -f "$file" ]] || return 0
  awk '
    /^[[:space:]]*\[presets\./ {
      line = $0
      sub(/^[[:space:]]*\[presets\./, "", line)
      sub(/\][[:space:]]*$/, "", line)
      gsub(/"/, "", line)
      # nested provider tables are part of their preset, not presets themselves
      if (line != "" && line !~ /\.providers\./) print line
    }
  ' "$file"
}

# Echo the value of `<key>` inside `[presets.<name>]` (or inside its nested
# `[presets.<name>.providers.<id>]` when <key> is dotted provider syntax);
# rc 1 when the preset or the key is absent. Key matching is a regex
# (`^key[[:space:]]*=`), not index(): codex TOML allows spaces around `=`,
# and index() would miss `model = "x"` when searching for `model=`.
_router_preset_value() { # <name> <key>
  local file="$(_router_presets_file)" name="$1" key="$2" section
  [[ -f "$file" ]] || return 1
  # The requested key is either a plain preset key (model) or a dotted
  # provider key (model_providers.id.key) mapped onto the nested
  # [presets.<name>.providers.<id>] table.
  if [[ "$key" == model_providers.* ]]; then
    local pid="${key#model_providers.}"; pid="${pid%.*}"
    section="presets.$name.providers.$pid"
    key="${key##*.}"
  else
    section="presets.$name"
  fi
  awk -v section="$section" -v key="$key" '
    /^[[:space:]]*\[/ { in_section = ($0 ~ ("^[[:space:]]*\\[" section "\\]")) }
    in_section {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      if (line ~ ("^" key "[[:space:]]*=")) {
        val = line
        sub(/^[^=]*=[[:space:]]*/, "", val)
        gsub(/^"|"$/, "", val)
        print val
        found = 1
        exit
      }
    }
    END { exit !found }
  ' "$file"
}

# Validate one preset name against [A-Za-z0-9._-]+ (TOML bare-key safe).
_router_preset_name_valid() { # <name>
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

# Build the -c override argument list for one preset. Fails with log_error
# and rc 1 when the preset is unknown, the file is missing, or the preset
# declares a provider whose env_key variable is unset in the environment.
# Sets the array variable ICODEX_ROUTER_OVERRIDES in the caller's scope.
router_apply_preset() { # <name>
  local name="$1" file model provider key val env_keys
  ICODEX_ROUTER_OVERRIDES=()
  if ! _router_preset_name_valid "$name"; then
    log_error "invalid --router preset '$name'"
    return 1
  fi
  file="$(_router_presets_file)"
  if [[ ! -f "$file" ]]; then
    log_error "router presets file missing: $file (see router.toml.example)"
    return 1
  fi
  if ! router_list_presets | grep -qx -- "$name"; then
    log_error "unknown --router preset '$name' (defined: $(router_list_presets | paste -sd', ' -))"
    return 1
  fi

  model="$(_router_preset_value "$name" model || true)"
  provider="$(_router_preset_value "$name" model_provider || true)"

  if [[ -n "$model" ]]; then
    ICODEX_ROUTER_OVERRIDES+=("-c" "model=\"$model\"")
  fi
  if [[ -n "$provider" ]]; then
    ICODEX_ROUTER_OVERRIDES+=("-c" "model_provider=\"$provider\"")
  fi

  # Provider parameters declared in the preset: emit one -c override each.
  # The set of provider ids is discovered from the file itself.
  local pid key val
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    for key in name base_url env_key wire_api requires_openai_auth supports_websockets query_params http_headers env_http_headers; do
      val="$(_router_preset_value "$name" "model_providers.$pid.$key" || true)"
      [[ -n "$val" ]] || continue
      case "$val" in
        true|false) quoted="$val" ;;   # booleans pass as TOML literals
        *) quoted="\"$val\"" ;;
      esac
      ICODEX_ROUTER_OVERRIDES+=("-c" "model_providers.$pid.$key=$quoted")
    done
  done < <(awk -v preset="$name" '
    /^[[:space:]]*\[presets\./ {
      line = $0
      sub(/^[[:space:]]*\[presets\./, "", line)
      sub(/\][[:space:]]*$/, "", line)
      prefix = preset ".providers."
      if (index(line, prefix) == 1) print substr(line, length(prefix) + 1)
    }
  ' "$file")

  # env_key hygiene: every provider touched by this run must have its
  # secret present in the environment; a missing key fails loudly.
  local -a touched=()
  [[ -n "$provider" ]] && touched+=("$provider")
  for pid in $(printf '%s\n' "${ICODEX_ROUTER_OVERRIDES[@]}" | sed -n 's/^model_providers\.\([A-Za-z0-9._-]*\)\..*/\1/p' | sort -u); do
    [[ -n "$pid" ]] && touched+=("$pid")
  done
  local t ek
  for t in "${touched[@]}"; do
    ek="$(_router_preset_value "$name" "model_providers.$t.env_key" || true)"
    [[ -n "$ek" ]] || continue
    if [[ -z "${!ek:-}" ]]; then
      log_error "--router preset '$name': provider '$t' needs $ek set in the environment"
      return 1
    fi
  done

  log_info "router: preset '$name' applied for this run${model:+ (model=$model)}${provider:+ (provider=$provider)}"
}

# Print the effective presets file location and each defined preset name.
router_status() {
  local file name
  file="$(_router_presets_file)"
  if [[ ! -f "$file" ]]; then
    log_info "router: no presets file at $file"
    return 0
  fi
  log_info "router presets: $file"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    log_info "  preset '$name': model=$(_router_preset_value "$name" model || echo -) provider=$(_router_preset_value "$name" model_provider || echo -)"
  done < <(router_list_presets)
}