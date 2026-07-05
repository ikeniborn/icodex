#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

plugin_root="$ROOT/plugins/loen"
manifest="$plugin_root/.codex-plugin/plugin.json"
hooks_json="$plugin_root/hooks/hooks.json"
vendored_cache="$ROOT/.codex-isolated/plugins/cache/iclaude/loen/0.5.1"
vendored_codex_manifest="$vendored_cache/.codex-plugin/plugin.json"
runtime_cache="$ROOT/.codex-isolated/plugins/cache/icodex-local/loen/0.1.0"

expected_skills=(
  loop-start
  loop-plan
  loop-act
  loop-check
  loop-reflect
  loop-status
  loop-repair
  loop-research
  loop-review
  loop-governance
)

expected_hooks=(
  loop-gate.py
  scope-guard.py
  tool-guard.py
  permission-guard.py
  evidence-gate.py
  audit-writer.py
)

expected_agents=(
  loen-planner.toml
  loen-worker.toml
  loen-verifier.toml
  loen-reviewer.toml
  loen-researcher.toml
)

expected_templates=(
  loop.yaml
  1_goal.md
  2_context.md
  3_plan.md
  4_act.md
  5_check.md
  6_reflect.md
  7_result.md
  handoff.md
  audit.html
)

assert_exit "plugin root exists" 0 test -d "$plugin_root"
assert_exit "plugin manifest exists" 0 test -f "$manifest"
assert_exit "root README exists" 0 test -f "$plugin_root/README.md"
assert_exit "root Russian README exists" 0 test -f "$plugin_root/README.ru.md"
assert_exit "runtime cache README exists" 0 test -f "$runtime_cache/README.md"
assert_exit "runtime cache Russian README exists" 0 test -f "$runtime_cache/README.ru.md"

root_readme="$(cat "$plugin_root/README.md" 2>/dev/null || true)"
root_readme_ru="$(cat "$plugin_root/README.ru.md" 2>/dev/null || true)"
assert_contains "root README explains icodex enablement" "$root_readme" "ICODEX_LOEN_MODE"
assert_contains "root README explains vendoring" "$root_readme" "scripts/vendor-loen.sh"
assert_contains "root README explains loop artifacts" "$root_readme" "docs/loen/<topic>/"
assert_contains "root Russian README explains icodex enablement" "$root_readme_ru" "ICODEX_LOEN_MODE"
assert_contains "root Russian README explains vendoring" "$root_readme_ru" "scripts/vendor-loen.sh"
assert_contains "root Russian README explains loop artifacts" "$root_readme_ru" "docs/loen/<topic>/"
assert_contains "runtime cache includes governance template" "$(cat "$runtime_cache/assets/templates/loop.yaml" 2>/dev/null || true)" "governance:"
assert_contains "runtime cache includes automation helper" "$(cat "$runtime_cache/hooks/loen_artifacts.py" 2>/dev/null || true)" "append_automation_attempt"

if [[ -f "$manifest" ]]; then
  manifest_summary="$(python3 - "$manifest" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
print(data.get("name", ""))
print(data.get("version", ""))
print(data.get("skills", ""))
print(data.get("hooks", ""))
print(data.get("agents", ""))
print(data.get("assets", ""))
print(data.get("interface", {}).get("displayName", ""))
PY
)"
else
  manifest_summary=$'\n\n\n\n\n\n'
fi

assert_eq "manifest name" "loen" "$(sed -n '1p' <<<"$manifest_summary")"
assert_eq "manifest version" "0.1.0" "$(sed -n '2p' <<<"$manifest_summary")"
assert_eq "manifest skills path" "./skills/" "$(sed -n '3p' <<<"$manifest_summary")"
assert_eq "manifest hooks path" "./hooks/hooks.json" "$(sed -n '4p' <<<"$manifest_summary")"
assert_eq "manifest agents path" "./agents/" "$(sed -n '5p' <<<"$manifest_summary")"
assert_eq "manifest assets path" "./assets/" "$(sed -n '6p' <<<"$manifest_summary")"
assert_eq "manifest display name" "LoEn" "$(sed -n '7p' <<<"$manifest_summary")"

assert_exit "vendored LoEn cache exists" 0 test -d "$vendored_cache"
assert_exit "vendored LoEn cache has Codex manifest" 0 test -f "$vendored_codex_manifest"

if [[ -f "$vendored_codex_manifest" ]]; then
  vendored_manifest_summary="$(python3 - "$vendored_codex_manifest" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
print(data.get("name", ""))
print(data.get("version", ""))
print(data.get("skills", ""))
print(data.get("interface", {}).get("displayName", ""))
PY
)"
else
  vendored_manifest_summary=$'\n\n\n'
fi

assert_eq "vendored manifest name" "loen" "$(sed -n '1p' <<<"$vendored_manifest_summary")"
assert_eq "vendored manifest version" "0.5.1" "$(sed -n '2p' <<<"$vendored_manifest_summary")"
assert_eq "vendored manifest skills path" "./skills/" "$(sed -n '3p' <<<"$vendored_manifest_summary")"
assert_eq "vendored manifest display name" "LoEn" "$(sed -n '4p' <<<"$vendored_manifest_summary")"

skill_names=()
for skill in "${expected_skills[@]}"; do
  skill_md="$plugin_root/skills/$skill/SKILL.md"
  assert_exit "skill exists: $skill" 0 test -f "$skill_md"
  name="$(awk -F': *' '$1 == "name" { print $2; exit }' "$skill_md" 2>/dev/null || true)"
  desc="$(awk -F': *' '$1 == "description" { print $2; exit }' "$skill_md" 2>/dev/null || true)"
  skill_names+=("$name")
  assert_eq "skill name matches directory: $skill" "$skill" "$name"
  assert_contains "skill writes only LoEn artifacts: $skill" "$(cat "$skill_md" 2>/dev/null)" 'docs/loen/<topic>/'
  assert_contains "skill has description: $skill" "$desc" "LoEn"
done

unique_skill_count="$(printf '%s\n' "${skill_names[@]}" | sort | uniq | sed '/^$/d' | wc -l | tr -d ' ')"
assert_eq "skill names are unique" "${#expected_skills[@]}" "$unique_skill_count"

assert_exit "hooks registry exists" 0 test -f "$hooks_json"
if [[ -f "$hooks_json" ]]; then
  hook_scripts_from_json="$(python3 - "$hooks_json" <<'PY'
import json
import re
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
commands = []
for entries in data.get("hooks", {}).values():
    for entry in entries:
        for hook in entry.get("hooks", []):
            commands.append(hook.get("command", ""))

for command in commands:
    match = re.search(r"hooks/([A-Za-z0-9_-]+\.py)", command)
    if match:
        print(match.group(1))
PY
)"
else
  hook_scripts_from_json=""
fi

for hook in "${expected_hooks[@]}"; do
  assert_exit "hook script exists: $hook" 0 test -f "$plugin_root/hooks/$hook"
  assert_contains "hook registry references: $hook" "$hook_scripts_from_json" "$hook"
  assert_contains "hook script reads artifact root: $hook" "$(cat "$plugin_root/hooks/$hook" 2>/dev/null)" "LOEN_ARTIFACT_ROOT"
done

malformed_root="$(mktemp -d)"
mkdir -p "$malformed_root/bad-topic"
printf '\377' > "$malformed_root/bad-topic/loop.yaml"
for hook in "${expected_hooks[@]}"; do
  assert_exit "hook tolerates malformed artifact: $hook" 0 \
    env LOEN_TOPIC="bad-topic" LOEN_ARTIFACT_ROOT="$malformed_root" python3 "$plugin_root/hooks/$hook"
done
rm -rf "$malformed_root"

if [[ -f "$hooks_json" ]]; then
  unbacked_hook_count="$(python3 - "$hooks_json" "$plugin_root/hooks" <<'PY'
import json
import re
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
hook_dir = Path(sys.argv[2])
missing = []
for entries in data.get("hooks", {}).values():
    for entry in entries:
        for hook in entry.get("hooks", []):
            command = hook.get("command", "")
            match = re.search(r"hooks/([A-Za-z0-9_-]+\.py)", command)
            if match and not (hook_dir / match.group(1)).is_file():
                missing.append(match.group(1))
print(len(missing))
PY
)"
else
  unbacked_hook_count="1"
fi
assert_eq "every hook command has a script" "0" "$unbacked_hook_count"

for agent in "${expected_agents[@]}"; do
  agent_path="$plugin_root/agents/$agent"
  assert_exit "agent exists: $agent" 0 test -f "$agent_path"
  if [[ -f "$agent_path" ]]; then
    parse_status="$(python3 - "$agent_path" <<'PY'
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    tomllib = None

text = Path(sys.argv[1]).read_text(encoding="utf-8")
if tomllib is not None:
    data = tomllib.loads(text)
else:
    data = {}
    for lineno, raw_line in enumerate(text.splitlines(), 1):
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        if "=" not in line:
            raise SystemExit(f"syntax:{lineno}")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key.replace("_", "").replace("-", "").isalnum():
            raise SystemExit(f"syntax:{lineno}")
        if value in {"true", "false"}:
            data[key] = value == "true"
        elif value.startswith('"') and value.endswith('"'):
            data[key] = value[1:-1]
        elif value.startswith("[") and value.endswith("]"):
            data[key] = [item.strip().strip('"') for item in value[1:-1].split(",") if item.strip()]
        else:
            raise SystemExit(f"syntax:{lineno}")
required = ["name", "role", "summary", "read_only_default"]
missing = [key for key in required if key not in data]
print("OK" if not missing else "missing:" + ",".join(missing))
PY
)"
  else
    parse_status="missing"
  fi
  assert_eq "agent TOML parses: $agent" "OK" "$parse_status"
done

for template in "${expected_templates[@]}"; do
  assert_exit "template exists: $template" 0 test -f "$plugin_root/assets/templates/$template"
done

assert_exit "plugin README exists" 0 test -f "$plugin_root/docs/README.md"
assert_exit "plugin architecture doc exists" 0 test -f "$plugin_root/docs/architecture.md"

if [[ -d "$plugin_root" ]]; then
  forbidden_refs="$(find "$plugin_root" -type f ! -path "$plugin_root/docs/*" -print0 | xargs -0 grep -En 'IDD|SDD|Superpowers|docs/superpowers|fix-intent|check-chain|lib/plugin/iwiki\.sh' 2>/dev/null || true)"
else
  forbidden_refs="missing plugin root"
fi
assert_eq "plugin source has no current-chain references" "" "$forbidden_refs"

finish
