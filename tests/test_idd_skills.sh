#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

SK="$ROOT/.codex-isolated/skills"
AGENTS="$SK/../AGENTS.md"
export ICODEX_ROOT="$ROOT"
export ICODEX_SHARED_DIR="$ROOT/.codex-isolated"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/plugin/superpowers.sh"
SP="$(_superpowers_pinned_cache_dir)/skills"

parse_frontmatter() { # <file> — exit 0 iff YAML frontmatter has name + description
  python3 - "$1" <<'PY'
import sys, yaml
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert lines and lines[0].strip() == "---"
fm = []
for ln in lines[1:]:
    if ln.strip() == "---":
        break
    fm.append(ln)
d = yaml.safe_load("\n".join(fm))
assert isinstance(d, dict) and d.get("name") and d.get("description")
PY
}

assert_before() { # <desc> <haystack> <first> <second>
  local desc="$1" hay="$2" first="$3" second="$4"
  local first_line second_line
  first_line="$(grep -nF -- "$first" <<<"$hay" | head -n1 | cut -d: -f1)"
  second_line="$(grep -nF -- "$second" <<<"$hay" | head -n1 | cut -d: -f1)"
  if [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]]; then
    echo "PASS [$desc]"; PASS=$((PASS+1))
  else
    echo "FAIL [$desc]: '$first' must appear before '$second'"; FAIL=$((FAIL+1))
  fi
}

assert_not_contains() { # <desc> <haystack> <needle>
  local desc="$1" hay="$2" need="$3"
  if grep -qF -- "$need" <<<"$hay"; then
    echo "FAIL [$desc]: unexpected '$need' found"; FAIL=$((FAIL+1))
  else
    echo "PASS [$desc]"; PASS=$((PASS+1))
  fi
}

# check-chain: one unified validator, four stage profiles.
CC="$SK/check-chain/SKILL.md"
assert_exit "check-chain SKILL.md exists" 0 test -f "$CC"
if [[ -f "$CC" ]]; then
  body="$(cat "$CC")"
  assert_contains "check-chain name frontmatter" "$body" "name: check-chain"
  assert_contains "check-chain has a description" "$body" "description:"
  assert_contains "check-chain references intent_hash" "$body" "intent_hash"
  assert_contains "check-chain references spec_hash" "$body" "spec_hash"
  assert_contains "check-chain references plan_hash" "$body" "plan_hash"
  assert_contains "check-chain result has two source modes" "$body" "Result has two source modes"
  assert_contains "check-chain recognizes chain route" "$body" 'workflow.route: chain'
  assert_contains "check-chain recognizes execute continuation" "$body" 'workflow.continuation: execute'
  assert_contains "check-chain intent result uses intent hash" "$body" 'intent_hash: <intent body hash>'
  assert_contains "check-chain execute continuation skips stages" "$body" 'mark `Spec: n/a` and `Plan: n/a`'
  assert_contains "check-chain legacy whole-chain detects plan" "$body" 'a legacy plan selects the'
  assert_contains "check-chain legacy whole-chain uses plan" "$body" 'plan-backed compatibility path'
  assert_contains "check-chain execute pending summary uses intent" "$body" '`OK up to intent` for `execute`'
  assert_contains "check-chain plan pending summary uses plan" "$body" '`OK up to plan` for plan-backed'
  assert_not_contains "check-chain has no unconditional brainstorm handoff" "$body" 'Next step: superpowers:brainstorming'
  assert_contains "check-chain writes result to source" "$body" 'Before offering the optional report, write `result_check` into the selected source'
  assert_contains "check-chain covers result stage" "$body" "result_check"
  assert_contains "check-chain approval requires OK first" "$body" 'Human approval is requested only after this stage returns `OK`'
  assert_contains "check-chain keeps task-page writes in main context" "$body" "Main context keeps task-page and changelog writes."
  assert_contains "check-chain skips duplicate cached events" "$body" "Cached intent/spec/plan checks do not append a duplicate gate event."
  assert_contains "check-chain cached stages read durable task page" "$body" 'Before returning cached OK, the parent reads `reference/tasks/<topic>`'
  assert_contains "check-chain cached stages verify TODO stage" "$body" 'verify the durable `TODO` stage is `OK`'
  assert_contains "check-chain cached stages verify matching event hash" "$body" 'matching `gate` event with the current body hash'
  assert_contains "check-chain missing cached page state reruns" "$body" "Missing task page state is not a cache hit"
  assert_contains "check-chain stale cached page state reruns" "$body" "Stale task page state is not a cache hit"
  assert_contains "check-chain cached result replays durable task state" "$body" "Cached result first verifies or replays durable final task-page state."
  assert_contains "check-chain cached result requires final evidence" "$body" "final verification evidence"
  assert_contains "check-chain cached result requires matching close hash" "$body" 'matching `close` event with the current selected-source hash'
  assert_contains "check-chain cached result requires done lifecycle" "$body" 'lifecycle is `done`'
  assert_contains "check-chain cached result requires empty spool" "$body" "spool is empty"
  assert_contains "check-chain cached result requires wiki completion" "$body" 'successful wiki write and `wiki_lint`'
  assert_contains "check-chain absent cached result state reruns" "$body" "Absent final task-page state is not a cache hit"
  assert_contains "check-chain stale cached result state reruns" "$body" "Stale final task-page state is not a cache hit"
  assert_contains "check-chain pending cached result stays pending" "$body" 'Pending spool state is not a cache hit; retain `completion-pending` and never report `done`.'
  assert_contains "check-chain records execute n/a stages in task page" "$body" "execute records Spec and Plan as n/a in the task page."
  assert_contains "check-chain persists evidence before close" "$body" "result writes final evidence before the close event."
  assert_contains "check-chain keeps pending completion during delivery" "$body" "completion-pending is used while spool events remain."
  assert_not_contains "check-chain has no repository task table" "$body" "docs/TODO.md"
  assert_not_contains "check-chain has no TODO row ownership" "$body" "TODO row"
  assert_not_contains "check-chain has no TODO cell ownership" "$body" "TODO cell"
  assert_exit "check-chain frontmatter parses" 0 parse_frontmatter "$CC"
fi

# chain auditor: read-only task-page review.
AUDITOR="$ROOT/.codex-isolated/agents/chain-auditor.toml"
assert_exit "chain auditor exists" 0 test -f "$AUDITOR"
if [[ -f "$AUDITOR" ]]; then
  auditor_body="$(cat "$AUDITOR")"
  assert_contains "chain auditor checks task-page readiness" "$auditor_body" "task-page readiness"
  assert_contains "chain auditor keeps MCP writes in main context" "$auditor_body" "every MCP write"
  assert_contains "chain auditor keeps spool acknowledgments in main context" "$auditor_body" "spool acknowledgment"
  assert_not_contains "chain auditor has no repository task table" "$auditor_body" "docs/TODO.md"
  assert_not_contains "chain auditor has no TODO row ownership" "$auditor_body" "TODO row"
  assert_not_contains "chain auditor has no TODO cell ownership" "$auditor_body" "TODO cell"
fi

# Skill availability: the injected catalog is authoritative over ad-hoc filesystem scans.
assert_exit "shared AGENTS.md exists" 0 test -f "$AGENTS"
if [[ -f "$AGENTS" ]]; then
  body="$(cat "$AGENTS")"
  assert_contains "available skills catalog is authoritative" "$body" "\`Available skills\` catalog injected into the current turn is authoritative"
  assert_contains "filesystem scan cannot mark a listed skill unavailable" "$body" "Never mark a listed skill unavailable because a filesystem scan"
fi

if [[ -f "$CC" ]]; then
  body="$(cat "$CC")"
  assert_contains "check-chain trusts available skills catalog" "$body" "the current turn's \`Available skills\` catalog lists \`check-chain\`"
  assert_contains "check-chain forbids filesystem availability probes" "$body" "Do not use filesystem scans to decide whether this skill is available"
fi

# fix-intent: intent capture skill.
FI="$SK/fix-intent/SKILL.md"
assert_exit "fix-intent SKILL.md exists" 0 test -f "$FI"
if [[ -f "$FI" ]]; then
  body="$(cat "$FI")"
  assert_contains "fix-intent name frontmatter" "$body" "name: fix-intent"
  assert_contains "fix-intent has a description" "$body" "description:"
  assert_contains "fix-intent runs check before approval" "$body" 'Run `$check-chain intent'
  assert_before "fix-intent check-chain before approval" "$body" 'Run `$check-chain intent' 'On approval, set `Status: approved`'
  assert_contains "fix-intent recommends continuation" "$body" 'Recommend `execute` or `full`'
  assert_contains "fix-intent records chain route" "$body" '`workflow.route: chain`'
  assert_contains "fix-intent records accepted continuation" "$body" '`workflow.continuation: execute|full`'
  assert_contains "fix-intent bootstraps draft topic profile with helper" "$body" 'python3 "$helper" bootstrap'
  assert_contains "fix-intent bootstrap defines copyable topic variable" "$body" 'topic="your-topic-slug"'
  assert_contains "fix-intent bootstrap derives current intent date" "$body" '$(date +%F)'
  assert_contains "fix-intent bootstrap quotes topic variable" "$body" '--topic "$topic"'
  assert_contains "fix-intent bootstrap quotes intent variable" "$body" '--intent "$intent_path"'
  assert_not_contains "fix-intent has no raw bootstrap topic placeholder" "$body" '--topic <topic>'
  assert_contains "fix-intent bootstrap defaults chain manifests to draft" "$body" '--status draft'
  assert_before "fix-intent bootstrap precedes intent validation" "$body" 'python3 "$helper" bootstrap' 'Run `$check-chain intent'
  assert_contains "fix-intent expands accepted full continuation" "$body" 'python3 "$helper" expand'
  assert_contains "fix-intent expansion selects full route" "$body" '--route full'
  assert_contains "fix-intent full expansion supplies authorization" "$body" '--authorization full'
  assert_contains "fix-intent commands locate helper from Codex root" "$body" 'helper="$ICODEX_ROOT/lib/profile/manifest.py"'
  assert_contains "fix-intent full expansion targets current Git worktree" "$body" 'project_root="$(git rev-parse --show-toplevel)"'
  assert_not_contains "fix-intent does not derive project root from Codex root" "$body" 'git -C "$ICODEX_ROOT" rev-parse --show-toplevel'
  assert_contains "fix-intent expansion quotes topic variable" "$body" '--topic "$topic"'
  assert_not_contains "fix-intent has no raw expansion topic placeholder" "$body" '--topic <topic>'
  assert_before "fix-intent records full continuation before expansion" "$body" 'workflow.continuation: full' 'python3 "$helper" expand'
  assert_contains "fix-intent full expansion includes selection task" "$body" 'intent-profile-selection'
  assert_contains "fix-intent full expansion includes spec task" "$body" 'spec-design'
  assert_contains "fix-intent full expansion includes plan task" "$body" 'plan-writing'
  assert_contains "fix-intent full expansion includes implementation task" "$body" 'implementation'
  assert_contains "fix-intent full expansion includes result task" "$body" 'result-reconciliation'
  assert_contains "fix-intent preserves execute without spec or plan" "$body" 'does not add spec or plan tasks'
  assert_contains "fix-intent defers future context paths" "$body" 'future spec or plan paths until those files exist'
  assert_not_contains "existing intent does not force brainstorming" "$body" 'Skip → go to brainstorm'
  assert_not_contains "small known work does not force IDD" "$body" 'Run IDD anyway'
  assert_before "fix-intent chooses continuation before brainstorming" "$body" 'Recommend `execute` or `full`' 'Run superpowers:brainstorming'
  assert_exit "fix-intent frontmatter parses" 0 parse_frontmatter "$FI"
fi

BR="$SP/brainstorming/SKILL.md"
assert_exit "brainstorming SKILL.md exists" 0 test -f "$BR"
if [[ -f "$BR" ]]; then
  body="$(cat "$BR")"
  assert_contains "brainstorming runs spec check before approval" "$body" 'Run `$check-chain spec <path>`'
  assert_contains "brainstorming distinguishes provisional feedback" "$body" "provisional design-section feedback"
  assert_contains "brainstorming needs_work returns to source" "$body" 'verdict is `needs_work`'
  assert_before "brainstorming check-chain before spec approval" "$body" 'Run `$check-chain spec <path>`' "Only proceed once the user approves the checked spec"
  assert_before "brainstorming fixes before successful recheck" "$body" '2. If the verdict is `needs_work`' '3. If the verdict is `OK`'
  assert_before "brainstorming approval before commit" "$body" "approves the checked spec" "commit the spec document once"
  assert_before "brainstorming commit before plan handoff" "$body" "commit the spec document once" "Invoke the writing-plans skill"
  assert_contains "brainstorming commits after checked spec approval" "$body" "commit the spec document once"
fi

WP="$SP/writing-plans/SKILL.md"
assert_exit "writing-plans SKILL.md exists" 0 test -f "$WP"
if [[ -f "$WP" ]]; then
  body="$(cat "$WP")"
  assert_contains "writing-plans runs plan check before approval" "$body" 'Run `$check-chain plan <path>`'
  assert_contains "writing-plans needs_work returns to source" "$body" 'verdict is `needs_work`'
  assert_before "writing-plans check-chain before plan approval" "$body" 'Run `$check-chain plan <path>`' "Only after the user approves the checked plan"
  assert_before "writing-plans fixes before successful recheck" "$body" '2. If the verdict is `needs_work`' '3. If the verdict is `OK`'
  assert_before "writing-plans approval before commit" "$body" "approves the checked plan" "Commit the approved plan"
  assert_before "writing-plans commit before execution handoff" "$body" "Commit the approved plan" "offer execution choice"
  assert_contains "writing-plans offers execution after checked plan" "$body" 'After the plan has passed `$check-chain plan <path>`'
fi

finish
