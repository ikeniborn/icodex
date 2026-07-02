# 01 LoEn Plugin Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `plugins/loen/` as a self-contained editable Codex plugin source tree with manifest, workflow skills, inert hook assets, role agent definitions, templates, docs, and fixture validation.

**Architecture:** Keep this layer as source assets only: no icodex launcher wiring, no vendoring, and no installed cache mutation. A single dependency-free Bash fixture test validates the directory contract, JSON/TOML parsing, hook-to-script consistency, unique skill names, required templates, and independence from the current chain tooling. Runtime behavior remains minimal and deterministic; hook scripts read LoEn task artifact paths and exit successfully until later layers define enforcement semantics.

**Tech Stack:** Bash tests, Python 3 standard library for JSON/TOML parsing in tests and hook assets, Markdown skills/docs, Codex plugin manifest JSON, TOML agent definitions.

Spec: `docs/superpowers/specs/2026-07-02-01-loen-plugin-core-design.md`

---

## Scope Check

This spec covers one subsystem: editable LoEn plugin source assets under `plugins/loen/`. It does not install the plugin, wire it into `icodex.sh`, create runtime task artifacts under `docs/loen/<topic>/`, enforce hook decisions, or define full agent isolation behavior. Those behaviors belong to later LoEn layer specs.

## File Structure

- **Create** `tests/test_loen_plugin_core.sh` - fixture contract test for the plugin source tree.
- **Create** `plugins/loen/.codex-plugin/plugin.json` - Codex plugin manifest and source directory pointers.
- **Create** `plugins/loen/skills/*/SKILL.md` - ten user-facing LoEn workflow skills.
- **Create** `plugins/loen/hooks/hooks.json` - hook asset registry.
- **Create** `plugins/loen/hooks/*.py` - deterministic inert hook scripts.
- **Create** `plugins/loen/agents/*.toml` - role-specific agent asset definitions.
- **Create** `plugins/loen/assets/templates/*` - source templates for later runtime artifacts.
- **Create** `plugins/loen/docs/README.md` and `plugins/loen/docs/architecture.md` - plugin-local source documentation.
- **Do not modify** `lib/`, `icodex.sh`, `.codex-isolated/plugins/cache/`, or any runtime install path in this plan.

## Execution Prerequisites

Use the project branch workflow before Task 1. If no suitable `dev-*` branch already exists, use `git-workflow` and `superpowers:using-git-worktrees`: ask whether to create a worktree, then create a branch such as `dev-01-loen-plugin-core` from the intended base branch. Run all commands from the repository root.

---

### Task 1: Add Plugin Core Fixture Test

**Files:**
- Create: `tests/test_loen_plugin_core.sh`
- Read: `docs/superpowers/specs/2026-07-02-01-loen-plugin-core-design.md`

- [ ] **Step 1: Write the failing test**

Create `tests/test_loen_plugin_core.sh` with:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

plugin_root="$ROOT/plugins/loen"
manifest="$plugin_root/.codex-plugin/plugin.json"
hooks_json="$plugin_root/hooks/hooks.json"

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
import tomllib
from pathlib import Path

data = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
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
  forbidden_refs="$(find "$plugin_root" -type f -print0 | xargs -0 grep -En 'IDD|SDD|Superpowers|docs/superpowers|fix-intent|check-chain|lib/plugin/iwiki\.sh' 2>/dev/null || true)"
else
  forbidden_refs="missing plugin root"
fi
assert_eq "plugin source has no current-chain references" "" "$forbidden_refs"

finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash tests/test_loen_plugin_core.sh
```

Expected: FAIL because `plugins/loen/` does not exist yet. Expected failing lines include:

```text
FAIL [plugin root exists]: exit 1 want 0
FAIL [plugin manifest exists]: exit 1 want 0
FAIL [skill exists: loop-start]: exit 1 want 0
```

- [ ] **Step 3: Syntax-check the new test**

Run:

```bash
bash -n tests/test_loen_plugin_core.sh
```

Expected: exit code `0`.

- [ ] **Step 4: Commit the failing fixture test**

Run:

```bash
git add tests/test_loen_plugin_core.sh
git commit -m "test(loen): define plugin core fixture contract"
```

Expected: commit succeeds on a `dev-*` branch.

---

### Task 2: Create Plugin Manifest and Source Directories

**Files:**
- Create: `plugins/loen/.codex-plugin/plugin.json`
- Create directories: `plugins/loen/skills/`, `plugins/loen/hooks/`, `plugins/loen/agents/`, `plugins/loen/assets/templates/`, `plugins/loen/docs/`
- Test: `tests/test_loen_plugin_core.sh`

- [ ] **Step 1: Create source directories**

Run:

```bash
mkdir -p plugins/loen/.codex-plugin plugins/loen/skills plugins/loen/hooks plugins/loen/agents plugins/loen/assets/templates plugins/loen/docs
```

Expected: exit code `0`.

- [ ] **Step 2: Create the plugin manifest**

Create `plugins/loen/.codex-plugin/plugin.json` with:

```json
{
  "name": "loen",
  "version": "0.1.0",
  "description": "Loop Engineering workflow assets for bounded planning, action, checking, reflection, repair, research, review, and governance.",
  "author": {
    "name": "icodex"
  },
  "license": "MIT",
  "keywords": [
    "loop-engineering",
    "planning",
    "verification",
    "workflow",
    "governance"
  ],
  "skills": "./skills/",
  "hooks": "./hooks/hooks.json",
  "agents": "./agents/",
  "assets": "./assets/",
  "interface": {
    "displayName": "LoEn",
    "shortDescription": "Loop Engineering workflow assets for Codex",
    "longDescription": "LoEn provides source assets for durable loop artifacts, role-specific skills, inert hook scripts, templates, and agent definitions. Installation and runtime enablement are handled by later integration layers.",
    "developerName": "icodex",
    "category": "Developer Tools",
    "capabilities": [
      "Interactive",
      "Read",
      "Write"
    ],
    "defaultPrompt": [
      "Start a LoEn loop for this task.",
      "Check the active LoEn loop status."
    ],
    "brandColor": "#2F6F5E"
  }
}
```

- [ ] **Step 3: Run the fixture test**

Run:

```bash
bash tests/test_loen_plugin_core.sh
```

Expected: FAIL. The manifest assertions pass, and the remaining failures are missing skills, hooks, agents, templates, and docs.

- [ ] **Step 4: Commit the manifest**

Run:

```bash
git add plugins/loen/.codex-plugin/plugin.json
git commit -m "feat(loen): add plugin source manifest"
```

Expected: commit succeeds.

---

### Task 3: Add LoEn Workflow Skills

**Files:**
- Create: `plugins/loen/skills/loop-start/SKILL.md`
- Create: `plugins/loen/skills/loop-plan/SKILL.md`
- Create: `plugins/loen/skills/loop-act/SKILL.md`
- Create: `plugins/loen/skills/loop-check/SKILL.md`
- Create: `plugins/loen/skills/loop-reflect/SKILL.md`
- Create: `plugins/loen/skills/loop-status/SKILL.md`
- Create: `plugins/loen/skills/loop-repair/SKILL.md`
- Create: `plugins/loen/skills/loop-research/SKILL.md`
- Create: `plugins/loen/skills/loop-review/SKILL.md`
- Create: `plugins/loen/skills/loop-governance/SKILL.md`
- Test: `tests/test_loen_plugin_core.sh`

- [ ] **Step 1: Create skill directories**

Run:

```bash
mkdir -p plugins/loen/skills/loop-start plugins/loen/skills/loop-plan plugins/loen/skills/loop-act plugins/loen/skills/loop-check plugins/loen/skills/loop-reflect plugins/loen/skills/loop-status plugins/loen/skills/loop-repair plugins/loen/skills/loop-research plugins/loen/skills/loop-review plugins/loen/skills/loop-governance
```

Expected: exit code `0`.

- [ ] **Step 2: Create `loop-start`**

Create `plugins/loen/skills/loop-start/SKILL.md` with:

```markdown
---
name: loop-start
description: LoEn skill for creating or selecting a topic and writing goal artifacts under docs/loen/<topic>/.
---

# LoEn Loop Start

Use this skill when the user asks to start a LoEn loop, create a durable loop topic, or turn an open-ended request into a bounded loop workspace.

## Procedure

1. Choose a short kebab-case topic from the user request.
2. Create or reuse `docs/loen/<topic>/`.
3. Write `1_goal.md` from `assets/templates/1_goal.md`.
4. Write `loop.yaml` from `assets/templates/loop.yaml`.
5. Record only durable task facts in `docs/loen/<topic>/`; do not use chat history as the source of truth.

## Output

Report the topic, artifact directory, and the next recommended LoEn skill.
```

- [ ] **Step 3: Create `loop-plan`**

Create `plugins/loen/skills/loop-plan/SKILL.md` with:

```markdown
---
name: loop-plan
description: LoEn skill for converting goal and context artifacts into a bounded plan under docs/loen/<topic>/.
---

# LoEn Loop Plan

Use this skill when `docs/loen/<topic>/1_goal.md` exists and the loop needs a bounded execution plan.

## Procedure

1. Read `docs/loen/<topic>/1_goal.md`, `2_context.md` if present, and `loop.yaml`.
2. Write `3_plan.md` from `assets/templates/3_plan.md`.
3. Keep the plan bounded to one verifiable loop pass.
4. Include exact checks that later `loop-check` can run or inspect.

## Output

Report the selected topic, planned steps, and verification command list.
```

- [ ] **Step 4: Create `loop-act`**

Create `plugins/loen/skills/loop-act/SKILL.md` with:

```markdown
---
name: loop-act
description: LoEn skill for executing one bounded action step and recording action evidence under docs/loen/<topic>/.
---

# LoEn Loop Act

Use this skill when `docs/loen/<topic>/3_plan.md` identifies the next bounded action.

## Procedure

1. Read `docs/loen/<topic>/loop.yaml` and `3_plan.md`.
2. Execute exactly one bounded action from the active plan.
3. Write `4_act.md` from `assets/templates/4_act.md`.
4. Record files changed, commands run, and any observed result.

## Output

Report the action completed, changed paths, and the next check to run.
```

- [ ] **Step 5: Create `loop-check`**

Create `plugins/loen/skills/loop-check/SKILL.md` with:

```markdown
---
name: loop-check
description: LoEn skill for running configured checks and recording evidence under docs/loen/<topic>/.
---

# LoEn Loop Check

Use this skill after a bounded action changes code, docs, or configuration.

## Procedure

1. Read check commands from `docs/loen/<topic>/3_plan.md` and `loop.yaml`.
2. Run each check from the repository root.
3. Write `5_check.md` from `assets/templates/5_check.md`.
4. Record command, exit code, and relevant output summary for each check.

## Output

Report pass/fail state and the evidence file path.
```

- [ ] **Step 6: Create `loop-reflect`**

Create `plugins/loen/skills/loop-reflect/SKILL.md` with:

```markdown
---
name: loop-reflect
description: LoEn skill for deciding keep, fix, revert, or handoff from evidence under docs/loen/<topic>/.
---

# LoEn Loop Reflect

Use this skill after checks produce evidence.

## Procedure

1. Read `docs/loen/<topic>/4_act.md` and `5_check.md`.
2. Decide one outcome: keep, fix, revert, or handoff.
3. Write `6_reflect.md` from `assets/templates/6_reflect.md`.
4. If the loop is complete, write `7_result.md` from `assets/templates/7_result.md`.

## Output

Report the decision, reason, and next LoEn skill if more work remains.
```

- [ ] **Step 7: Create `loop-status`**

Create `plugins/loen/skills/loop-status/SKILL.md` with:

```markdown
---
name: loop-status
description: LoEn skill for summarizing current topic state from artifacts under docs/loen/<topic>/.
---

# LoEn Loop Status

Use this skill when the user asks for the state of a LoEn topic or all active LoEn topics.

## Procedure

1. Read `docs/loen/<topic>/loop.yaml` and numbered artifact files.
2. Summarize current stage, latest evidence, open decisions, and next action.
3. Treat missing artifact files as missing state, not as implied chat state.

## Output

Report concise status with artifact paths and discrepancies.
```

- [ ] **Step 8: Create `loop-repair`**

Create `plugins/loen/skills/loop-repair/SKILL.md` with:

```markdown
---
name: loop-repair
description: LoEn skill for specializing a loop around failing tests, CI failures, or regressions under docs/loen/<topic>/.
---

# LoEn Loop Repair

Use this skill when evidence shows a failing test, CI failure, regression, or broken behavior.

## Procedure

1. Read failure evidence from `docs/loen/<topic>/5_check.md` or supplied logs.
2. Write repair context to `docs/loen/<topic>/2_context.md`.
3. Keep the repair plan focused on reproducing, isolating, fixing, and rechecking the failure.
4. Hand back to `loop-plan` or `loop-act` for execution.

## Output

Report the failing signal, suspected surface, and next bounded repair step.
```

- [ ] **Step 9: Create `loop-research`**

Create `plugins/loen/skills/loop-research/SKILL.md` with:

```markdown
---
name: loop-research
description: LoEn skill for metric-driven experiments and research loops under docs/loen/<topic>/.
---

# LoEn Loop Research

Use this skill when the loop is an experiment with a measurable question.

## Procedure

1. Write the research question and metric to `docs/loen/<topic>/2_context.md`.
2. Keep experiments small enough for one loop pass.
3. Record measurement commands in `3_plan.md`.
4. Record observed results in `5_check.md` and decision logic in `6_reflect.md`.

## Output

Report metric, baseline, experiment step, and decision threshold.
```

- [ ] **Step 10: Create `loop-review`**

Create `plugins/loen/skills/loop-review/SKILL.md` with:

```markdown
---
name: loop-review
description: LoEn skill for PR or diff review loops with findings recorded under docs/loen/<topic>/.
---

# LoEn Loop Review

Use this skill when reviewing a diff, branch, or pull request through a LoEn topic.

## Procedure

1. Record review scope in `docs/loen/<topic>/1_goal.md`.
2. Inspect changed files and tests relevant to the scope.
3. Write findings and evidence to `5_check.md`.
4. Write final review disposition to `7_result.md` when complete.

## Output

Lead with findings by severity, then open questions, then verification evidence.
```

- [ ] **Step 11: Create `loop-governance`**

Create `plugins/loen/skills/loop-governance/SKILL.md` with:

```markdown
---
name: loop-governance
description: LoEn skill for scheduled or recurring checks with governance artifacts under docs/loen/<topic>/.
---

# LoEn Loop Governance

Use this skill when a LoEn topic represents a recurring check or scheduled governance pass.

## Procedure

1. Record recurrence, owner, and review requirement in `docs/loen/<topic>/loop.yaml`.
2. Keep scheduled activity advisory unless later integration enables stricter modes.
3. Record every run in the topic artifacts.
4. Require human review before any merge, release, or destructive operation.

## Output

Report schedule, latest evidence, required human decision, and next run condition.
```

- [ ] **Step 12: Run the fixture test**

Run:

```bash
bash tests/test_loen_plugin_core.sh
```

Expected: FAIL. Skill assertions pass, and remaining failures are missing hooks, agents, templates, and docs.

- [ ] **Step 13: Commit the skills**

Run:

```bash
git add plugins/loen/skills
git commit -m "feat(loen): add workflow skill assets"
```

Expected: commit succeeds.

---

### Task 4: Add Inert Hook Assets

**Files:**
- Create: `plugins/loen/hooks/hooks.json`
- Create: `plugins/loen/hooks/loop-gate.py`
- Create: `plugins/loen/hooks/scope-guard.py`
- Create: `plugins/loen/hooks/tool-guard.py`
- Create: `plugins/loen/hooks/permission-guard.py`
- Create: `plugins/loen/hooks/evidence-gate.py`
- Create: `plugins/loen/hooks/audit-writer.py`
- Test: `tests/test_loen_plugin_core.sh`

- [ ] **Step 1: Create hook registry**

Create `plugins/loen/hooks/hooks.json` with:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|apply_patch|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$CODEX_PLUGIN_DIR/hooks/loop-gate.py\"",
            "timeout": 30,
            "statusMessage": "LoEn loop gate"
          },
          {
            "type": "command",
            "command": "python3 \"$CODEX_PLUGIN_DIR/hooks/scope-guard.py\"",
            "timeout": 30,
            "statusMessage": "LoEn scope guard"
          },
          {
            "type": "command",
            "command": "python3 \"$CODEX_PLUGIN_DIR/hooks/tool-guard.py\"",
            "timeout": 30,
            "statusMessage": "LoEn tool guard"
          },
          {
            "type": "command",
            "command": "python3 \"$CODEX_PLUGIN_DIR/hooks/permission-guard.py\"",
            "timeout": 30,
            "statusMessage": "LoEn permission guard"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|apply_patch|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$CODEX_PLUGIN_DIR/hooks/audit-writer.py\"",
            "timeout": 30,
            "statusMessage": "LoEn audit writer"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$CODEX_PLUGIN_DIR/hooks/evidence-gate.py\"",
            "timeout": 30,
            "statusMessage": "LoEn evidence gate"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Create hook scripts**

Create each hook file below with its matching `SCRIPT_NAME` value.

`plugins/loen/hooks/loop-gate.py`:

```python
#!/usr/bin/env python3
"""Inert LoEn loop gate hook asset."""
from pathlib import Path
import os

SCRIPT_NAME = "loop-gate"


def read_loop_artifact() -> str:
  topic = os.environ.get("LOEN_TOPIC", "").strip()
  root = Path(os.environ.get("LOEN_ARTIFACT_ROOT", "docs/loen"))
  if not topic:
    return ""
  loop_file = root / topic / "loop.yaml"
  if not loop_file.is_file():
    return ""
  return loop_file.read_text(encoding="utf-8")


def main() -> int:
  read_loop_artifact()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
```

`plugins/loen/hooks/scope-guard.py`:

```python
#!/usr/bin/env python3
"""Inert LoEn scope guard hook asset."""
from pathlib import Path
import os

SCRIPT_NAME = "scope-guard"


def read_loop_artifact() -> str:
  topic = os.environ.get("LOEN_TOPIC", "").strip()
  root = Path(os.environ.get("LOEN_ARTIFACT_ROOT", "docs/loen"))
  if not topic:
    return ""
  loop_file = root / topic / "loop.yaml"
  if not loop_file.is_file():
    return ""
  return loop_file.read_text(encoding="utf-8")


def main() -> int:
  read_loop_artifact()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
```

`plugins/loen/hooks/tool-guard.py`:

```python
#!/usr/bin/env python3
"""Inert LoEn tool guard hook asset."""
from pathlib import Path
import os

SCRIPT_NAME = "tool-guard"


def read_loop_artifact() -> str:
  topic = os.environ.get("LOEN_TOPIC", "").strip()
  root = Path(os.environ.get("LOEN_ARTIFACT_ROOT", "docs/loen"))
  if not topic:
    return ""
  loop_file = root / topic / "loop.yaml"
  if not loop_file.is_file():
    return ""
  return loop_file.read_text(encoding="utf-8")


def main() -> int:
  read_loop_artifact()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
```

`plugins/loen/hooks/permission-guard.py`:

```python
#!/usr/bin/env python3
"""Inert LoEn permission guard hook asset."""
from pathlib import Path
import os

SCRIPT_NAME = "permission-guard"


def read_loop_artifact() -> str:
  topic = os.environ.get("LOEN_TOPIC", "").strip()
  root = Path(os.environ.get("LOEN_ARTIFACT_ROOT", "docs/loen"))
  if not topic:
    return ""
  loop_file = root / topic / "loop.yaml"
  if not loop_file.is_file():
    return ""
  return loop_file.read_text(encoding="utf-8")


def main() -> int:
  read_loop_artifact()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
```

`plugins/loen/hooks/evidence-gate.py`:

```python
#!/usr/bin/env python3
"""Inert LoEn evidence gate hook asset."""
from pathlib import Path
import os

SCRIPT_NAME = "evidence-gate"


def read_loop_artifact() -> str:
  topic = os.environ.get("LOEN_TOPIC", "").strip()
  root = Path(os.environ.get("LOEN_ARTIFACT_ROOT", "docs/loen"))
  if not topic:
    return ""
  loop_file = root / topic / "loop.yaml"
  if not loop_file.is_file():
    return ""
  return loop_file.read_text(encoding="utf-8")


def main() -> int:
  read_loop_artifact()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
```

`plugins/loen/hooks/audit-writer.py`:

```python
#!/usr/bin/env python3
"""Inert LoEn audit writer hook asset."""
from pathlib import Path
import os

SCRIPT_NAME = "audit-writer"


def read_loop_artifact() -> str:
  topic = os.environ.get("LOEN_TOPIC", "").strip()
  root = Path(os.environ.get("LOEN_ARTIFACT_ROOT", "docs/loen"))
  if not topic:
    return ""
  loop_file = root / topic / "loop.yaml"
  if not loop_file.is_file():
    return ""
  return loop_file.read_text(encoding="utf-8")


def main() -> int:
  read_loop_artifact()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
```

- [ ] **Step 3: Make hook scripts executable and syntax-check them**

Run:

```bash
chmod +x plugins/loen/hooks/*.py
python3 -m py_compile plugins/loen/hooks/*.py
```

Expected: exit code `0`.

- [ ] **Step 4: Run the fixture test**

Run:

```bash
bash tests/test_loen_plugin_core.sh
```

Expected: FAIL. Hook assertions pass, and remaining failures are missing agents, templates, and docs.

- [ ] **Step 5: Commit the hook assets**

Run:

```bash
git add plugins/loen/hooks
git commit -m "feat(loen): add inert hook assets"
```

Expected: commit succeeds.

---

### Task 5: Add Agent Definitions and Templates

**Files:**
- Create: `plugins/loen/agents/loen-planner.toml`
- Create: `plugins/loen/agents/loen-worker.toml`
- Create: `plugins/loen/agents/loen-verifier.toml`
- Create: `plugins/loen/agents/loen-reviewer.toml`
- Create: `plugins/loen/agents/loen-researcher.toml`
- Create: `plugins/loen/assets/templates/loop.yaml`
- Create: `plugins/loen/assets/templates/1_goal.md`
- Create: `plugins/loen/assets/templates/2_context.md`
- Create: `plugins/loen/assets/templates/3_plan.md`
- Create: `plugins/loen/assets/templates/4_act.md`
- Create: `plugins/loen/assets/templates/5_check.md`
- Create: `plugins/loen/assets/templates/6_reflect.md`
- Create: `plugins/loen/assets/templates/7_result.md`
- Create: `plugins/loen/assets/templates/handoff.md`
- Create: `plugins/loen/assets/templates/audit.html`
- Test: `tests/test_loen_plugin_core.sh`

- [ ] **Step 1: Create agent definitions**

Create `plugins/loen/agents/loen-planner.toml` with:

```toml
name = "loen-planner"
role = "planner"
summary = "Creates bounded LoEn plans from goal and context artifacts."
read_only_default = false
artifact_root = "docs/loen"
allowed_outputs = ["3_plan.md"]
```

Create `plugins/loen/agents/loen-worker.toml` with:

```toml
name = "loen-worker"
role = "worker"
summary = "Executes one bounded LoEn action step and records action evidence."
read_only_default = false
artifact_root = "docs/loen"
allowed_outputs = ["4_act.md"]
```

Create `plugins/loen/agents/loen-verifier.toml` with:

```toml
name = "loen-verifier"
role = "verifier"
summary = "Runs or inspects checks and records verification evidence."
read_only_default = true
artifact_root = "docs/loen"
allowed_outputs = ["5_check.md"]
```

Create `plugins/loen/agents/loen-reviewer.toml` with:

```toml
name = "loen-reviewer"
role = "reviewer"
summary = "Reviews diffs and evidence before a LoEn loop is accepted."
read_only_default = true
artifact_root = "docs/loen"
allowed_outputs = ["5_check.md", "6_reflect.md"]
```

Create `plugins/loen/agents/loen-researcher.toml` with:

```toml
name = "loen-researcher"
role = "researcher"
summary = "Frames metric-driven LoEn experiments and records observations."
read_only_default = true
artifact_root = "docs/loen"
allowed_outputs = ["2_context.md", "5_check.md"]
```

- [ ] **Step 2: Create runtime artifact templates**

Create `plugins/loen/assets/templates/loop.yaml` with:

```yaml
topic: "{{topic}}"
status: active
stage: goal
created: "{{created_date}}"
updated: "{{updated_date}}"
artifact_root: "docs/loen/{{topic}}"
checks: []
decision: pending
```

Create `plugins/loen/assets/templates/1_goal.md` with:

```markdown
# Goal

Topic: `{{topic}}`

## User Request

{{user_request}}

## Success Criteria

- {{success_criterion}}
```

Create `plugins/loen/assets/templates/2_context.md` with:

```markdown
# Context

Topic: `{{topic}}`

## Facts

- {{fact}}

## Constraints

- {{constraint}}
```

Create `plugins/loen/assets/templates/3_plan.md` with:

````markdown
# Plan

Topic: `{{topic}}`

## Steps

1. {{step}} -> verify: {{verification}}

## Checks

```bash
{{check_command}}
```
````

Create `plugins/loen/assets/templates/4_act.md` with:

````markdown
# Act

Topic: `{{topic}}`

## Action

{{action_summary}}

## Changed Paths

- `{{path}}`

## Commands

```bash
{{command}}
```
````

Create `plugins/loen/assets/templates/5_check.md` with:

````markdown
# Check

Topic: `{{topic}}`

## Evidence

```text
{{evidence}}
```

## Result

{{result}}
````

Create `plugins/loen/assets/templates/6_reflect.md` with:

```markdown
# Reflect

Topic: `{{topic}}`

## Decision

{{decision}}

## Reason

{{reason}}

## Next Step

{{next_step}}
```

Create `plugins/loen/assets/templates/7_result.md` with:

```markdown
# Result

Topic: `{{topic}}`

## Outcome

{{outcome}}

## Evidence Files

- `{{evidence_file}}`
```

Create `plugins/loen/assets/templates/handoff.md` with:

```markdown
# Handoff

Topic: `{{topic}}`

## Current State

{{current_state}}

## Required Human Decision

{{required_decision}}
```

Create `plugins/loen/assets/templates/audit.html` with:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>LoEn Audit - {{topic}}</title>
</head>
<body>
  <main>
    <h1>LoEn Audit</h1>
    <p><strong>Topic:</strong> {{topic}}</p>
    <section>
      <h2>Evidence</h2>
      <pre>{{evidence}}</pre>
    </section>
  </main>
</body>
</html>
```

- [ ] **Step 3: Parse TOML and run the fixture test**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
import tomllib

for path in sorted(Path("plugins/loen/agents").glob("*.toml")):
    tomllib.loads(path.read_text(encoding="utf-8"))
    print(f"OK {path}")
PY
bash tests/test_loen_plugin_core.sh
```

Expected: TOML parser prints one `OK ...` line for each of the five agent files. Fixture test still FAILS only because plugin docs are missing.

- [ ] **Step 4: Commit agents and templates**

Run:

```bash
git add plugins/loen/agents plugins/loen/assets/templates
git commit -m "feat(loen): add agent definitions and templates"
```

Expected: commit succeeds.

---

### Task 6: Add Plugin Docs and Final Verification

**Files:**
- Create: `plugins/loen/docs/README.md`
- Create: `plugins/loen/docs/architecture.md`
- Test: `tests/test_loen_plugin_core.sh`

- [ ] **Step 1: Create plugin README**

Create `plugins/loen/docs/README.md` with:

```markdown
# LoEn Plugin Source

LoEn is an editable Codex plugin source tree for Loop Engineering workflows.
This layer contains source assets only: manifest, skills, hook scripts, agent
definitions, templates, and plugin-local documentation.

## Directories

- `.codex-plugin/plugin.json` identifies the plugin and source asset paths.
- `skills/` contains the user-facing loop workflow skills.
- `hooks/` contains deterministic hook assets that remain inert until an
  integration layer installs and enables the plugin.
- `agents/` contains role-specific agent asset definitions.
- `assets/templates/` contains source templates for later runtime artifacts.

## Artifact Boundary

Active task artifacts are written under `docs/loen/<topic>/`. The plugin source
tree does not write installed cache files and does not depend on icodex runtime
wiring.
```

- [ ] **Step 2: Create architecture doc**

Create `plugins/loen/docs/architecture.md` with:

```markdown
# LoEn Core Architecture

## Source Layer

The core layer establishes the editable plugin source tree. It is safe to
validate without installing the plugin into Codex because all assets are plain
JSON, Markdown, Python, TOML, YAML, and HTML files.

## Hook Assets

Hook scripts are deterministic and read only LoEn artifact paths such as
`docs/loen/<topic>/loop.yaml`. In this layer they exit successfully and do not
block actions. Later layers define enforcement semantics.

## Agent Assets

Agent definitions describe role names, default write posture, artifact root, and
allowed output files. Verifier, reviewer, and researcher roles are read-only by
default.

## Runtime Boundary

Installation, launch-time wiring, cache layout, and runtime enablement are owned
by later integration layers. This source tree is not an installed plugin cache.
```

- [ ] **Step 3: Run focused verification**

Run:

```bash
bash tests/test_loen_plugin_core.sh
```

Expected: PASS with `FAIL=0`.

- [ ] **Step 4: Run full Bash suite**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: all tests finish with no failing assertion and exit code `0`.

- [ ] **Step 5: Commit docs and passing verification**

Run:

```bash
git add plugins/loen/docs
git commit -m "docs(loen): document plugin source architecture"
```

Expected: commit succeeds.

---

## Self-Review

- Spec coverage: Task 2 covers the manifest and self-contained source root; Task 3 covers all ten skills; Task 4 covers `hooks/hooks.json` and the six deterministic hook scripts; Task 5 covers all five agent definitions and all ten templates; Task 6 covers plugin-local docs and final validation. The fixture test checks all acceptance bullets.
- Independence check: The fixture rejects references to current chain tooling and installed plugin cache paths inside `plugins/loen/`.
- Type consistency: Skill names match directory names; hook command script names match files; agent TOML uses the same required keys across all five agent definitions; template filenames match the spec list.
