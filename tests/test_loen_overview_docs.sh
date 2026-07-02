#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

overview="$ROOT/docs/superpowers/specs/2026-07-02-00-loen-overview-design.md"
todo="$ROOT/docs/TODO.md"

assert_exit "overview spec exists" 0 test -f "$overview"
assert_exit "TODO index exists" 0 test -f "$todo"

if [[ ! -f "$overview" || ! -f "$todo" ]]; then
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

todo_topics=(
  "00-loen-overview"
  "01-loen-plugin-core"
  "02-loen-runtime-artifacts"
  "03-loen-enforcement-hooks"
  "04-loen-agent-isolation"
  "05-loen-icodex-integration"
  "06-loen-automation-governance"
)

for topic in "${todo_topics[@]}"; do
  assert_eq "TODO one row: $topic" "1" "$(grep -cF "| $topic |" "$todo")"
done

assert_contains "overview source boundary" "$overview_body" "plugins/loen/"
assert_contains "overview cache boundary" "$overview_body" ".codex-isolated/plugins/cache/<marketplace>/loen/<version>/"
assert_contains "overview task artifact boundary" "$overview_body" "docs/loen/<topic>/"
assert_contains "overview global registry boundary" "$flat_overview_body" '`docs/TODO.md` remains the only global human-readable task index'

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
