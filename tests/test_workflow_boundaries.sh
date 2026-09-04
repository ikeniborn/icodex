#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

agents="$ROOT/.codex-isolated/AGENTS.md"
readme="$ROOT/README.md"
readme_ru="$ROOT/docs/README.ru.md"
profiles_readme="$ROOT/docs/profiles/README.md"
loen_readme="$ROOT/plugins/loen/README.md"
loen_readme_ru="$ROOT/plugins/loen/README.ru.md"

assert_exit "global AGENTS policy exists" 0 test -f "$agents"
assert_exit "README exists" 0 test -f "$readme"
assert_exit "Russian README exists" 0 test -f "$readme_ru"
assert_exit "profile manifest README exists" 0 test -f "$profiles_readme"
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
  assert_contains "workflow has three external routes" "$agents_body" 'Workflow recommendation: direct | chain | loen'
  assert_contains "workflow requires routing discovery" "$flat_agents_body" 'Before selecting a workflow, perform bounded routing discovery'
  assert_contains "missing evidence does not select chain" "$flat_agents_body" 'Absence of evidence is not evidence for chain'
  assert_contains "chain branches after intent" "$agents_body" 'Continuation after intent: execute | full | n/a'
  assert_contains "chain execute skips spec and plan" "$flat_agents_body" 'implements directly from the approved intent and marks Spec and Plan n/a'
  assert_contains "task page precedes every task" "$agents_body" "Every direct, chain, and LoEn task"
  assert_contains "read-only work tracked" "$agents_body" "including read-only analysis"
  assert_contains "wiki is sole durable status" "$agents_body" "sole durable task index"
  assert_contains "outage is fail-open execution" "$agents_body" "execution may continue"
  assert_contains "outage is fail-closed completion" "$agents_body" 'must not report `done`'
  assert_contains "missing task domain is fail-open execution" "$agents_body" "When iwiki is connected but the project domain is absent, execution may continue"
  assert_contains "missing task domain uses completion pending" "$agents_body" 'lifecycle is `completion-pending`'
  assert_contains "missing task domain is fail-closed completion" "$agents_body" 'must not report `done` until the domain and task page are available'
  assert_exit "no live repository task log" 1 grep -qF "Task Log (docs/TODO.md)" "$agents"
  assert_contains "routing discovery excludes task-specific analysis" "$flat_agents_body" 'must not perform task-specific analysis, reproduction, or test execution before the task page is resolved'
  assert_contains "direct creates no chain artifacts but resolves a task page" "$flat_agents_body" 'Direct work creates no formal intent, spec, plan, or `check-chain` artifact, but always resolves a wiki task page.'
  assert_contains "full continuation needs evidence" "$flat_agents_body" 'Recommend `full` only when both an enumerated design-risk category'
  assert_contains "full requires an unresolved decision" "$flat_agents_body" 'named unresolved design decision'
  assert_contains "direct skips fix-intent" "$agents_body" 'Direct work must not invoke `fix-intent`'
  assert_contains "direct skips brainstorming" "$agents_body" '`superpowers:brainstorming`'
  assert_contains "direct skips writing plans" "$agents_body" '`superpowers:writing-plans`'
  assert_contains "direct skips plan execution skills" "$flat_agents_body" '`superpowers:subagent-driven-development`, or `superpowers:executing-plans`'
  assert_contains "finishing skill remains available" "$agents_body" '`superpowers:finishing-a-development-branch` remains available'
  assert_contains "verification evidence follows relevant inputs" "$flat_agents_body" 'Verification evidence remains valid while its declared relevant inputs are unchanged.'
  assert_contains "fresh verification is state based" "$flat_agents_body" 'Fresh means produced after the last relevant input change for the exact code-state fingerprint; it does not mean rerun in the current message.'
  assert_contains "read-only work skips code tests" "$flat_agents_body" 'Read-only and documentation-only tasks run no code tests.'
  assert_contains "agent instructions are behavior" "$flat_agents_body" 'Agent instructions, skills, hooks, executable examples, and generated runtime inputs are behavior, not documentation-only content.'
  assert_contains "full suite has one owner" "$flat_agents_body" 'Run the full suite at most once for one unchanged code-state fingerprint.'
  assert_contains "matching full-suite evidence is reused" "$flat_agents_body" 'Result review, branch finishing, and completion checks reuse matching full-suite evidence.'
  assert_contains "focused test is not full-suite evidence" "$flat_agents_body" 'Never describe focused or related-test evidence as a full-suite pass.'
  assert_contains "high-risk verification stays strict" "$flat_agents_body" 'Security, migration, concurrency, and data-integrity changes retain their required enhanced verification.'
  assert_contains "verification budget changes strategy" "$flat_agents_body" 'A verification budget is a strategy-change threshold, never permission to skip a required check.'
  assert_contains "LoEn gets model checkpoints" "$flat_agents_body" 'At LoEn loop start and after each check or review, classify the next work'
  assert_contains "orchestrated transition branch" "$agents_body" "Orchestrated branch:"
  assert_contains "orchestrated validates split policy" "$flat_agents_body" "runner validates shared registry and direct project manifest"
  assert_contains "orchestrated accepts correlated local handoff" "$flat_agents_body" "hook accepts only correlated local handoff/session evidence"
  assert_contains "orchestrated task bypass is scoped" "$flat_agents_body" "for that protected task only"
  assert_contains "interactive transition branch" "$agents_body" "Interactive branch:"
  assert_contains "interactive recommendations do not block parent" "$flat_agents_body" 'Parent-session model recommendations are informational and never block safe work.'
  assert_contains "interactive work keeps active parent model" "$flat_agents_body" 'Continue on the active parent model without requesting `/status`, `/model`, downgrade confirmation, or escalation confirmation.'
  assert_contains "delegation requires coordination benefit" "$flat_agents_body" 'Delegate only when the expected benefit exceeds coordination cost.'
  assert_contains "delegated task gets explicit mapping" "$flat_agents_body" 'Pass the exact mapped `model` and `reasoning_effort` to `spawn_agent`'
  assert_contains "mechanical child cannot use unjustified strong route" "$flat_agents_body" 'A delegated mechanical subtask must not use a stronger route without an evidenced trigger.'
  assert_contains "missing child model does not block parent" "$flat_agents_body" 'An unavailable preferred child model never blocks safe parent work.'
  assert_contains "delegation preserves authority boundaries" "$flat_agents_body" 'Delegation never bypasses user confirmation for destructive, risky, or external actions.'
  assert_exit "interactive policy has no status stop gate" 1 grep -qF 'request `/status` before asking the user to switch' "$agents"
  assert_exit "interactive policy has no switch halt" 1 grep -qF 'Halt before the next stage when a recommended switch requires user action.' "$agents"
  assert_contains "hook never selects model" "$flat_agents_body" "never selects or changes model"
  assert_contains "semantic route mechanical" "$agents_body" '`mechanical`'
  assert_contains "semantic route engineering" "$agents_body" '`engineering`'
  assert_contains "semantic route synthesis" "$agents_body" '`synthesis`'
  assert_contains "semantic route deep" "$agents_body" '`deep`'
  assert_contains "semantic route escalation" "$agents_body" '`escalation`'
  assert_contains "semantic route parallel audit" "$agents_body" '`parallel-audit`'
  assert_contains "single current catalog mapping" "$agents_body" '### Current Catalog Mapping'
  assert_eq "one current catalog mapping section" "1" "$(grep -cF '### Current Catalog Mapping' "$agents")"
  model_ids_outside_mapping="$(awk '
    /^### Current Catalog Mapping$/ { in_mapping=1; next }
    in_mapping && /^### / { in_mapping=0 }
    !in_mapping { print }
  ' "$agents" | grep -E 'gpt-[0-9]' || true)"
  assert_eq "exact model ids only in current mapping" "" "$model_ids_outside_mapping"
fi

if [[ -f "$readme" ]]; then
  readme_body="$(cat "$readme")"
  flat_readme_body="$(tr '\n' ' ' < "$readme" | sed 's/[[:space:]][[:space:]]*/ /g')"
  assert_contains "README workflow boundaries section" "$readme_body" "## Workflow boundaries"
  assert_contains "README separates LoEn and Superpowers" "$readme_body" "IDD->SDD/Superpowers and LoEn are separate workflow systems"
  assert_contains "README LoEn no Superpowers requirement" "$flat_readme_body" "a LoEn loop does not require \`fix-intent\`, \`superpowers:*\`, or"
  assert_contains "README thread titles best effort" "$readme_body" "Thread titles are best-effort only"
  assert_contains "README documents three workflow routes" "$flat_readme_body" 'Workflow routing has three entries: `direct`, `chain`, and `loen`.'
  assert_contains "README documents chain continuation" "$flat_readme_body" '`execute` is the default; `full` needs both a design-risk category and a named unresolved design decision.'
  assert_contains "README documents state-based verification" "$flat_readme_body" 'Verification evidence is tied to relevant inputs and an exact code-state fingerprint, not to a conversation turn.'
  assert_contains "README documents one final full suite" "$flat_readme_body" 'run the full suite once on the final stable state'
  assert_contains "README documents canonical wiki task page" "$flat_readme_body" 'One canonical topic maps to `reference/tasks/<topic>`.'
  assert_contains "README documents direct and read-only task pages" "$flat_readme_body" 'Every direct, chain, and LoEn task, including read-only analysis, requires that task page.'
  assert_contains "README documents parent-only task writes" "$flat_readme_body" 'The parent agent is the sole writer; subagents return structured evidence only.'
  assert_contains "README documents completion pending outage" "$flat_readme_body" 'an MCP outage writes redacted local delivery-spool evidence and keeps lifecycle `completion-pending`.'
  assert_contains "README documents wiki-only status" "$flat_readme_body" 'Task-tagged wiki pages are the only current task-status index.'
  assert_contains "README documents legacy archive" "$flat_readme_body" 'Legacy repository history is archived at `reference/tasks-legacy-archive`.'
  assert_exit "README has no current repository TODO index" 1 grep -qF 'docs/TODO.md' "$readme"
fi

if [[ -f "$readme_ru" ]]; then
  readme_ru_body="$(cat "$readme_ru")"
  flat_readme_ru_body="$(tr '\n' ' ' < "$readme_ru" | sed 's/[[:space:]][[:space:]]*/ /g')"
  assert_contains "Russian README workflow boundaries section" "$readme_ru_body" "## Границы workflow"
  assert_contains "Russian README separates LoEn and Superpowers" "$readme_ru_body" "IDD -> SDD/Superpowers и LoEn — отдельные workflow"
  assert_contains "Russian README LoEn no Superpowers requirement" "$readme_ru_body" "активный LoEn loop сам по себе не требует \`fix-intent\`, \`superpowers:*\` или"
  assert_contains "Russian README thread titles best effort" "$readme_ru_body" "Thread title — best-effort"
  assert_contains "Russian README documents three workflow routes" "$readme_ru_body" 'Маршрутизация workflow имеет три входа: `direct`, `chain` и `loen`.'
  assert_contains "Russian README documents chain continuation" "$readme_ru_body" '`execute` выбирается по умолчанию; для `full` одновременно нужны категория design-risk и явно названное нерешённое design decision.'
  assert_contains "Russian README documents state-based verification" "$flat_readme_ru_body" 'Verification evidence привязывается к релевантным входам и точному fingerprint состояния кода, а не к сообщению в диалоге.'
  assert_contains "Russian README documents one final full suite" "$flat_readme_ru_body" 'запускают full suite один раз на финальном стабильном состоянии'
  assert_contains "Russian README documents canonical wiki task page" "$flat_readme_ru_body" 'Один canonical topic соответствует `reference/tasks/<topic>`.'
  assert_contains "Russian README documents direct and read-only task pages" "$flat_readme_ru_body" 'Каждая задача direct, chain или LoEn, включая read-only analysis, требует эту страницу.'
  assert_contains "Russian README documents parent-only task writes" "$flat_readme_ru_body" 'Только parent agent пишет состояние; subagent возвращает лишь structured evidence.'
  assert_contains "Russian README documents completion pending outage" "$flat_readme_ru_body" 'outage MCP записывает redacted evidence в локальный delivery spool и сохраняет lifecycle `completion-pending`.'
  assert_contains "Russian README documents wiki-only status" "$flat_readme_ru_body" 'Task-tagged wiki pages — единственный текущий индекс статуса задач.'
  assert_contains "Russian README documents legacy archive" "$flat_readme_ru_body" 'Исторический repository index архивирован в `reference/tasks-legacy-archive`.'
  assert_exit "Russian README has no current repository TODO index" 1 grep -qF 'docs/TODO.md' "$readme_ru"
  assert_contains "Russian README profile policy locations" "$readme_ru_body" '.codex-isolated/profiles/registry.yaml'
  assert_contains "Russian README project manifest policy location" "$readme_ru_body" 'docs/profiles/<topic>.yaml'
  assert_contains "Russian README shared profiles directory symlink" "$readme_ru_body" '.codex-homes/<проект>-<хеш>/profiles'
  assert_contains "Russian README shared profiles symlink target" "$readme_ru_body" '.codex-isolated/profiles`'
  assert_contains "Russian README manifest has independent approval commit" "$readme_ru_body" "отдельным коммитом"
  assert_contains "Russian README registry has independent repin commit" "$readme_ru_body" "отдельным коммитом"
  assert_contains "Russian README cold run command" "$readme_ru_body" './icodex.sh --run-task <topic> <task-id>'
  assert_contains "Russian README cold orchestration command" "$readme_ru_body" './icodex.sh --orchestrate <topic>'
  assert_contains "Russian README cold state never continues across machines" "$readme_ru_body" "новый cold run, а не продолжение с другой машины"
  assert_contains "Russian README local state deletion recovery" "$readme_ru_body" "Удаление локального состояния"
  assert_contains "Russian README dirty failure" "$readme_ru_body" "dirty"
  assert_contains "Russian README hash failure" "$readme_ru_body" "hash"
  assert_contains "Russian README path failure" "$readme_ru_body" "path"
  assert_contains "Russian README model failure" "$readme_ru_body" "model"
  assert_contains "Russian README no home manifest" "$readme_ru_body" "не хранит policy manifest"
  assert_contains "Russian README portable history out of scope" "$readme_ru_body" "Переносимой истории сессий, export/import"
  assert_contains "Russian README interactive parent is non-blocking" "$flat_readme_ru_body" 'Обычная интерактивная работа продолжает выполняться на активной parent model без обязательных `/model` или `/status`.'
  assert_contains "Russian README delegates explicit child mapping" "$flat_readme_ru_body" 'Для подходящих самостоятельных subtasks parent явно передаёт child agent выбранные `model` и `reasoning_effort`.'
fi

if [[ -f "$profiles_readme" ]]; then
  profiles_readme_body="$(cat "$profiles_readme")"
  flat_profiles_readme_body="$(tr '\n' ' ' < "$profiles_readme" | sed 's/[[:space:]][[:space:]]*/ /g')"
  assert_contains "direct topic does not pin interactive parent model" "$flat_profiles_readme_body" 'The direct profile does not pin the interactive parent model or block its next prompt.'
  assert_contains "direct topic preserves App Server route" "$flat_profiles_readme_body" 'This interactive path does not change the full-chain App Server runner.'
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
