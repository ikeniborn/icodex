#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
cd "$ROOT"

CC=".codex-isolated/skills/check-chain/SKILL.md"
HR=".codex-isolated/skills/html-report/SKILL.md"
CR=".codex-isolated/skills/html-report/references/chain-report.md"

cc_text="$(cat "$CC")"
hr_text="$(cat "$HR")"
cr_text="$(cat "$CR")"

assert_contains "check-chain documents enriched payload" "$cc_text" "## Enriched chain report payload"
assert_contains "check-chain keeps existing six blocks" "$cc_text" "The existing six owned-tab blocks remain mandatory"
assert_contains "check-chain requires Russian HTML text" "$cc_text" "All HTML report user-facing text is Russian"
assert_contains "check-chain keeps markdown English" "$cc_text" "All markdown artifacts remain English"
assert_contains "check-chain documents HTML-first approval" "$cc_text" "The user approves the generated HTML report"
assert_contains "check-chain documents markdown feedback loop" "$cc_text" "feedback is fixed in markdown source artifacts"
assert_contains "check-chain prohibits invented report content" "$cc_text" "Do not invent requirements, dependencies, decisions, risks, or diagrams"
assert_contains "check-chain cached exit stays rich" "$cc_text" "Cached quick-exit runs must regenerate the same full enriched owned-tab payload"

for diagram in \
  "Outcome Chain" \
  "Constraint Matrix" \
  "Autonomy Map" \
  "Context Map" \
  "Requirement Coverage Map" \
  "Component Graph" \
  "Data Flow" \
  "Risk/Mitigation Map" \
  "Step DAG" \
  "Artifact Impact Map" \
  "Verification Map" \
  "Human Checkpoint Flow" \
  "Diff Reconciliation Graph" \
  "Outcome Evidence Map" \
  "Excess/Gap Map"
do
  assert_contains "check-chain mandatory diagram $diagram" "$cc_text" "$diagram"
done

assert_contains "html-report accepts enriched owned tab" "$hr_text" "chain mode accepts a fully enriched owned-tab payload from the caller"
assert_contains "html-report does not read chain sources" "$hr_text" "does not read intent, spec, plan, or result markdown sources in chain mode"
assert_contains "html-report allows inline svg" "$hr_text" "inline SVG"
assert_contains "html-report allows small inline js" "$hr_text" "small inline JavaScript"
assert_contains "html-report keeps self-contained report" "$hr_text" "no CDN"
assert_contains "html-report preserves non-owned tabs" "$hr_text" "preserve the non-owned tabs"

assert_contains "chain-report semantic blocks" "$cr_text" "Semantic owned-tab blocks"
assert_contains "chain-report mandatory visualizations" "$cr_text" "Mandatory rich visualizations"
assert_contains "chain-report html-first review" "$cr_text" "HTML-first review flow"
assert_contains "chain-report source fallback" "$cr_text" "source lacks enough structure"
assert_contains "chain-report marker contract preserved" "$cr_text" "Markers are the exact literal strings"

finish
