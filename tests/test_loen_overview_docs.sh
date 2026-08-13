#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

overview="$ROOT/docs/superpowers/specs/2026-07-02-00-loen-overview-design.md"
readme="$ROOT/plugins/loen/README.md"
readme_ru="$ROOT/plugins/loen/README.ru.md"
architecture="$ROOT/plugins/loen/docs/architecture.md"
loop_start="$ROOT/plugins/loen/skills/loop-start/SKILL.md"

assert_exit "overview spec exists" 0 test -f "$overview"
if [[ ! -f "$overview" ]]; then
  finish; exit $?
fi

overview_body="$(cat "$overview")"
flat_overview_body="$(tr '\n' ' ' < "$overview" | sed 's/[[:space:]][[:space:]]*/ /g')"

layer_topics=(
  "01-loen-plugin-core"
  "02-loen-runtime-artifacts"
  "03-loen-enforcement-hooks"
  "04-loen-agent-isolation"
  "05-loen-icodex-integration"
  "06-loen-automation-governance"
)

layer_specs=(
  "docs/superpowers/specs/2026-07-02-01-loen-plugin-core-design.md"
  "docs/superpowers/specs/2026-07-02-02-loen-runtime-artifacts-design.md"
  "docs/superpowers/specs/2026-07-02-03-loen-enforcement-hooks-design.md"
  "docs/superpowers/specs/2026-07-02-04-loen-agent-isolation-design.md"
  "docs/superpowers/specs/2026-07-02-05-loen-icodex-integration-design.md"
  "docs/superpowers/specs/2026-07-02-06-loen-automation-governance-design.md"
)

for i in "${!layer_topics[@]}"; do
  topic="${layer_topics[$i]}"
  rel="${layer_specs[$i]}"
  base="$(basename "$rel")"
  expected_link='[`'"$topic"'`]('"$base"')'

  assert_exit "layer spec exists: $topic" 0 test -f "$ROOT/$rel"
  assert_contains "overview links $topic" "$overview_body" "$expected_link"
done

assert_contains "overview source boundary" "$overview_body" "plugins/loen/"
assert_contains "overview cache boundary" "$overview_body" ".codex-isolated/plugins/cache/<marketplace>/loen/<version>/"
assert_contains "overview task artifact boundary" "$overview_body" "docs/loen/<topic>/"
for doc in "$readme" "$readme_ru" "$architecture" "$loop_start"; do
  assert_eq "LoEn docs have no repository task index: $(basename "$doc")" "0" "$(grep -cF 'docs/TODO.md' "$doc" || true)"
done
readme_flat="$(tr '\n' ' ' < "$readme" | sed 's/[[:space:]][[:space:]]*/ /g')"
assert_contains "README loop artifacts authoritative" "$readme_flat" "Loop artifacts remain authoritative for loop execution"
assert_contains "README parent task-page mirror" "$(cat "$readme")" "mirrors material lifecycle evidence"
assert_contains "README hooks MCP-free" "$(cat "$readme")" "Hooks remain MCP-free"
assert_contains "loop-start resolves shared page" "$(cat "$loop_start")" 'resolve or create the shared `reference/tasks/<topic>` page before the loop starts'
assert_contains "architecture parent task-page mirror" "$(cat "$architecture")" 'parent resolves or creates `reference/tasks/<topic>`'

assert_contains "independent from IDD chain" "$overview_body" "LoEn is not an extension of the current IDD->SDD chain"
assert_contains "independent from Superpowers" "$flat_overview_body" "does not depend on the Superpowers plugin"
assert_contains "legacy iwiki excluded" "$overview_body" 'Do not depend on `lib/plugin/iwiki.sh`'

assert_contains "runtime behavior section present" "$overview_body" "## Runtime Behavior Ownership"

runtime_section="$(awk '
  /^## Runtime Behavior Ownership$/ { in_section = 1; next }
  /^## / && in_section { in_section = 0 }
  in_section { print }
' "$overview")"

assert_runtime_owner() {
  local desc="$1" key="$2" owner="$3" line
  line="$(grep -F "$key" <<<"$runtime_section" || true)"
  assert_contains "$desc key" "$line" "$key"
  assert_contains "$desc owner" "$line" "$owner"
}

assert_runtime_owner "runtime behavior owner: plugin core" "Editable plugin source" '[`01-loen-plugin-core`](2026-07-02-01-loen-plugin-core-design.md)'
assert_runtime_owner "runtime behavior owner: runtime artifacts" "Topic artifact contract" '[`02-loen-runtime-artifacts`](2026-07-02-02-loen-runtime-artifacts-design.md)'
assert_runtime_owner "runtime behavior owner: enforcement hooks" "Blocking/advisory loop gates" '[`03-loen-enforcement-hooks`](2026-07-02-03-loen-enforcement-hooks-design.md)'
assert_runtime_owner "runtime behavior owner: agent isolation" "Planner/worker/verifier/reviewer/researcher role separation" '[`04-loen-agent-isolation`](2026-07-02-04-loen-agent-isolation-design.md)'
assert_runtime_owner "runtime behavior owner: icodex integration" "Vendoring, launch-time marketplace wiring" '[`05-loen-icodex-integration`](2026-07-02-05-loen-icodex-integration-design.md)'
assert_runtime_owner "runtime behavior owner: automation governance" "Scheduled/background loop governance" '[`06-loen-automation-governance`](2026-07-02-06-loen-automation-governance-design.md)'

finish
