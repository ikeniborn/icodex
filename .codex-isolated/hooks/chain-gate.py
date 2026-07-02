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
import re

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
SKILL_PATH_RE = re.compile(r"(?:^|/)skills/([^/\s\"']+)/SKILL\.md(?:$|[\s\"'])")
SKILL_TOKEN_RE = re.compile(r"\bskill\s*[:=]\s*[\"']?(?:[\w-]+:)?([\w-]+)")


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
    else:
        skill = skill_from_event(data, tool)
        if skill in CLAIM_SKILLS:
            plan = newest_plan()
            if plan:
                record_owner(plan, sid)


def normalize_skill(name):
    return name.rsplit(":", 1)[-1].strip()


def skill_from_path(path):
    match = SKILL_PATH_RE.search(path.replace("\\", "/"))
    return normalize_skill(match.group(1)) if match else ""


def skill_from_text(text):
    if not isinstance(text, str):
        return ""
    path_match = SKILL_PATH_RE.search(text.replace("\\", "/"))
    if path_match:
        return normalize_skill(path_match.group(1))
    token_match = SKILL_TOKEN_RE.search(text)
    return normalize_skill(token_match.group(1)) if token_match else ""


def skill_from_event(data, tool):
    params = data.get("tool_input") or {}
    if tool == "Skill" and isinstance(params, dict):
        return normalize_skill(params.get("skill", ""))
    if tool == "Read":
        for path in extract_paths(tool, params):
            skill = skill_from_path(path)
            if skill:
                return skill
    if tool == "Bash":
        if isinstance(params, dict):
            return skill_from_text(params.get("cmd", "") or params.get("command", ""))
        return skill_from_text(params)
    return ""


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
    skill = skill_from_event(data, data.get("tool_name"))
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
        if tool in ("Skill", "Read", "Bash"):
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
