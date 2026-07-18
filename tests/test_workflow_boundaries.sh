#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

agents="$ROOT/.codex-isolated/AGENTS.md"
readme="$ROOT/README.md"
readme_ru="$ROOT/docs/README.ru.md"
loen_readme="$ROOT/plugins/loen/README.md"
loen_readme_ru="$ROOT/plugins/loen/README.ru.md"

assert_exit "global AGENTS policy exists" 0 test -f "$agents"
assert_exit "README exists" 0 test -f "$readme"
assert_exit "Russian README exists" 0 test -f "$readme_ru"
assert_exit "LoEn README exists" 0 test -f "$loen_readme"
assert_exit "LoEn Russian README exists" 0 test -f "$loen_readme_ru"

if [[ -f "$agents" ]]; then
  agents_body="$(cat "$agents")"
  flat_agents_body="$(tr '\n' ' ' < "$agents" | sed 's/[[:space:]][[:space:]]*/ /g')"
  assert_contains "Superpowers policy has LoEn carve-out" "$agents_body" "**LoEn carve-out:**"
  assert_contains "LoEn lifecycle only" "$agents_body" "use the LoEn lifecycle"
  assert_contains "LoEn skips fix-intent" "$agents_body" "Do not run \`fix-intent\`"
  assert_contains "LoEn skips check-chain" "$flat_agents_body" "or \`\$check-chain\` merely because a LoEn loop is active"
  assert_contains "LoEn state path" "$agents_body" "\`docs/loen/<topic>/\`"
  assert_contains "topic rule is controllable-artifact scoped" "$agents_body" "workflow artifacts the agent can control"
  assert_contains "topic rule includes LoEn topic directory" "$agents_body" "LoEn topic directory, for LoEn loop work"
  assert_contains "thread title is best effort" "$agents_body" "Thread title is best-effort only"
  assert_contains "inaccessible thread title is not blocking" "$flat_agents_body" "Do not treat an inaccessible UI thread title as a blocking artifact"
fi

if [[ -f "$readme" ]]; then
  readme_body="$(cat "$readme")"
  assert_contains "README workflow boundaries section" "$readme_body" "## Workflow boundaries"
  assert_contains "README separates LoEn and Superpowers" "$readme_body" "IDD->SDD/Superpowers and LoEn are separate workflow systems"
  assert_contains "README LoEn no Superpowers requirement" "$readme_body" "a LoEn loop does not require \`fix-intent\`, \`superpowers:*\`, or"
  assert_contains "README thread titles best effort" "$readme_body" "Thread titles are best-effort only"
fi

if [[ -f "$readme_ru" ]]; then
  readme_ru_body="$(cat "$readme_ru")"
  assert_contains "Russian README workflow boundaries section" "$readme_ru_body" "## Границы workflow"
  assert_contains "Russian README separates LoEn and Superpowers" "$readme_ru_body" "IDD -> SDD/Superpowers и LoEn — отдельные workflow"
  assert_contains "Russian README LoEn no Superpowers requirement" "$readme_ru_body" "активный LoEn loop сам по себе не требует \`fix-intent\`, \`superpowers:*\` или"
  assert_contains "Russian README thread titles best effort" "$readme_ru_body" "Thread title — best-effort"
fi

if [[ -f "$loen_readme" ]]; then
  loen_body="$(cat "$loen_readme")"
  assert_contains "LoEn README no workflow plugin dependency" "$loen_body" "LoEn is self-contained and does not depend on other workflow plugins"
  assert_contains "LoEn README lifecycle complete" "$loen_body" "The LoEn lifecycle is complete on its own"
fi

if [[ -f "$loen_readme_ru" ]]; then
  loen_ru_body="$(cat "$loen_readme_ru")"
  assert_contains "LoEn Russian README no workflow plugin dependency" "$loen_ru_body" "LoEn самодостаточен и не зависит от других workflow-плагинов"
  assert_contains "LoEn Russian README lifecycle complete" "$loen_ru_body" "Жизненный цикл LoEn полон сам по себе"
fi

finish
