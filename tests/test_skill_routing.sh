#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
cd "$ROOT"

check_skill() { # <skill-path> <agent-name> <main-owned-phrase>
  local path="$1" agent="$2" owned="$3" text
  text="$(cat "$path" 2>/dev/null || true)"
  assert_contains "$path has routing section" "$text" "## Subagent Routing"
  assert_contains "$path names $agent" "$text" "Agent: \`$agent\`"
  assert_contains "$path keeps main ownership" "$text" "$owned"
  assert_contains "$path summary decision" "$text" "decision"
  assert_contains "$path summary evidence" "$text" "evidence"
  assert_contains "$path summary risks" "$text" "risks"
  assert_contains "$path summary next_action" "$text" "next_action"
}

check_skill ".codex-isolated/skills/check-chain/SKILL.md" "chain-auditor" "Main context keeps confirmations, final verdicts, frontmatter writes, report merges, task-log row updates, and downstream stop/go decisions."
check_skill ".codex-isolated/skills/html-report/SKILL.md" "artifact-renderer" "Main context keeps ambiguous source selection, final file writes, and user-facing output reporting."
check_skill ".codex-isolated/skills/mermaid-obsidian/SKILL.md" "diagram-checker" "Main context keeps semantic questions, final diagram text, and file edits."
check_skill ".codex-isolated/skills/git-workflow/SKILL.md" "repo-safety-reviewer" "Main context keeps all mutating git commands: checkout, branch creation, add, commit, push, and PR creation."
check_skill ".codex-isolated/skills/context-awareness/SKILL.md" "project-explorer" "Main context keeps final project_context synthesis, task-specific documentation interpretation, and deep semantic wiki searches."

finish
