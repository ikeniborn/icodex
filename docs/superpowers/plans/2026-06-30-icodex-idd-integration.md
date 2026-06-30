---
review:
  plan_hash: 1c3203e14090a2bf
  spec_hash: 53cf73c1480846c0
  last_run: 2026-06-30
  phases:
    structure:     { status: passed }
    coverage:      { status: passed }
    dependencies:  { status: passed }
    verifiability: { status: passed }
    consistency:   { status: passed }
  findings:
    - id: F-001
      phase: coverage
      severity: WARNING
      section: "Task 3 / Step 1 (tests/test_idd_wiring.sh)"
      section_hash: null
      fragment: 'assert_contains "base block-secrets preserved" "$hooks" "block-secrets.py"'
      text: >-
        Spec Testing section requires test_idd_wiring.sh to verify, after a caveman
        merge, that the result contains block-secrets, redact-secrets, idd-gate,
        idd-nudge, AND the caveman entry (composition check). The plan's wiring test
        seeds no caveman entry and asserts only block-secrets; Task 3 Step 6 adds
        only a `bash -n` syntax check, not a composition assertion.
      fix: >-
        In test_idd_wiring.sh, seed a caveman UserPromptSubmit entry (or run
        ensure_caveman_wiring) before ensure_idd_wiring, then assert the merged
        hooks.json contains caveman + redact-secrets alongside idd-gate/idd-nudge.
      verdict: open
      verdict_at: null
    - id: F-002
      phase: consistency
      severity: WARNING
      section: "Global Constraints (line 19) vs spec Component 3 (line 206)"
      section_hash: null
      fragment: '`.gitignore` already whitelists `!.codex-isolated/hooks/**` and `!.codex-isolated/skills/**`, so the new hooks and skills are tracked with **no `.gitignore` change**.'
      text: >-
        Spec Component 3 lists ".gitignore whitelisting for hooks/idd-*.py,
        skills/check-*/" as a required non-asset change. The plan instead asserts no
        .gitignore change is needed because broad globs already whitelist those
        paths. Verified against the repo: git check-ignore confirms both paths are
        trackable, so the plan is factually correct and the spec is stale on this
        point. Divergence is benign but should be acknowledged.
      fix: >-
        No plan change required; note the spec's .gitignore requirement is already
        satisfied by existing globs. Optionally annotate the spec divergence.
      verdict: open
      verdict_at: null
result_check:
  verdict: OK
  plan_hash: 1c3203e14090a2bf
  last_run: 2026-06-30
chain:
  intent: null
  spec: docs/superpowers/specs/2026-06-30-icodex-idd-integration-design.md
---

# icodex IDD→SDD Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the iclaude IDD→SDD enforcement (4 `check-*` validators + the `idd-gate` / `idd-nudge` hooks + the session ledger) into icodex, with validators as Codex skills, hooks re-pointed at Codex tool names, and a default-on/opt-out `ICODEX_IDD` wiring module mirroring caveman.

**Architecture:** Two ported Python hooks live in `.codex-isolated/hooks/` (shared store, symlinked into every Codex home). A new `lib/idd/idd.sh` merges their `hooks.json` entries into the per-project home `hooks.json` at launch unless `ICODEX_IDD=off`, running after `ensure_caveman_wiring` so it is the final authority on the IDD entries. The 4 validators are Codex skills under `.codex-isolated/skills/check-*/`, invoked from clean-context subagents. A small shared `_codex_paths.py` gives both hooks Codex `apply_patch` path extraction.

**Tech Stack:** Bash (launcher modules + tests), Python 3 (hooks; PyYAML 6.0.1 confirmed present), Codex `hooks.json` schema (PreToolUse / PostToolUse), Codex skills (`SKILL.md`).

**Spec:** `docs/superpowers/specs/2026-06-30-icodex-idd-integration-design.md`

## Global Constraints

- Bash executables: `#!/usr/bin/env bash`, `set -euo pipefail`; tests: `set -uo pipefail`. Two-space indent inside functions/conditionals. Functions `snake_case` (e.g. `ensure_idd_wiring`). Wrapper env vars use the `ICODEX_` prefix.
- Python hooks are **fail-open**: any broken stdin / missing `yaml` / unreachable ledger / internal exception → `exit 0` (gate allows, nudge silent). Never fail-closed (that is `block-secrets.py`'s job).
- Dependency-free: no new runtime dependencies beyond stdlib + the already-present PyYAML.
- Do **not** modify `block-secrets.py`, `redact-secrets.py`, `caveman-hook.py`, or `lib/caveman/caveman.sh`. The IDD code is purely additive.
- `.gitignore` already whitelists `!.codex-isolated/hooks/**` and `!.codex-isolated/skills/**`, so the new hooks and skills are tracked with **no `.gitignore` change**.
- Docs, code comments, and commit messages in English. Commit messages end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- The IDD enforcement is **on by default**, disabled only when `ICODEX_IDD=off`.

## File Structure

| Path | Responsibility | Action |
|------|----------------|--------|
| `.codex-isolated/hooks/_codex_paths.py` | Shared Codex tool path extraction (`apply_patch` patch + `file_path` fields) | Create |
| `.codex-isolated/hooks/idd-gate.py` | PreToolUse phase gate (block/allow), Codex-adapted | Create (port) |
| `.codex-isolated/hooks/idd-nudge.py` | PostToolUse advisory nudge, Codex-adapted | Create (port) |
| `.codex-isolated/skills/check-intent/SKILL.md` | Intent-doc validator | Create (port) |
| `.codex-isolated/skills/check-spec/SKILL.md` | Spec validator | Create (port) |
| `.codex-isolated/skills/check-plan/SKILL.md` | Plan validator | Create (port) |
| `.codex-isolated/skills/check-result/SKILL.md` | Result reconciliation validator | Create (port) |
| `lib/idd/idd.sh` | `ensure_idd_wiring`: default-on/opt-out merge of the two hooks into home `hooks.json` | Create |
| `icodex.sh` | Source `idd/idd` module; call `ensure_idd_wiring` after `ensure_caveman_wiring` | Modify |
| `tests/test_idd_gate.sh` | Gate behaviour (block/allow/fail-open, apply_patch paths) | Create |
| `tests/test_idd_nudge.sh` | Nudge behaviour (emit/silent/fail-open) | Create |
| `tests/test_idd_wiring.sh` | Wiring (default-on merge, opt-out strip, caveman composition) | Create |
| `tests/test_idd_skills.sh` | Skill assets present + frontmatter + chain wiring | Create |

**Source files to copy/port from** (read-only inputs, iclaude install):
- Hooks: `/home/ikeniborn/Documents/Project/iclaude/.nvm-isolated/.claude-isolated/hooks/idd-gate.py`, `idd-nudge.py`
- Commands: `/home/ikeniborn/Documents/Project/iclaude/.nvm-isolated/.claude-isolated/commands/check-{intent,spec,plan,result}.md`
- Reuse pattern: `.codex-isolated/hooks/block-secrets.py` (lines 120–161: `patch_text_from_input`, `path_fields`, `patch_paths`, `PATCH_FILE_RE`).

---

## Task 1: Shared Codex path helper + `idd-gate.py` port

**Files:**
- Create: `.codex-isolated/hooks/_codex_paths.py`
- Create: `.codex-isolated/hooks/idd-gate.py`
- Test: `tests/test_idd_gate.sh`

**Interfaces:**
- Produces (`_codex_paths.py`): `patch_text_from_input(params) -> str`, `path_fields(params) -> list[str]`, `patch_paths(patch: str) -> list[str]`, `extract_paths(tool, params) -> list[str]`.
- Consumes: `idd-gate.py` imports those from `_codex_paths`.

- [ ] **Step 1: Write the failing gate test**

Create `tests/test_idd_gate.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

GATE="$ROOT/.codex-isolated/hooks/idd-gate.py"
assert_exit "gate file exists" 0 test -f "$GATE"

# Build a temp repo CWD with a docs/superpowers tree + a ledger home.
WORK="$(mktemp -d)"; HOME_DIR="$(mktemp -d)"
mkdir -p "$WORK/docs/superpowers/specs" "$WORK/docs/superpowers/plans"

# A spec with a PASSING review block (all phases passed, hash matches body).
SPEC="$WORK/docs/superpowers/specs/2026-06-30-foo-design.md"
write_spec() { # <phase_status>
  local body="# Foo

Body text."
  local hash
  hash="$(printf '%s\n' "$body" | sha256sum | cut -c1-16)"
  cat > "$SPEC" <<EOF
---
review:
  spec_hash: $hash
  phases:
    structure: { status: $1 }
  findings: []
---
$body
EOF
}

# Helper: run the gate from inside WORK with a given JSON payload.
run_gate() { # <json> -> prints exit code
  local code=0
  ( cd "$WORK" && CODEX_HOME="$HOME_DIR" python3 "$GATE" >/dev/null 2>&1 <<<"$1" ) || code=$?
  printf '%s' "$code"
}

# Record ownership: a Write of the spec by session s1 stamps the ledger.
own='{"session_id":"s1","tool_name":"Write","tool_input":{"file_path":"docs/superpowers/specs/2026-06-30-foo-design.md","content":"x"}}'
run_gate "$own" >/dev/null

# 1. Skill writing-plans with a PASSED spec owned by s1 -> allow (exit 0).
write_spec passed
skill='{"session_id":"s1","tool_name":"Skill","tool_input":{"skill":"superpowers:writing-plans"}}'
assert_eq "passed spec allows writing-plans" "0" "$(run_gate "$skill")"

# 2. Skill writing-plans with a NON-passed spec -> block (exit 2).
write_spec pending
assert_eq "pending spec blocks writing-plans" "2" "$(run_gate "$skill")"

# 3. apply_patch creating a plan while spec NOT passed -> block (spec->plan gate).
patch='{"session_id":"s1","tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Add File: docs/superpowers/plans/2026-06-30-foo.md\n+# Plan\n*** End Patch\n"}}'
assert_eq "apply_patch plan create blocks on unpassed spec" "2" "$(run_gate "$patch")"

# 4. Malformed stdin -> fail-open (exit 0).
assert_eq "malformed stdin fail-open" "0" "$(run_gate 'not json')"

# 5. No owned artifact (session s2) -> escape/allow (exit 0).
skill2='{"session_id":"s2","tool_name":"Skill","tool_input":{"skill":"superpowers:writing-plans"}}'
assert_eq "unowned spec does not gate other session" "0" "$(run_gate "$skill2")"

rm -rf "$WORK" "$HOME_DIR"
finish
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash tests/test_idd_gate.sh`
Expected: FAIL at "gate file exists" (file not yet created).

- [ ] **Step 3: Create the shared path helper**

Create `.codex-isolated/hooks/_codex_paths.py`:

```python
#!/usr/bin/env python3
"""Shared Codex tool path extraction for the IDD hooks.

Codex's edit tool is `apply_patch` (its payload carries a `patch` string with
`*** Add/Update/Delete File:` headers), unlike Claude Code's `file_path`-keyed
Edit/Write. These helpers normalise both shapes to a list of touched paths.
Mirrors the predicate already used by block-secrets.py (kept separate so the
secret-guard is never imported for its side effects)."""

import re

PATCH_FILE_RE = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$")


def patch_text_from_input(params):
    if isinstance(params, str):
        return params
    if not isinstance(params, dict):
        return ""
    for key in ("patch", "input", "content", "text"):
        value = params.get(key)
        if isinstance(value, str):
            return value
    return ""


def path_fields(params):
    if not isinstance(params, dict):
        return []
    out = []
    for key in ("file_path", "path", "target_file", "target_path"):
        value = params.get(key)
        if isinstance(value, str):
            out.append(value)
    return out


def patch_paths(patch):
    out = []
    for line in (patch or "").splitlines():
        m = PATCH_FILE_RE.match(line)
        if m:
            out.append(m.group(1).strip())
    return out


def extract_paths(tool, params):
    """All filesystem paths a Write/Edit/apply_patch call touches."""
    paths = list(path_fields(params))
    if tool in ("apply_patch", "Write", "Edit"):
        paths.extend(patch_paths(patch_text_from_input(params)))
    # de-dup, preserve order
    seen, uniq = set(), []
    for p in paths:
        if p not in seen:
            seen.add(p); uniq.append(p)
    return uniq
```

- [ ] **Step 4: Create `idd-gate.py` by copying the source and applying the Codex edits**

Copy the source gate verbatim first:

Run: `cp /home/ikeniborn/Documents/Project/iclaude/.nvm-isolated/.claude-isolated/hooks/idd-gate.py .codex-isolated/hooks/idd-gate.py`

Then apply these exact edits to `.codex-isolated/hooks/idd-gate.py`:

**Edit 4a — import the shared helper.** After the `import subprocess` line near the top, add:

```python
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _codex_paths import extract_paths  # noqa: E402
```

(Place after the existing `import os` so `os.path` is available.)

**Edit 4b — ledger path → CODEX_HOME.** Replace the body of `ledger_path()`:

```python
def ledger_path():
    """Path to the ownership ledger, or None when CODEX_HOME is unset
    (→ ledger unreachable → every session owns nothing → all gates open)."""
    cfg = os.environ.get("CODEX_HOME")
    return os.path.join(cfg, "state", "idd-sessions.json") if cfg else None
```

**Edit 4c — record_ownership: extract all touched paths.** Replace the `if tool in ("Write", "Edit", "MultiEdit"):` branch:

```python
    if tool in ("apply_patch", "Write", "Edit"):
        for path in extract_paths(tool, data.get("tool_input") or {}):
            if _is_artifact(path):
                record_owner(path, sid)
    elif tool == "Skill":
```

**Edit 4d — handle_write: per-path spec→plan and plan→impl gates.** Replace the entire `handle_write` function body (keep the signature) with:

```python
def handle_write(data, tool, sid):
    """Gate downstream-artifact writes (spec→plan creation, plan→impl edits)."""
    params = data.get("tool_input") or {}
    paths = extract_paths(tool, params)
    if not paths:
        sys.exit(0)  # no path → fail-open

    for path in paths:
        # spec→plan: creation of a plan file (Write or apply_patch Add File).
        if _under(path, PLANS_DIR) and path.endswith(".md"):
            content = patch_or_content(params)
            spec = resolve_spec_from_chain(content) or resolve_candidate(SPEC_RULE, sid)
            if spec is not None:
                reason = evaluate_gate(spec, SPEC_RULE)
                if reason is not None:
                    block(spec, reason, SPEC_RULE["fix"])
            continue

        # plan→impl: editing a file outside docs/superpowers/.
        if not _under(path, DOCS_ROOT):
            plan = resolve_candidate(PLAN_RULE, sid)
            if plan is None:
                continue
            if not fresh(plan, IMPL_GATE_FRESH_SECONDS):
                continue
            reason = evaluate_gate(plan, PLAN_RULE)
            if reason is not None:
                block(plan, reason, PLAN_RULE["fix"])

    sys.exit(0)
```

And add this helper above `handle_write`:

```python
def patch_or_content(params):
    """The new-file body for chain resolution: apply_patch patch text or Write content."""
    return patch_text_from_input(params) if not isinstance(params, str) else params
```

Add `from _codex_paths import extract_paths, patch_text_from_input` (extend Edit 4a's import).

**Edit 4e — dispatch apply_patch.** In `main()`, replace `elif tool in ("Write", "Edit", "MultiEdit"):` with:

```python
        elif tool in ("apply_patch", "Write", "Edit"):
```

**Edit 4f — reword block messages to skill invocation.** In `block()`, replace the `Action:` line so it reads:

```python
        "Action: dispatch a clean-context subagent to invoke the %s skill on %s\n"
        "(check-runner protocol: run the validator in the subagent, collect\n"
        "verdicts in the main session), resolve the CRITICAL findings, then retry.\n"
```

and change the `GATE_MAP` / `SPEC_RULE` / `PLAN_RULE` `fix` values from `"/check-intent"`, `"/check-spec"`, `"/check-plan"`, `"/check-result"` to `"check-intent"`, `"check-spec"`, `"check-plan"`, `"check-result"` (drop the leading slash — they are skill names now).

- [ ] **Step 5: Run the gate test, verify it passes**

Run: `bash tests/test_idd_gate.sh`
Expected: PASS for all assertions; final line `PASS=… FAIL=0`.

- [ ] **Step 6: Commit**

```bash
git add .codex-isolated/hooks/_codex_paths.py .codex-isolated/hooks/idd-gate.py tests/test_idd_gate.sh
git commit -m "feat(idd): port idd-gate PreToolUse phase gate to Codex

Codex-adapted: CODEX_HOME ledger, apply_patch path extraction via a shared
_codex_paths helper, apply_patch/Write/Edit dispatch, skill-invocation block
messages. Fail-open preserved.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `idd-nudge.py` port

**Files:**
- Create: `.codex-isolated/hooks/idd-nudge.py`
- Test: `tests/test_idd_nudge.sh`

**Interfaces:**
- Consumes: `_codex_paths.extract_paths` (from Task 1).
- Produces: a PostToolUse hook that prints `{"hookSpecificOutput": {"hookEventName":"PostToolUse","additionalContext": …}}` when an unvalidated IDD artifact was just written, else nothing.

- [ ] **Step 1: Write the failing nudge test**

Create `tests/test_idd_nudge.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

NUDGE="$ROOT/.codex-isolated/hooks/idd-nudge.py"
assert_exit "nudge file exists" 0 test -f "$NUDGE"

WORK="$(mktemp -d)"
mkdir -p "$WORK/docs/superpowers/specs"
SPEC="docs/superpowers/specs/2026-06-30-bar-design.md"
printf '# Bar\n\nBody.\n' > "$WORK/$SPEC"

run_nudge() { # <json> -> prints stdout
  ( cd "$WORK" && python3 "$NUDGE" 2>/dev/null <<<"$1" )
}

# 1. Write of an unvalidated spec -> nudge mentions check-spec.
w='{"tool_name":"Write","tool_input":{"file_path":"'"$SPEC"'","content":"x"}}'
out="$(run_nudge "$w")"
assert_contains "nudge emitted for new spec" "$out" "additionalContext"
assert_contains "nudge names check-spec" "$out" "check-spec"

# 2. apply_patch Add File of the spec -> also nudges.
p='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Add File: '"$SPEC"'\n+# Bar\n*** End Patch\n"}}'
assert_contains "nudge emitted for apply_patch spec" "$(run_nudge "$p")" "check-spec"

# 3. Write of a non-artifact path -> silent.
n='{"tool_name":"Write","tool_input":{"file_path":"README.md","content":"x"}}'
assert_eq "non-artifact silent" "" "$(run_nudge "$n")"

# 4. Malformed stdin -> silent, exit 0.
assert_eq "malformed stdin silent" "" "$(run_nudge 'not json')"

rm -rf "$WORK"
finish
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash tests/test_idd_nudge.sh`
Expected: FAIL at "nudge file exists".

- [ ] **Step 3: Create `idd-nudge.py` by copying the source and applying the Codex edits**

Run: `cp /home/ikeniborn/Documents/Project/iclaude/.nvm-isolated/.claude-isolated/hooks/idd-nudge.py .codex-isolated/hooks/idd-nudge.py`

Apply these exact edits to `.codex-isolated/hooks/idd-nudge.py`:

**Edit 3a — import the shared helper.** After `import fnmatch`, add:

```python
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _codex_paths import extract_paths  # noqa: E402
```

**Edit 3b — fix values are skill names.** In `ARTIFACT_RULES`, change each `"fix": "/check-intent"` / `"/check-spec"` / `"/check-plan"` to `"check-intent"` / `"check-spec"` / `"check-plan"` (drop the leading slash).

**Edit 3c — reword the nudge message.** In `nudge()`, replace the message body with:

```python
    msg = (
        "IDD artifact %s was just written and has not passed validation yet. "
        "Dispatch a clean-context subagent to invoke the %s skill on it "
        "(check-runner protocol), then collect verdicts in the main session, so "
        "the IDD gate is open before the next chain transition." % (path, fix)
    )
```

**Edit 3d — match Write and apply_patch, per touched path.** Replace the body of `main()` (inside the `try:`) so it iterates extracted paths:

```python
        tool = data.get("tool_name")
        if tool not in ("Write", "apply_patch"):
            sys.exit(0)
        for path in extract_paths(tool, data.get("tool_input") or {}):
            rule = rule_for(path)
            if rule is None:
                continue
            if not os.path.exists(path):
                continue
            if validated(path, rule):
                continue
            nudge(path, rule["fix"])
            sys.exit(0)  # one nudge per write is enough
        sys.exit(0)
```

(The leading comment block in the source that says "matcher `Write`" should be updated to "matcher `apply_patch|Write`".)

- [ ] **Step 4: Run the nudge test, verify it passes**

Run: `bash tests/test_idd_nudge.sh`
Expected: PASS; `PASS=… FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add .codex-isolated/hooks/idd-nudge.py tests/test_idd_nudge.sh
git commit -m "feat(idd): port idd-nudge PostToolUse hook to Codex

Match apply_patch|Write, extract artifact paths from the patch, reword the
suggestion to a check-runner subagent invoking the check-* skill. Advisory,
fail-open, silent once the artifact validates.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Wiring — `lib/idd/idd.sh` + `icodex.sh`

**Files:**
- Create: `lib/idd/idd.sh`
- Modify: `icodex.sh` (module source list; call after `ensure_caveman_wiring`)
- Test: `tests/test_idd_wiring.sh`

**Interfaces:**
- Consumes: `$ICODEX_HOME_DIR`, `$ICODEX_SHARED_DIR` (set by `lib/config/isolated.sh` / `lib/core/init.sh`), `log_warn` (from `lib/core/logging.sh`).
- Produces: `ensure_idd_wiring` (no args; reads `ICODEX_IDD`).

- [ ] **Step 1: Write the failing wiring test**

Create `tests/test_idd_wiring.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

assert_exit "idd module exists" 0 test -f "$ROOT/lib/idd/idd.sh"

# Minimal harness: stub log_warn, set dirs, source the module.
HOME_DIR="$(mktemp -d)"
export ICODEX_SHARED_DIR="$ROOT/.codex-isolated"
export ICODEX_HOME_DIR="$HOME_DIR"
log_warn() { :; }
# shellcheck source=/dev/null
source "$ROOT/lib/idd/idd.sh"

# Seed the home hooks.json as a symlink to the shared base (as isolated.sh does).
ln -s "$ICODEX_SHARED_DIR/hooks.json" "$HOME_DIR/hooks.json"

# 1. Default (ICODEX_IDD unset) -> both entries merged, valid JSON.
unset ICODEX_IDD || true
ensure_idd_wiring
hooks="$(cat "$HOME_DIR/hooks.json")"
assert_contains "default-on adds idd-gate"  "$hooks" "idd-gate.py"
assert_contains "default-on adds idd-nudge" "$hooks" "idd-nudge.py"
assert_exit "result is valid json" 0 python3 -c "import json,sys; json.load(open('$HOME_DIR/hooks.json'))"
assert_contains "base block-secrets preserved" "$hooks" "block-secrets.py"

# 2. Idempotent: a second run does not duplicate the gate entry.
ensure_idd_wiring
count="$(grep -c "idd-gate.py" "$HOME_DIR/hooks.json")"
assert_eq "idempotent (one idd-gate entry)" "1" "$count"

# 3. Opt-out: ICODEX_IDD=off strips both entries.
export ICODEX_IDD=off
ensure_idd_wiring
hooks_off="$(cat "$HOME_DIR/hooks.json")"
assert_eq "opt-out removes idd-gate"  "0" "$(grep -c 'idd-gate.py'  <<<"$hooks_off")"
assert_eq "opt-out removes idd-nudge" "0" "$(grep -c 'idd-nudge.py' <<<"$hooks_off")"
assert_contains "opt-out keeps block-secrets" "$hooks_off" "block-secrets.py"

rm -rf "$HOME_DIR"
finish
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash tests/test_idd_wiring.sh`
Expected: FAIL at "idd module exists".

- [ ] **Step 3: Create `lib/idd/idd.sh`**

```bash
#!/usr/bin/env bash
# Wire the IDD→SDD phase gate + nudge into the per-project Codex home at launch.
#
# IDD is ON BY DEFAULT and governed by ICODEX_IDD (opt-out: disabled only when
# ICODEX_IDD=off). When enabled, the idd-gate (PreToolUse) and idd-nudge
# (PostToolUse) entries are merged into $ICODEX_HOME_DIR/hooks.json; when opted
# out, they are stripped. Mirrors lib/caveman/caveman.sh and MUST run after
# ensure_caveman_wiring so it is the final authority on the IDD entries.

# Echo "off" when opted out, else empty (enabled).
_idd_disabled() {
  [[ "$(printf '%s' "${ICODEX_IDD:-}" | tr '[:upper:]' '[:lower:]')" == "off" ]]
}

# Rebuild $ICODEX_HOME_DIR/hooks.json from its current content with the IDD
# entries either present (enable=1) or absent (enable=0). Idempotent.
_idd_apply_hooks_json() { # <enable 0|1>
  local home="$ICODEX_HOME_DIR/hooks.json" enable="$1" tmp
  [[ -e "$home" || -L "$home" ]] || return 0
  tmp="$(mktemp)"
  python3 - "$home" "$enable" > "$tmp" <<'PY'
import json, sys
home, enable = sys.argv[1], sys.argv[2] == "1"
with open(home, encoding="utf-8") as fh:
    cfg = json.load(fh)
hooks = cfg.setdefault("hooks", {})
GATE = 'python3 "$CODEX_HOME/hooks/idd-gate.py"'
NUDGE = 'python3 "$CODEX_HOME/hooks/idd-nudge.py"'

def strip(event, cmd):
    arr = hooks.get(event, [])
    kept = [e for e in arr
            if not any(h.get("command") == cmd for h in e.get("hooks", []))]
    if kept:
        hooks[event] = kept
    elif event in hooks:
        del hooks[event]

def present(event, cmd):
    return any(h.get("command") == cmd
               for e in hooks.get(event, []) for h in e.get("hooks", []))

def add(event, matcher, cmd, status):
    if present(event, cmd):
        return
    hooks.setdefault(event, []).append({
        "matcher": matcher,
        "hooks": [{"type": "command", "command": cmd,
                   "timeout": 30, "statusMessage": status}],
    })

# Always strip first so re-runs and opt-out converge deterministically.
strip("PreToolUse", GATE)
strip("PostToolUse", NUDGE)
if enable:
    add("PreToolUse", "Skill|apply_patch|Write|Edit", GATE, "IDD phase gate")
    add("PostToolUse", "apply_patch|Write", NUDGE, "IDD nudge")

json.dump(cfg, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
  if [[ -L "$home" || ! -f "$home" ]] || ! cmp -s "$tmp" "$home"; then
    rm -f "$home"
    cat "$tmp" > "$home"
  fi
  rm -f "$tmp"
}

# Orchestrate IDD wiring on the launch path. Default-on; off only on ICODEX_IDD=off.
ensure_idd_wiring() {
  if _idd_disabled; then
    _idd_apply_hooks_json 0
  else
    _idd_apply_hooks_json 1
  fi
}
```

- [ ] **Step 4: Run the wiring test, verify it passes**

Run: `bash tests/test_idd_wiring.sh`
Expected: PASS; `PASS=… FAIL=0`.

- [ ] **Step 5: Wire into `icodex.sh`**

Edit the module source loop in `icodex.sh` — add `idd/idd` after `plugin/superpowers`:

```bash
for m in core/logging core/init core/validation command/args \
         binary/detect binary/lockfile binary/install \
         config/isolated config/permissions config/sandbox config/env proxy/proxy symlink/symlink \
         plugin/superpowers caveman/caveman idd/idd launcher/launch; do
```

(If `caveman/caveman` is not already in the loop on this branch, add it too — it is sourced on `main`. Match the existing list; only insert the missing modules.)

Then, in `main()`, add the call immediately after `ensure_caveman_wiring`:

```bash
  ensure_superpowers_wiring
  ensure_caveman_wiring
  ensure_idd_wiring
```

- [ ] **Step 6: Verify the full hook pipeline composes with caveman**

Run:
```bash
bash tests/test_idd_wiring.sh && bash -n icodex.sh && echo "icodex.sh syntax OK"
```
Expected: wiring test PASS; `icodex.sh syntax OK`.

- [ ] **Step 7: Commit**

```bash
git add lib/idd/idd.sh icodex.sh tests/test_idd_wiring.sh
git commit -m "feat(idd): wire idd-gate/idd-nudge into the home hooks.json

Add lib/idd/idd.sh with ensure_idd_wiring (default-on; opt-out via
ICODEX_IDD=off), merging the gate/nudge entries into the per-project home
hooks.json after ensure_caveman_wiring so the two compose.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Validator skills (`check-intent` / `check-spec` / `check-plan` / `check-result`)

**Files:**
- Create: `.codex-isolated/skills/check-intent/SKILL.md`
- Create: `.codex-isolated/skills/check-spec/SKILL.md`
- Create: `.codex-isolated/skills/check-plan/SKILL.md`
- Create: `.codex-isolated/skills/check-result/SKILL.md`
- Test: `tests/test_idd_skills.sh`

**Interfaces:**
- Each skill reads/writes only the artifact `review:` / `result_check:` frontmatter and emits an HTML chain report via the `html-report` skill (already present). The frontmatter keys and phase names below MUST match what `idd-gate.py`'s `GATE_MAP` expects (verbatim from the source — do not rename).

Per-skill port table (source → SKILL.md):

| Skill | Source command | Phases (gating) | Hash key / block | HTML `tab` | Chain field(s) written |
|-------|----------------|-----------------|------------------|-----------|------------------------|
| check-intent | `commands/check-intent.md` | structure, completeness, clarity, consistency (+ alignment advisory) | `review.intent_hash` | `intent` | none (chain root) |
| check-spec | `commands/check-spec.md` | structure, coverage, clarity, consistency | `review.spec_hash` | `spec` | `chain.intent` |
| check-plan | `commands/check-plan.md` | structure, coverage, dependencies, verifiability, consistency | `review.plan_hash` (+ `spec_hash`) | `plan` | `chain.intent`, `chain.spec` |
| check-result | `commands/check-result.md` | reconciliation vs git diff | `result_check.plan_hash` + `verdict` | `result` | reads `chain.intent`, `chain.spec` |

- [ ] **Step 1: Write the failing skills test**

Create `tests/test_idd_skills.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

SK="$ROOT/.codex-isolated/skills"

check_skill() { # <name> <expected hash-key token> <expected tab token>
  local name="$1" key="$2" tab="$3" f="$SK/$1/SKILL.md"
  assert_exit "$name SKILL.md exists" 0 test -f "$f"
  [[ -f "$f" ]] || return 0
  local body; body="$(cat "$f")"
  assert_contains "$name has name frontmatter" "$body" "name: $name"
  assert_contains "$name has a description"    "$body" "description:"
  assert_contains "$name references $key"      "$body" "$key"
  assert_contains "$name targets tab: $tab"    "$body" "tab: $tab"
  # frontmatter parses as YAML
  assert_exit "$name frontmatter parses" 0 python3 - "$f" <<'PY'
import sys, yaml
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert lines[0].strip() == "---"
fm = []
for ln in lines[1:]:
    if ln.strip() == "---": break
    fm.append(ln)
d = yaml.safe_load("\n".join(fm))
assert isinstance(d, dict) and d.get("name") and d.get("description")
PY
}

check_skill check-intent intent_hash intent
check_skill check-spec   spec_hash   spec
check_skill check-plan   plan_hash   plan
check_skill check-result plan_hash   result

finish
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash tests/test_idd_skills.sh`
Expected: FAIL at "check-intent SKILL.md exists".

- [ ] **Step 3: Build each SKILL.md (repeat for all four)**

For each skill, create the directory and assemble `SKILL.md` = **frontmatter** + a one-paragraph **execution-context note** + the **ported command body**:

1. `mkdir -p .codex-isolated/skills/check-<x>`
2. Write the frontmatter (example for `check-spec`; adapt `name` and the trigger phrases per skill):

```markdown
---
name: check-spec
description: >-
  Validate a specification doc (docs/superpowers/specs/*-design.md) against the
  IDD→SDD phase model before writing-plans. Triggers on "/check-spec",
  "check the spec", "validate spec". Run from a clean-context subagent after a
  spec is written; reports verdicts to the main session. Skip for hotfixes.
---

## Execution context

This validator runs in a **clean-context subagent** (the check-runner protocol):
the subagent runs the deterministic phases on the artifact body, writes findings
into the artifact's `review:` frontmatter with `verdict: open`, and returns the
phase statuses + findings to the main session, which collects verdicts with the
user. The advisory `alignment`/`coverage`-context steps are skipped silently when
their inputs (conversation tasks, `iwiki`/`lat_*` MCP) are unavailable. Never
edit the artifact body — only its `review:` frontmatter.
```

3. Append the **body of the source command** copied verbatim from
   `commands/check-<x>.md`, with exactly these adjustments:
   - Remove the trailing `$ARGUMENTS` slash-command token; where the body says
     "passed in `$ARGUMENTS`", read the file path from the skill's invocation
     argument instead (the surrounding "Step 1. Determine scope" logic already
     handles auto-resolution when no path is given).
   - Leave every Bash hashing pipeline, the `review:`/`result_check:` frontmatter
     contract, the closed phase checklists, the `chain:` handling, and the final
     `html-report` Skill call **unchanged** (Codex has the Bash tool and the
     `html-report` skill).
   - Keep the report language Russian (parity).

Apply to all four: `check-intent`, `check-spec`, `check-plan`, `check-result`
(using each one's source file and the row in the port table above).

- [ ] **Step 4: Run the skills test, verify it passes**

Run: `bash tests/test_idd_skills.sh`
Expected: PASS; `PASS=… FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add .codex-isolated/skills/check-intent .codex-isolated/skills/check-spec \
        .codex-isolated/skills/check-plan .codex-isolated/skills/check-result \
        tests/test_idd_skills.sh
git commit -m "feat(idd): add check-intent/spec/plan/result validator skills

Port the four iclaude /check-* commands to Codex skills (clean-context
subagent validators). Frontmatter triggers replace the slash invocation; the
phase algorithm, frontmatter contract, and html-report call are verbatim.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Full suite + docs

**Files:**
- Modify: `docs/wiki/` (via the iwiki skill)

- [ ] **Step 1: Run the entire Bash test suite**

Run: `for t in tests/test_*.sh; do echo "== $t =="; bash "$t" || exit 1; done`
Expected: every file ends `PASS=… FAIL=0`; loop exits 0. Confirms the IDD tests pass and nothing regressed (caveman, codex-hooks, etc.).

- [ ] **Step 2: Confirm the standalone-skill activation assumption (spec open item)**

The spec flags that standalone `.codex-isolated/skills/` activation in Codex is unverified. Verify it: launch a Codex session in this repo and check that the `check-spec` skill is discoverable (e.g. its trigger fires, or it appears in the skill list). If it is NOT surfaced, STOP and report — wiring standalone-skill discovery is then a prerequisite to track separately (the hooks still function; only the validators-as-skills depend on this).

Run (manual): `! ./icodex.sh` then, in the session, ask it to "check the spec docs/superpowers/specs/2026-06-30-icodex-idd-integration-design.md".
Expected: the `check-spec` skill activates. Record the outcome.

- [ ] **Step 3: Update the project wiki**

Invoke `iwiki:iwiki-ingest` for the new surface, then lint:
- `Skill(skill="iwiki:iwiki-ingest", args="lib/idd/idd.sh")`
- `Skill(skill="iwiki:iwiki-ingest", args=".codex-isolated/hooks/idd-gate.py")`
- `Skill(skill="iwiki:iwiki-lint")` — fix any broken `[[refs]]`, orphans, or stale pages it reports.

- [ ] **Step 4: Commit docs**

```bash
git add docs/wiki
git commit -m "docs(wiki): document the IDD→SDD integration

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Full parity (4 validators + 2 hooks + ledger) → Tasks 1, 2, 4; ledger preserved verbatim in the gate port (Task 1).
- Commands → Codex skills → Task 4.
- On-by-default / `ICODEX_IDD` opt-out → Task 3 (`_idd_disabled`, `ensure_idd_wiring`).
- Clean-context subagent validators → Task 4 frontmatter "Execution context"; gate/nudge messages (Tasks 1, 2).
- Hooks port: apply_patch extraction, tool remap, CODEX_HOME ledger, message reword, fail-open → Task 1 (Edits 4a–4f) + Task 2 (Edits 3a–3d).
- `lib/idd/idd.sh` after `ensure_caveman_wiring` → Task 3 Steps 3, 5.
- Tests for gate / nudge / wiring → Tasks 1, 2, 3; plus skills structural test (Task 4).
- Risk: Skill-PreToolUse uncertainty → the gate's Write/apply_patch path is load-bearing and fully tested (Task 1 Steps 1, 3 cover apply_patch); the Skill matcher is registered (Task 3) but not relied on for the tested behaviour.
- Risk: standalone-skill activation → Task 5 Step 2 explicit verification gate.

**Placeholder scan:** none — every code step shows complete file content or exact before/after edits; the skill-body port references the verbatim source plus an enumerated edit list.

**Type/name consistency:** `extract_paths` / `patch_text_from_input` (Task 1) consumed by Tasks 1–2; hook command strings `python3 "$CODEX_HOME/hooks/idd-gate.py"` / `idd-nudge.py` identical in Task 3 wiring and the registered matchers; frontmatter keys (`intent_hash`/`spec_hash`/`plan_hash`/`result_check`) consistent between the gate `GATE_MAP` (unchanged source) and the Task 4 port table.
