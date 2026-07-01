---
review:
  plan_hash: c02ac3fd34f8cc0a
  last_run: 2026-07-01
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings:
    - id: F-001
      phase: coverage
      severity: WARNING
      section: "Task 3: check-chain + fix-intent skills"
      section_hash: 24ff0800ca21ca61
      fragment: "assert_contains \"check-chain covers result stage\" \"$body\" \"result_check\""
      text: "Spec §Tests (design line 183) requires test_idd_skills.sh to assert the four `tab:` tokens intent/spec/plan/result for check-chain; Task 3 Step 1 asserts `result_check` plus the three hash keys instead and includes no `tab:` check. Coverage of the underlying requirement (skills test validates the unified layout) is preserved, but the specific spec assertion is not implemented. Note: the iclaude source contains only a single templated `tab: <stage>` token, so asserting four literal `tab:` tokens would fail — the plan's substitution is arguably the more correct choice, and the spec text was imprecise."
      fix: "Either (a) update the plan/spec to agree — keep the `result_check` assertion and drop the spec's four-`tab:`-tokens wording, or (b) if the spec intent must be honored, add an assert that check-chain's body contains the `tab:` token. Recommend (a) since the source has a single templated tab token."
      verdict: fixed
      verdict_at: 2026-07-01
      resolution: "Applied (a): spec §Tests reworded to drop the four-`tab:`-tokens requirement and assert stage coverage via the hash keys + result_check; spec_hash refreshed. Plan and spec now agree."
chain:
  intent: null
  spec: docs/superpowers/specs/2026-07-01-icodex-idd-unify-design.md
---
# icodex IDD-chain unification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace icodex's split IDD architecture (2 hooks + 4 check-* skills + `intent`) with iclaude's unified shape — one `chain-gate.py`, one `check-chain` skill, one `fix-intent` skill — keeping the full test suite green.

**Architecture:** Port the unified iclaude `chain-gate.py` (single file, gate on PreToolUse / nudge on PostToolUse) and adapt it to Codex: ledger under `CODEX_HOME`, `apply_patch`/`Write`/`Edit` path extraction via `_codex_paths`, `chain.spec` resolution from an `apply_patch` Add File body, and the fail-closed-on-malformed-frontmatter hardening the icodex tests assert. The two roles are selected by a `--post` argv flag injected by the wiring, not by `hook_event_name`. Port the `check-chain` and `fix-intent` skills near-verbatim from iclaude with small Codex adaptations. Rewire `lib/idd/idd.sh`, update the four IDD tests, and rewrite `docs/wiki/idd.md`.

**Tech Stack:** Python 3 (stdlib + `pyyaml`, already a dependency), Bash test harness (`tests/helpers.sh`), Codex hooks.json merge in `lib/idd/idd.sh`.

## Global Constraints

- Python hooks: stdlib only except `pyyaml` (already used by the deleted hooks). No new dependencies.
- Fail-open policy: any internal exception or malformed hook stdin → exit 0 (gate allows, nudge silent). Malformed artifact *frontmatter* is the one fail-closed case (gate blocks / nudge emits).
- Preserve icodex hardening exactly: malformed/unclosed/invalid-YAML frontmatter, non-dict `phases`, non-list `findings` → block (gate) / nudge. The tests assert this.
- Body-hash pipeline shells to bash with the path passed as `argv` (`bash -c '… "$1" …' -- "$path"`) — never string-interpolated — so shell metacharacters in a filename never execute.
- `review:` frontmatter `phases` is a **dict** keyed by phase name (`structure: { status: passed }`), never a list. Gate and `check-chain` must agree on this shape.
- `fix` remediation strings use the Codex skill form: `check-chain <stage>` (skill name + argument, no leading slash).
- Hook / skill / test comments and docs in English. Conversation in Russian.
- Do not change IDD validation semantics (checklists, hashing, severities, ledger ownership). Shape + Codex adaptation only.
- Branch `dev-idd-unify` (already created). Commit per task. Do not touch main.

## File Structure

```
.codex-isolated/hooks/chain-gate.py     CREATE  unified gate (Pre) + nudge (Post)
.codex-isolated/hooks/idd-gate.py       DELETE  (already removed on disk; stage it)
.codex-isolated/hooks/idd-nudge.py      DELETE  (already removed on disk; stage it)
.codex-isolated/skills/check-chain/SKILL.md   CREATE  unified validator (4 profiles)
.codex-isolated/skills/fix-intent/SKILL.md    CREATE  intent capture
.codex-isolated/skills/check-{intent,spec,plan,result}/  DELETE (staged)
.codex-isolated/skills/intent/          DELETE  (staged)
lib/idd/idd.sh                          MODIFY  wire chain-gate.py Pre + Post(--post), strip legacy
tests/test_idd_gate.sh                  MODIFY  GATE path → chain-gate.py
tests/test_idd_nudge.sh                 MODIFY  NUDGE → chain-gate.py --post; check-spec → check-chain
tests/test_idd_wiring.sh                MODIFY  idd-gate/idd-nudge → chain-gate.py (+ --post)
tests/test_idd_skills.sh                MODIFY  4 check-* → check-chain + fix-intent
.codex-isolated/AGENTS.md               VERIFY  no stale check-*/idd-gate refs (mostly pre-migrated)
docs/wiki/idd.md                        MODIFY  unified architecture
docs/TODO.md                            DONE    row already opened (icodex-idd-unify)
```

Source files to copy from (read-only reference on this machine):
- iclaude hook: `/home/ikeniborn/Documents/Project/iclaude/.nvm-isolated/.claude-isolated/hooks/chain-gate.py`
- iclaude check-chain: `/home/ikeniborn/Documents/Project/iclaude/.nvm-isolated/.claude-isolated/skills/check-chain/SKILL.md`
- iclaude fix-intent: `/home/ikeniborn/Documents/Project/iclaude/.nvm-isolated/.claude-isolated/skills/fix-intent/SKILL.md`
- Codex adaptation reference (deleted, read from git): `git show HEAD~2:.codex-isolated/hooks/idd-gate.py` and `…idd-nudge.py` (or any commit before the working-tree deletion).

---

## Task 1: chain-gate.py — unified gate + nudge hook

**Files:**
- Create: `.codex-isolated/hooks/chain-gate.py`
- Modify: `tests/test_idd_gate.sh` (line 6)
- Modify: `tests/test_idd_nudge.sh` (lines 6, and every `check-spec` assertion + the `run_nudge` invocation)
- Delete (stage): `.codex-isolated/hooks/idd-gate.py`, `.codex-isolated/hooks/idd-nudge.py`

**Interfaces:**
- Consumes: `_codex_paths.extract_paths(tool, params)` and `_codex_paths.patch_text_from_input(params)` (kept module, unchanged).
- Produces: an executable hook. PreToolUse (no flag): exit 0 allow / exit 2 block. PostToolUse (`--post`): exit 0 always, JSON `hookSpecificOutput.additionalContext` on stdout = nudge, empty stdout = silent. Reads the `review:`/`result_check:` frontmatter contract that `check-chain` writes.

- [ ] **Step 1: Point the gate test at the new file**

Edit `tests/test_idd_gate.sh` line 6:

```bash
GATE="$ROOT/.codex-isolated/hooks/chain-gate.py"
```

(was `.../idd-gate.py`). No other line changes — the gate is invoked without `--post`, so `main()` resolves the PreToolUse branch.

- [ ] **Step 2: Point the nudge test at the new file and the unified skill name**

Edit `tests/test_idd_nudge.sh`:

Line 6:
```bash
NUDGE="$ROOT/.codex-isolated/hooks/chain-gate.py"
```

The `run_nudge` helper must pass the `--post` flag so the nudge branch is selected:
```bash
run_nudge() { # <json> -> prints stdout
  ( cd "$WORK" && python3 "$NUDGE" --post 2>/dev/null <<<"$1" )
}
```

Replace every expected fix token `check-spec` with `check-chain` (7 occurrences: the case-1 `assert_contains "nudge names check-spec"`, case-2, case-6, and the four case-7 asserts). Example for case 1:
```bash
assert_contains "nudge names check-chain" "$out" "check-chain"
```
Apply the same `check-spec` → `check-chain` substitution to cases 2, 6, 7 (leave the human-readable assert labels sensible, e.g. "nudge emitted for apply_patch spec" can stay).

- [ ] **Step 3: Run both tests to verify they fail (file missing)**

Run:
```bash
bash tests/test_idd_gate.sh; bash tests/test_idd_nudge.sh
```
Expected: both FAIL fast on the first assertion (`gate file exists` / `nudge file exists`) because `chain-gate.py` does not exist yet.

- [ ] **Step 4: Create `.codex-isolated/hooks/chain-gate.py`**

Create the file with exactly this content:

```python
#!/usr/bin/env python3
"""
IDD→SDD chain gate — unified PreToolUse gate + PostToolUse nudge (Codex).

One hook file, two roles selected by argv:
  (no flag) PreToolUse  → gate. Block (exit 2) an invalid chain transition until the
            upstream artifact passes validation.
  --post    PostToolUse → nudge. After an intent/spec/plan artifact is written and is
            not yet validated, suggest the check-chain skill via additionalContext.

Replaces the split idd-gate.py + idd-nudge.py. Codex adaptation of the iclaude
chain-gate.py: ledger under CODEX_HOME, apply_patch/Write/Edit path extraction via
_codex_paths, chain.spec resolution from an apply_patch Add File body, and the
fail-closed-on-malformed-frontmatter hardening the icodex test-suite asserts.

The hook only GATES/NUDGES; it never validates. Validation is the check-chain skill
run in a clean-context subagent; verdicts are collected in the main session.
Communication is via frontmatter review:/result_check:.

Session scoping — the gate resolves a candidate ONLY among artifacts owned by the
current session (session_id), recorded in $CODEX_HOME/state/idd-sessions.json. A
session that did not create an artifact is not gated by it. No session_id / no ledger
→ fail-open.

Exit codes:
  0 — allow (gate) / silent-or-nudge (nudge)
  2 — block (gate only)

Fail-open: any internal exception → exit 0. A bug here must never break a real tool
call. (This is the opposite of block-secrets.py, which is fail-closed.)
"""

import sys
import json
import os
import glob
import time
import subprocess
import fnmatch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _codex_paths import extract_paths, patch_text_from_input  # noqa: E402

DOCS_ROOT = "docs/superpowers"
PLANS_DIR = os.path.join(DOCS_ROOT, "plans")

BLOCK_ON = {"CRITICAL"}
IMPL_GATE_FRESH_SECONDS = 7200  # 2h: only a freshly edited plan gates code edits

# Sentinel returned by the frontmatter parser when the YAML is malformed. Cannot
# collide with a real key (double-underscore name is not valid document content here).
MALFORMED_FRONTMATTER_KEY = "__malformed_frontmatter__"

# One rule per stage: dir + glob (artifact), state block + body-hash key (frontmatter
# contract), fix (remediation shown on block/nudge — Codex skill form: name + stage arg).
STAGE_RULES = {
    "intent": {"dir": "intents", "glob": "*-intent.md", "block": "review",
               "hash_key": "intent_hash", "fix": "check-chain intent"},
    "spec":   {"dir": "specs", "glob": "*-design.md", "block": "review",
               "hash_key": "spec_hash", "fix": "check-chain spec"},
    "plan":   {"dir": "plans", "glob": "*.md", "block": "review",
               "hash_key": "plan_hash", "fix": "check-chain plan"},
    "result": {"dir": "plans", "glob": "*.md", "block": "result_check",
               "hash_key": "plan_hash", "fix": "check-chain result"},
}

# PreToolUse skill → stage rule. Keys are the skill-name suffix after the last ':'.
GATE_MAP = {
    "brainstorming": STAGE_RULES["intent"],
    "writing-plans": STAGE_RULES["spec"],
    "executing-plans": STAGE_RULES["plan"],
    "subagent-driven-development": STAGE_RULES["plan"],
    "finishing-a-development-branch": STAGE_RULES["result"],
}

SPEC_RULE = STAGE_RULES["spec"]
PLAN_RULE = STAGE_RULES["plan"]

# PostToolUse nudge rules (artifact-keyed). result is excluded — it needs git diff + a
# plan path and runs at branch finish, covered by the gate.
NUDGE_RULES = [STAGE_RULES["intent"], STAGE_RULES["spec"], STAGE_RULES["plan"]]

# ── session-ownership ledger ────────────────────────────────────────────
LEDGER_MAX_AGE_SECONDS = 7 * 24 * 3600
ARTIFACT_DIRS = ("intents", "specs", "plans")
CLAIM_SKILLS = {"executing-plans", "subagent-driven-development"}


def ledger_path():
    cfg = os.environ.get("CODEX_HOME")
    return os.path.join(cfg, "state", "idd-sessions.json") if cfg else None


def load_ledger():
    path = ledger_path()
    if not path or not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, ValueError, OSError):
        return {}
    if not isinstance(data, dict):
        return {}
    now = time.time()
    out = {}
    for key, val in data.items():
        if not isinstance(val, dict) or not os.path.exists(key):
            continue
        if now - val.get("ts", 0) > LEDGER_MAX_AGE_SECONDS:
            continue
        out[key] = val
    return out


def record_owner(path, sid):
    lp = ledger_path()
    if not lp or not sid:
        return
    ledger = load_ledger()
    ledger[os.path.abspath(path)] = {"session": sid, "ts": int(time.time())}
    try:
        os.makedirs(os.path.dirname(lp), exist_ok=True)
        tmp = "%s.%d.tmp" % (lp, os.getpid())
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(ledger, f)
        os.replace(tmp, lp)
    except OSError:
        pass


def owns(path, sid, ledger):
    if not sid:
        return False
    entry = ledger.get(os.path.abspath(path))
    return isinstance(entry, dict) and entry.get("session") == sid


def _is_artifact(path):
    return any(_under(path, os.path.join(DOCS_ROOT, d)) for d in ARTIFACT_DIRS)


def record_ownership(data, tool, sid):
    if tool in ("apply_patch", "Write", "Edit"):
        for path in extract_paths(tool, data.get("tool_input") or {}):
            if _is_artifact(path):
                record_owner(path, sid)
    elif tool == "Skill":
        skill = normalize_skill((data.get("tool_input") or {}).get("skill", ""))
        if skill in CLAIM_SKILLS:
            plan = newest_plan()
            if plan:
                record_owner(plan, sid)


def normalize_skill(name):
    return name.rsplit(":", 1)[-1].strip()


def resolve_candidate(rule, sid):
    pattern = os.path.join(DOCS_ROOT, rule["dir"], rule["glob"])
    matches = glob.glob(pattern)
    if not matches:
        return None
    ledger = load_ledger()
    owned = [m for m in matches if owns(m, sid, ledger)]
    if not owned:
        return None
    return max(owned, key=os.path.getmtime)


def newest_plan():
    pattern = os.path.join(DOCS_ROOT, PLAN_RULE["dir"], PLAN_RULE["glob"])
    matches = glob.glob(pattern)
    return max(matches, key=os.path.getmtime) if matches else None


def body_hash(path):
    pipeline = (
        "set -o pipefail; "
        "awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2{print}' "
        '"$1" | sha256sum | cut -c1-16'
    )
    out = subprocess.run(
        ["bash", "-c", pipeline, "--", path],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


def _frontmatter_from_lines(lines):
    import yaml  # lazy import: missing → exception → fail-open in main()
    if not lines or lines[0].strip() != "---":
        return {}
    fm = []
    closed = False
    for line in lines[1:]:
        if line.strip() == "---":
            closed = True
            break
        fm.append(line)
    if not closed:
        return {}
    try:
        data = yaml.safe_load("\n".join(fm))
    except yaml.YAMLError:
        return {MALFORMED_FRONTMATTER_KEY: True}
    return data if isinstance(data, dict) else {}


def read_frontmatter(path):
    with open(path, "r", encoding="utf-8") as f:
        return _frontmatter_from_lines(f.read().splitlines())


def resolve_spec_from_chain(content):
    data = _frontmatter_from_lines((content or "").splitlines())
    chain = data.get("chain")
    spec = chain.get("spec") if isinstance(chain, dict) else None
    if spec and os.path.exists(spec):
        return spec
    return None


def _under(path, root):
    ap = os.path.abspath(path)
    ar = os.path.abspath(root)
    return ap == ar or ap.startswith(ar + os.sep)


def fresh(path, seconds):
    return time.time() - os.path.getmtime(path) <= seconds


def gate_reason(path, rule):
    """None if the gate is OPEN for `path` under `rule` (validated), else a reason
    string. The nudge's "validated" predicate is `gate_reason(...) is None`."""
    fm = read_frontmatter(path)
    if fm.get(MALFORMED_FRONTMATTER_KEY):
        return "malformed frontmatter"
    block_data = fm.get(rule["block"])
    if not isinstance(block_data, dict):
        return "no %s: block" % rule["block"]

    if block_data.get(rule["hash_key"]) != body_hash(path):
        return "hash stale (edited after last check)"

    if rule["block"] == "result_check":
        if block_data.get("verdict") != "OK":
            return "result_check verdict: %s" % block_data.get("verdict")
        return None

    phases = block_data.get("phases")
    if not isinstance(phases, dict):
        return "malformed phases"
    findings = block_data.get("findings", [])
    if not isinstance(findings, list):
        return "malformed findings"

    for name, ph in phases.items():
        status = ph.get("status") if isinstance(ph, dict) else None
        if status != "passed":
            return "phase %s: %s" % (name, status)

    open_critical = [
        f.get("id", "?")
        for f in findings
        if isinstance(f, dict)
        and f.get("severity") in BLOCK_ON
        and f.get("verdict") == "open"
    ]
    if open_critical:
        return "open CRITICAL: " + ", ".join(open_critical)

    return None


def validated(path, rule):
    return gate_reason(path, rule) is None


def block(candidate, reason, fix):
    stage = fix.split()[-1]
    sys.stderr.write(
        "🚧 IDD gate: %s has not passed validation.\n"
        "Reason: %s\n"
        "Action: dispatch a clean-context subagent to invoke the check-chain skill\n"
        "with argument %s on %s, collect verdicts in the main session, resolve the\n"
        "CRITICAL findings, then retry.\n"
        % (candidate, reason, stage, candidate)
    )
    sys.exit(2)


def patch_added_body(patch, target_path):
    """New-file body from an apply_patch Add File block, with leading '+' removed."""
    if not patch:
        return ""
    wanted = target_path.replace("\\", "/") if target_path else None
    capture = False
    out = []
    for line in patch.splitlines():
        if line.startswith("*** Add File: "):
            path = line[len("*** Add File: "):].strip().replace("\\", "/")
            capture = wanted is None or path == wanted
            out = [] if capture else out
            continue
        if line.startswith("*** "):
            if capture:
                break
            continue
        if capture and line.startswith("+"):
            out.append(line[1:])
    return "\n".join(out)


def patch_or_content(params, path=None):
    """New-file body for chain resolution: apply_patch patch text or Write content."""
    text = patch_text_from_input(params)
    body = patch_added_body(text, path)
    return body if body else text


def handle_write(data, tool, sid):
    params = data.get("tool_input") or {}
    paths = extract_paths(tool, params)
    if not paths:
        sys.exit(0)

    for path in paths:
        if _under(path, PLANS_DIR) and path.endswith(".md"):
            content = patch_or_content(params, path)
            spec = resolve_spec_from_chain(content) or resolve_candidate(SPEC_RULE, sid)
            if spec is not None:
                reason = gate_reason(spec, SPEC_RULE)
                if reason is not None:
                    block(spec, reason, SPEC_RULE["fix"])
            continue

        if not _under(path, DOCS_ROOT):
            plan = resolve_candidate(PLAN_RULE, sid)
            if plan is None:
                continue
            if not fresh(plan, IMPL_GATE_FRESH_SECONDS):
                continue
            reason = gate_reason(plan, PLAN_RULE)
            if reason is not None:
                block(plan, reason, PLAN_RULE["fix"])

    sys.exit(0)


def handle_skill(data, sid):
    skill = normalize_skill((data.get("tool_input") or {}).get("skill", ""))
    rule = GATE_MAP.get(skill)
    if rule is None:
        sys.exit(0)
    candidate = resolve_candidate(rule, sid)
    if candidate is None:
        sys.exit(0)
    reason = gate_reason(candidate, rule)
    if reason is None:
        sys.exit(0)
    block(candidate, reason, rule["fix"])


def rule_for(path):
    ap = os.path.abspath(path)
    for rule in NUDGE_RULES:
        root = os.path.abspath(os.path.join(DOCS_ROOT, rule["dir"]))
        if (ap == root or ap.startswith(root + os.sep)) and \
           fnmatch.fnmatch(os.path.basename(ap), rule["glob"]):
            return rule
    return None


def emit_nudge(path, fix):
    stage = fix.split()[-1]
    msg = (
        "IDD artifact %s was just written and has not passed validation yet. "
        "Dispatch a clean-context subagent to invoke the check-chain skill with "
        "argument %s on it, then collect verdicts in the main session, so the IDD "
        "gate is open before the next chain transition." % (path, stage)
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": msg,
        }
    }))


def handle_nudge(data):
    tool = data.get("tool_name")
    if tool not in ("Write", "apply_patch"):
        return
    for path in extract_paths(tool, data.get("tool_input") or {}):
        rule = rule_for(path)
        if rule is None:
            continue
        if not os.path.exists(path):
            continue
        if validated(path, rule):
            continue
        emit_nudge(path, rule["fix"])
        return  # one nudge per write is enough


def main():
    post = "--post" in sys.argv[1:]
    try:
        data = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)  # broken stdin → fail-open

    if post:
        event = "PostToolUse"
    else:
        event = data.get("hook_event_name") or (
            "PostToolUse" if "tool_response" in data else "PreToolUse")

    tool = data.get("tool_name")
    sid = data.get("session_id")
    try:
        if event == "PostToolUse":
            handle_nudge(data)
            sys.exit(0)
        record_ownership(data, tool, sid)
        if tool == "Skill":
            handle_skill(data, sid)
        elif tool in ("apply_patch", "Write", "Edit"):
            handle_write(data, tool, sid)
        else:
            sys.exit(0)
    except Exception as exc:  # fail-open
        print("chain-gate: internal error, skipping (fail-open): %s" % exc,
              file=sys.stderr)
        sys.exit(0)


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run both tests to verify they pass**

Run:
```bash
bash tests/test_idd_gate.sh && bash tests/test_idd_nudge.sh
```
Expected: both PASS (all assertions OK, `finish` reports 0 failures). The gate cases cover skill-gate allow/block, apply_patch spec→plan, chain.spec from patch (raw + dict), malformed-schema block, shell-quote safety, malformed-stdin fail-open, unowned-session escape. The nudge cases cover new-artifact/apply_patch nudge, non-artifact silent, malformed-stdin silent, validated silent, stale-hash, malformed-review nudges, metachar safety.

- [ ] **Step 6: Commit**

Stage the new hook plus the two legacy deletions (already removed on disk):
```bash
git add .codex-isolated/hooks/chain-gate.py .codex-isolated/hooks/idd-gate.py .codex-isolated/hooks/idd-nudge.py tests/test_idd_gate.sh tests/test_idd_nudge.sh
git commit -m "feat(idd): unify gate+nudge into chain-gate.py (Codex), drop split hooks"
```

---

## Task 2: rewire lib/idd/idd.sh to the single hook

**Files:**
- Modify: `lib/idd/idd.sh` (the inline Python block, lines ~24-25 and ~49-53)
- Modify: `tests/test_idd_wiring.sh`

**Interfaces:**
- Consumes: the `chain-gate.py` file from Task 1.
- Produces: `ensure_idd_wiring` that merges one PreToolUse entry (`python3 "$CODEX_HOME/hooks/chain-gate.py"`) and one PostToolUse entry (`python3 "$CODEX_HOME/hooks/chain-gate.py" --post`) into `$ICODEX_HOME_DIR/hooks.json`, idempotently, and strips both new and legacy IDD commands on opt-out.

- [ ] **Step 1: Update the wiring test assertions**

Edit `tests/test_idd_wiring.sh`:

In the opt-out-base block, replace the two legacy assertions:
```bash
assert_eq "opt-out base removes chain-gate" "0" "$(grep -c 'chain-gate.py' <<<"$hooks_off_base")"
```
(delete the separate `idd-nudge` line — one `chain-gate.py` count check covers both entries).

In the default-on block, replace the `idd-gate`/`idd-nudge` `assert_contains` pair:
```bash
assert_contains "default-on adds gate" "$hooks" "chain-gate.py"
assert_contains "default-on adds nudge (--post)" "$hooks" "chain-gate.py --post"
```

Replace the idempotency check:
```bash
ensure_idd_wiring
count="$(grep -c "chain-gate.py" "$ICODEX_HOME_DIR/hooks.json")"
assert_eq "idempotent (gate+nudge = 2 refs)" "2" "$count"
```

In the opt-out block, replace both legacy removal assertions with:
```bash
assert_eq "opt-out removes chain-gate" "0" "$(grep -c 'chain-gate.py' <<<"$hooks_off")"
```

Leave the base-hook and caveman `assert_contains` lines (`block-secrets.py`, `redact-secrets.py`, `caveman-hook.py`, `UserPromptSubmit`) unchanged.

- [ ] **Step 2: Run the wiring test to verify it fails**

Run:
```bash
bash tests/test_idd_wiring.sh
```
Expected: FAIL at "default-on adds gate" — `idd.sh` still merges `idd-gate.py`/`idd-nudge.py`, so `chain-gate.py` is absent from the merged hooks.json.

- [ ] **Step 3: Rewire idd.sh**

In `lib/idd/idd.sh`, inside the inline `python3 - "$home" "$enable"` heredoc, replace the command constants and the strip/add logic.

Replace:
```python
GATE = 'python3 "$CODEX_HOME/hooks/idd-gate.py"'
NUDGE = 'python3 "$CODEX_HOME/hooks/idd-nudge.py"'
```
with:
```python
GATE = 'python3 "$CODEX_HOME/hooks/chain-gate.py"'
NUDGE = 'python3 "$CODEX_HOME/hooks/chain-gate.py" --post'
# Legacy split-hook commands to strip on upgrade (self-healing migration).
LEGACY = [
    'python3 "$CODEX_HOME/hooks/idd-gate.py"',
    'python3 "$CODEX_HOME/hooks/idd-nudge.py"',
]
```

Replace:
```python
strip("PreToolUse", GATE)
strip("PostToolUse", NUDGE)
if enable:
    add("PreToolUse", "Skill|apply_patch|Write|Edit", GATE, "IDD phase gate")
    add("PostToolUse", "apply_patch|Write", NUDGE, "IDD nudge")
```
with:
```python
strip("PreToolUse", GATE)
strip("PostToolUse", NUDGE)
for cmd in LEGACY:
    strip("PreToolUse", cmd)
    strip("PostToolUse", cmd)
if enable:
    add("PreToolUse", "Skill|apply_patch|Write|Edit", GATE, "IDD phase gate")
    add("PostToolUse", "apply_patch|Write", NUDGE, "IDD nudge")
```

Leave the surrounding bash (`_idd_apply_hooks_json`, symlink-restore, `ensure_idd_wiring`, opt-out detection) unchanged.

- [ ] **Step 4: Run the wiring test to verify it passes**

Run:
```bash
bash tests/test_idd_wiring.sh
```
Expected: PASS — default-on merges one gate + one nudge (`--post`) `chain-gate.py` entry (2 refs total), idempotent, opt-out strips them and restores the shared symlink, base + caveman hooks preserved.

- [ ] **Step 5: Commit**

```bash
git add lib/idd/idd.sh tests/test_idd_wiring.sh
git commit -m "feat(idd): wire chain-gate.py (Pre + Post --post), strip legacy split entries"
```

---

## Task 3: check-chain + fix-intent skills

**Files:**
- Create: `.codex-isolated/skills/check-chain/SKILL.md`
- Create: `.codex-isolated/skills/fix-intent/SKILL.md`
- Modify: `tests/test_idd_skills.sh` (replace the four `check_skill` calls)
- Delete (stage): `.codex-isolated/skills/check-intent/`, `check-spec/`, `check-plan/`, `check-result/`, `intent/`

**Interfaces:**
- Consumes: nothing at runtime — these are model-visible skill docs. `check-chain` writes the `review:`/`result_check:` frontmatter that `chain-gate.py` (Task 1) reads: `phases` as a **dict** keyed by phase name, `findings` as a list, `spec_hash`/`intent_hash`/`plan_hash` = canonical body hash.
- Produces: two catalog-visible skills. `html-report` (already present) is invoked by `check-chain` Step 5.

- [ ] **Step 1: Rewrite the skills test for the unified layout**

Replace the body of `tests/test_idd_skills.sh` below the `helpers.sh` source with:

```bash
SK="$ROOT/.codex-isolated/skills"

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
  assert_contains "check-chain covers result stage" "$body" "result_check"
  assert_exit "check-chain frontmatter parses" 0 parse_frontmatter "$CC"
fi

# fix-intent: intent capture skill.
FI="$SK/fix-intent/SKILL.md"
assert_exit "fix-intent SKILL.md exists" 0 test -f "$FI"
if [[ -f "$FI" ]]; then
  body="$(cat "$FI")"
  assert_contains "fix-intent name frontmatter" "$body" "name: fix-intent"
  assert_contains "fix-intent has a description" "$body" "description:"
  assert_exit "fix-intent frontmatter parses" 0 parse_frontmatter "$FI"
fi

finish
```

- [ ] **Step 2: Run the skills test to verify it fails**

Run:
```bash
bash tests/test_idd_skills.sh
```
Expected: FAIL at "check-chain SKILL.md exists" — the unified skills are not created yet.

- [ ] **Step 3: Create the check-chain skill**

Copy the iclaude source verbatim, then apply one functional edit:

```bash
mkdir -p .codex-isolated/skills/check-chain
cp "/home/ikeniborn/Documents/Project/iclaude/.nvm-isolated/.claude-isolated/skills/check-chain/SKILL.md" .codex-isolated/skills/check-chain/SKILL.md
```

Then edit `.codex-isolated/skills/check-chain/SKILL.md`: immediately after the `### Step 2 — confirm & init state` paragraph, insert this explicit frontmatter-contract block so the skill emits gate-compatible YAML (dict-form `phases`, matching `chain-gate.py`):

````markdown
### Frontmatter contract (MANDATORY shape)

`chain-gate.py` reads this exact shape. `phases` is a **map keyed by phase name**
(never a list); `findings` is a list. Emit:

```yaml
---
review:
  <stage>_hash: <16-hex body hash>
  last_run: <YYYY-MM-DD>
  phases:
    structure: { status: passed }      # one key per phase; status ∈ passed|in_progress
    coverage:  { status: passed }
  findings:
    - id: F-001
      phase: structure
      severity: CRITICAL               # CRITICAL|WARNING|INFO
      section: "<heading>"
      section_hash: <16-hex>
      fragment: "<≤140-char quote or null>"
      text: "<what is wrong>"
      fix: "<how to fix>"
      verdict: open                    # open|accepted|wontfix|fixed
chain:
  intent: <path or null>               # spec adds chain.intent; plan adds intent+spec
  spec: <path or null>
---
```

For the `result` stage the block is `result_check:` with `verdict: OK|needs_work`,
`plan_hash`, `last_run` (no `phases`/`findings`).
````

Leave everything else in the copied file unchanged (invocation prose keeps the `/check-chain` shorthand as human-readable; in Codex the skill is invoked by name `check-chain` with a stage argument, which the frontmatter contract and `chain-gate.py` fix strings already reflect).

- [ ] **Step 4: Create the fix-intent skill**

Copy the iclaude source verbatim (no functional edits needed — `name: fix-intent`, handoff to `superpowers:brainstorming`, and the iwiki Step 0 "skip silently if unavailable" contract are all Codex-compatible):

```bash
mkdir -p .codex-isolated/skills/fix-intent
cp "/home/ikeniborn/Documents/Project/iclaude/.nvm-isolated/.claude-isolated/skills/fix-intent/SKILL.md" .codex-isolated/skills/fix-intent/SKILL.md
```

- [ ] **Step 5: Run the skills test to verify it passes**

Run:
```bash
bash tests/test_idd_skills.sh
```
Expected: PASS — both SKILL.md files exist, carry the expected `name:`/`description:` frontmatter, `check-chain` references all three hash keys + `result_check`, and both frontmatters parse as YAML.

- [ ] **Step 6: Commit**

Stage the new skills plus the five legacy skill-dir deletions (already removed on disk):

```bash
git add .codex-isolated/skills/check-chain .codex-isolated/skills/fix-intent \
        .codex-isolated/skills/check-intent .codex-isolated/skills/check-spec \
        .codex-isolated/skills/check-plan .codex-isolated/skills/check-result \
        .codex-isolated/skills/intent tests/test_idd_skills.sh
git commit -m "feat(idd): add unified check-chain + fix-intent skills, drop split validators"
```

---

## Task 4: docs, AGENTS.md, and full-suite regression

**Files:**
- Modify: `docs/wiki/idd.md`
- Verify/modify: `.codex-isolated/AGENTS.md`
- Run: full `tests/*.sh`

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: `docs/wiki/idd.md` describing the unified architecture; a green full test suite.

- [ ] **Step 1: Check AGENTS.md for stale IDD/skill references**

Run:
```bash
grep -nE 'idd-gate\.py|idd-nudge\.py|check-intent|check-spec|check-plan|check-result|(^|[^-])\bintent\b skill' .codex-isolated/AGENTS.md
```
Expected: no hits referring to the old split hooks or the four `check-*` skills or the `intent` skill (the Task-Log section already says `/check-chain`). If any stale reference appears, replace it: split hooks → `chain-gate.py`; `check-*` skill names → `check-chain <stage>`; `intent` skill → `fix-intent`. If no hits, make no change.

- [ ] **Step 2: Rewrite docs/wiki/idd.md for the unified architecture**

Replace the file contents with:

```markdown
# IDD

## Overview

The IDD layer ports the IDD->SDD phase gates from iclaude into icodex, in the
unified shape:

- `chain-gate.py`: one hook, two roles. As a `PreToolUse` gate it blocks phase
  transitions until the upstream artifact is validated; as a `PostToolUse` nudge
  (invoked with `--post`) it advises validating a newly written IDD artifact.
- `check-chain`: one skill with four stage profiles (intent / spec / plan / result)
  over a shared validation core.
- `fix-intent`: the intent-capture skill run before `superpowers:brainstorming`.

See [[architecture#Default run path]] and [[config#CODEX_HOME isolation]] for how
the shared hooks and skills become visible inside each per-project `CODEX_HOME`.

## Hook wiring

`ensure_idd_wiring` lives in `lib/idd/idd.sh`.

It merges two entries into `$CODEX_HOME/hooks.json`, both pointing at the same file:

- `PreToolUse`, matcher `Skill|apply_patch|Write|Edit`, command
  `python3 "$CODEX_HOME/hooks/chain-gate.py"` (gate);
- `PostToolUse`, matcher `apply_patch|Write`, command
  `python3 "$CODEX_HOME/hooks/chain-gate.py" --post` (nudge).

The merge is idempotent and self-healing: it strips any prior IDD entries — both the
current `chain-gate.py` commands and the legacy `idd-gate.py` / `idd-nudge.py` split
commands — then adds exactly one gate and one nudge entry when enabled. It runs after
`ensure_caveman_wiring`, so caveman's `UserPromptSubmit` hook and the base secret-guard
hooks compose with IDD.

## Opt-out

IDD is on by default.

Set `ICODEX_IDD=off` (case-insensitive) to disable it. When disabled, `ensure_idd_wiring`
removes the IDD hook entries. If the resulting `hooks.json` matches the shared base file,
the per-project home is restored to a symlink to `.codex-isolated/hooks.json`; if other
local hook merges remain (such as caveman), the real home file is preserved.

## Gate behavior

The gate role (no `--post`) is fail-open for hook-level failures and malformed stdin, but
blocks invalid artifact validation state. It selects its role by the `--post` argv flag,
falling back to `hook_event_name` / the presence of `tool_response` when the flag is
absent.

It records artifact ownership in `$CODEX_HOME/state/idd-sessions.json`, keyed by absolute
path, so one session is gated only by artifacts it wrote or claimed. It extracts touched
paths from `Write`, `Edit`, and Codex `apply_patch` payloads via `_codex_paths.py`. Plan
creation can resolve `chain.spec` from an `apply_patch` Add File body, including raw-string
and dict-shaped payloads.

The gate checks the same frontmatter contract the `check-chain` skill writes:
`review.intent_hash`, `review.spec_hash`, `review.plan_hash`, and `result_check.plan_hash`,
with `phases` as a dict and `findings` as a list. Hashing uses the validator-compatible
body-hash pipeline, with the path passed to bash as `argv`. Malformed / unclosed / invalid
frontmatter, non-dict `phases`, and non-list `findings` are fail-closed (the gate blocks).

## Nudge behavior

The nudge role (`--post`) is advisory and always exits 0.

When a `Write` or `apply_patch` touches an intent, spec, or plan artifact that is not
validated for its current body, it emits `PostToolUse` `additionalContext` asking the agent
to dispatch a clean-context subagent to run `check-chain <stage>`. Validated artifacts stay
silent. Malformed artifact frontmatter is treated as unvalidated and nudges; malformed hook
stdin stays silent.

## check-chain skill

`check-chain` validates one stage or the whole chain:

- `check-chain intent` — `docs/superpowers/intents/*-intent.md`;
- `check-chain spec` — `docs/superpowers/specs/*-design.md`;
- `check-chain plan` — `docs/superpowers/plans/*.md`;
- `check-chain result` — reconciles a plan against the implementation diff;
- `check-chain` (no stage) — runs the whole chain as a sequential gate.

It writes machine-readable `review:` / `result_check:` frontmatter (body untouched),
renders a four-tab HTML report via the `html-report` skill, and upserts the chain's row in
`docs/TODO.md`.

## fix-intent skill

`fix-intent` captures WHY/WHAT/Outcomes/Constraints before `superpowers:brainstorming`,
writing an approved `docs/superpowers/intents/YYYY-MM-DD-<topic>-intent.md`. It optionally
enriches questions from the iwiki MCP domain and skips silently when iwiki is unavailable.

## Skills visibility

`check-chain` and `fix-intent` live in `.codex-isolated/skills/`, and `setup_codex_home`
symlinks that shared directory into each per-project `CODEX_HOME/skills` so Codex lists them
in the model-visible skill catalog.

## Tests

Coverage lives in:

- `tests/test_idd_gate.sh` — gate (PreToolUse) behavior;
- `tests/test_idd_nudge.sh` — nudge (`--post`) behavior;
- `tests/test_idd_wiring.sh` — `ensure_idd_wiring` merge / idempotency / opt-out;
- `tests/test_idd_skills.sh` — `check-chain` + `fix-intent` skill docs;
- `tests/test_isolated.sh` — the shared `skills` symlink.
```

- [ ] **Step 3: Run the full test suite for regressions**

Run:
```bash
for t in tests/test_*.sh; do echo "== $t =="; bash "$t" || echo "FAIL: $t"; done
```
Expected: every suite reports 0 failures; no line prints `FAIL:`. Pay attention to `test_idd_gate`, `test_idd_nudge`, `test_idd_wiring`, `test_idd_skills`, `test_isolated`, and `test_smoke`.

- [ ] **Step 4: Commit**

```bash
git add docs/wiki/idd.md .codex-isolated/AGENTS.md
git commit -m "docs(idd): rewrite idd wiki + AGENTS refs for the unified chain"
```

- [ ] **Step 5: Update the iwiki page (doc-keeping rule)**

If the iwiki MCP server reports a domain bound to this project (`wiki_status`), update the
IDD page from the changed source, then lint:

- `wiki_update_page(domain, slug="idd", heading="Overview", new_body=<unified overview>, source="docs/wiki/idd.md")` (or `wiki_write_page` if no `idd` page exists yet);
- `wiki_lint(domain)` — no broken `[[refs]]`, no orphan/stale pages.

If iwiki is not set up for this project, skip this step.

---

## Self-Review

**1. Spec coverage** (against `2026-07-01-icodex-idd-unify-design.md`):
- chain-gate.py exists, same gate/nudge behavior, same frontmatter contract → Task 1. ✓
- check-chain + fix-intent skills catalog-visible → Task 3 (+ `test_isolated` covers the symlink). ✓
- idd.sh wires one gate + one nudge (`--post`), opt-out restores shared base → Task 2. ✓
- Four `test_idd_*` pass, full suite no regressions → Tasks 1-4 (Task 4 Step 3). ✓
- wiki/idd.md unified, TODO row present → Task 4 + TODO already opened. ✓
- Codex adaptations (argv event, CODEX_HOME ledger, apply_patch body, hardening, fix strings) → Task 1 code. ✓
- Non-goals honored: no change to caveman/iwiki/secret-guard/launcher beyond IDD wiring; no new IDD features. ✓

**2. Placeholder scan:** No TBD/TODO/"implement later" steps; chain-gate.py is fully inlined; test edits show exact old→new lines; skill creation gives exact `cp` + the one insert block. The `<stage>` / `<topic>` tokens are literal template syntax inside YAML/skill examples, not plan gaps.

**3. Type consistency:** `gate_reason`/`validated`, `resolve_candidate`, `resolve_spec_from_chain`, `patch_or_content`, `extract_paths`, `patch_text_from_input` names match across the hook and are consistent with `_codex_paths.py`'s exported API. Frontmatter keys (`review`, `result_check`, `spec_hash`/`intent_hash`/`plan_hash`, `phases` dict, `findings` list, `verdict`) are identical in the hook (Task 1), the check-chain contract (Task 3), and the tests. Wiring command strings (`chain-gate.py`, `chain-gate.py --post`) match between `idd.sh` (Task 2) and `test_idd_wiring.sh`.
