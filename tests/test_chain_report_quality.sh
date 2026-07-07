#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
cd "$ROOT"

CC=".codex-isolated/skills/check-chain/SKILL.md"
HR=".codex-isolated/skills/html-report/SKILL.md"
CR=".codex-isolated/skills/html-report/references/chain-report.md"
REPORT="docs/superpowers/reports/check-chain-report-quality-results.html"

cc_text="$(cat "$CC")"
hr_text="$(cat "$HR")"
cr_text="$(cat "$CR")"
report_text="$(cat "$REPORT")"

assert_contains "check-chain documents enriched payload" "$cc_text" "## Enriched chain report payload"
assert_contains "check-chain keeps existing six blocks" "$cc_text" "The existing six owned-tab blocks remain mandatory"
assert_contains "check-chain requires Russian HTML text" "$cc_text" "All HTML report user-facing text is Russian"
assert_contains "check-chain allows only technical English exceptions" "$cc_text" "English is allowed only for technical terms"
assert_contains "check-chain translates visible diagram titles" "$cc_text" "visible diagram titles in HTML"
assert_contains "check-chain maps Step DAG to Russian" "$cc_text" "Step DAG -> Граф шагов"
assert_contains "check-chain maps result evidence to Russian" "$cc_text" "Outcome Evidence Map -> Карта свидетельств результатов"
assert_contains "check-chain keeps markdown English" "$cc_text" "All markdown artifacts remain English"
assert_contains "check-chain documents HTML-first approval" "$cc_text" "The user approves the generated HTML report"
assert_contains "check-chain requires OK before approval" "$cc_text" "Human approval is requested only after this stage returns OK"
assert_contains "check-chain result includes code review" "$cc_text" "Result includes a focused code review"
assert_contains "check-chain result fixes bugs before OK" "$cc_text" 'Fix every confirmed bug before writing `result_check.verdict: OK`'
assert_contains "check-chain result requires docs evidence" "$cc_text" "Documentation evidence is required for behavior, architecture, or user-facing changes"
assert_contains "check-chain all stages check wiki docs" "$cc_text" "Every stage must check whether its verdict changes documented behavior"
assert_contains "check-chain result propagates decision changes" "$cc_text" "If implementation changed an approved decision"
assert_contains "check-chain result blocks stale chain docs" "$cc_text" 'Do not write `result_check.verdict: OK` while intent, spec, plan, repository docs, or iwiki describe stale decisions'
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
  "Excess/Gap Map" \
  "Code Review Findings Map" \
  "Documentation Evidence Map" \
  "Decision Propagation Map"
do
  assert_contains "check-chain mandatory diagram $diagram" "$cc_text" "$diagram"
done

assert_contains "html-report accepts enriched owned tab" "$hr_text" "chain mode accepts a fully enriched owned-tab payload from the caller"
assert_contains "html-report does not read chain sources" "$hr_text" "does not read intent, spec, plan, or result markdown sources in chain mode"
assert_contains "html-report allows inline svg" "$hr_text" "inline SVG"
assert_contains "html-report allows small inline js" "$hr_text" "small inline JavaScript"
assert_contains "html-report keeps self-contained report" "$hr_text" "no CDN"
assert_contains "html-report preserves non-owned tabs" "$hr_text" "preserve the non-owned tabs"
assert_contains "html-report prohibits English UI copy" "$hr_text" "English visible UI copy is not allowed"

assert_contains "chain-report semantic blocks" "$cr_text" "Semantic owned-tab blocks"
assert_contains "chain-report mandatory visualizations" "$cr_text" "Mandatory rich visualizations"
assert_contains "chain-report html-first review" "$cr_text" "HTML-first review flow"
assert_contains "chain-report technical English exception only" "$cr_text" "English is allowed only for technical terms"
assert_contains "chain-report translates visible diagram titles" "$cr_text" "titles in generated HTML must be Russian"
assert_contains "chain-report maps Step DAG to Russian" "$cr_text" "Step DAG -> Граф шагов"
assert_contains "chain-report maps result evidence to Russian" "$cr_text" "Outcome Evidence Map -> Карта свидетельств результатов"
assert_contains "chain-report Russian intent tab label" "$cr_text" '<label for="tab-intent">Интент</label>'
assert_contains "chain-report Russian spec tab label" "$cr_text" '<label for="tab-spec">Спека</label>'
assert_contains "chain-report Russian plan tab label" "$cr_text" '<label for="tab-plan">План</label>'
assert_contains "chain-report Russian result tab label" "$cr_text" '<label for="tab-result">Результат</label>'
assert_contains "chain-report source fallback" "$cr_text" "source lacks enough structure"
assert_contains "chain-report marker contract preserved" "$cr_text" "Markers are the exact literal strings"

banned_report_labels=(
  "Step DAG"
  "Artifact Impact Map"
  "Verification Map"
  "Human Checkpoint Flow"
  "Diff Reconciliation Graph"
  "Outcome Evidence Map"
  "Excess/Gap Map"
  "Outcome Chain"
  "Constraint Matrix"
  "Autonomy Map"
  "Context Map"
  "Requirement Coverage Map"
  "Component Graph"
  "Data Flow"
  "Risk/Mitigation Map"
  "Code Review Findings Map"
  "Documentation Evidence Map"
  "Decision Propagation Map"
  "Markdown source of truth"
  "review surface"
  "Executive overview"
  "Approval lens"
  "Source anchors"
  "Findings"
  "Summary"
)

for label in "${banned_report_labels[@]}"; do
  count="$(grep -oF -- "$label" <<<"$report_text" | wc -l | tr -d ' ')"
  assert_eq "generated chain report has no visible English label: $label" "0" "$count"
done

finish
