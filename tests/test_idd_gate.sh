#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

GATE="$ROOT/.codex-isolated/hooks/chain-gate.py"
assert_exit "gate file exists" 0 test -f "$GATE"

# Build a temp repo CWD with a docs/superpowers tree + a ledger home.
WORK="$(mktemp -d)"; HOME_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$HOME_DIR"; }
trap cleanup EXIT
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

write_spec_review() { # <review_yaml>
  local body="# Foo

Body text."
  local hash
  hash="$(printf '%s\n' "$body" | sha256sum | cut -c1-16)"
  cat > "$SPEC" <<EOF
---
review:
  spec_hash: $hash
$1
---
$body
EOF
}

write_spec_open_fm() {
  local body="# Foo

Body text."
  local hash
  hash="$(printf '%s\n' "$body" | sha256sum | cut -c1-16)"
  cat > "$SPEC" <<EOF
---
review:
  spec_hash: $hash
  phases:
    structure: { status: passed }
  findings: []
$body
EOF
}

write_spec_invalid_yaml() {
  local body="# Foo

Body text."
  local hash
  hash="$(printf '%s\n' "$body" | sha256sum | cut -c1-16)"
  cat > "$SPEC" <<EOF
---
review:
  spec_hash: $hash
  phases: [
---
$body
EOF
}

write_spec_file() { # <path> <phase_status>
  local path="$1" status="$2"
  local body="# Foo

Body text."
  local hash
  hash="$(printf '%s\n' "$body" | sha256sum | cut -c1-16)"
  cat > "$path" <<EOF
---
review:
  spec_hash: $hash
  phases:
    structure: { status: $status }
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

# 2a. Codex can load skills through ordinary file reads instead of a Skill tool.
skill_read='{"session_id":"s1","tool_name":"Read","tool_input":{"file_path":".codex-isolated/plugins/cache/openai-curated/superpowers/3fdeeb49/skills/writing-plans/SKILL.md"}}'
assert_eq "pending spec blocks writing-plans SKILL.md read" "2" "$(run_gate "$skill_read")"

# 2b. Some Codex surfaces expose skill activation only through shell-visible text.
skill_bash='{"session_id":"s1","tool_name":"Bash","tool_input":{"cmd":"sed -n '\''1,120p'\'' .codex-isolated/plugins/cache/openai-curated/superpowers/3fdeeb49/skills/writing-plans/SKILL.md"}}'
assert_eq "pending spec blocks writing-plans bash read" "2" "$(run_gate "$skill_bash")"

# 2c. LoEn workflow skills are not part of the IDD/Superpowers gate.
loen_skill_read='{"session_id":"s1","tool_name":"Read","tool_input":{"file_path":".codex-isolated/plugins/cache/ikeniborn/loen/0.2.0/skills/loop-start/SKILL.md"}}'
assert_eq "pending spec allows loen loop-start SKILL.md read" "0" "$(run_gate "$loen_skill_read")"

# 3. apply_patch creating a plan while spec NOT passed -> block (spec->plan gate).
patch='{"session_id":"s1","tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Add File: docs/superpowers/plans/2026-06-30-foo.md\n+# Plan\n*** End Patch\n"}}'
assert_eq "apply_patch plan create blocks on unpassed spec" "2" "$(run_gate "$patch")"

# 4. apply_patch plan Add File with chain.spec blocks on unowned pending spec.
chain_patch='{"session_id":"s2","tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Add File: docs/superpowers/plans/2026-06-30-chain.md\n+---\n+chain:\n+  spec: docs/superpowers/specs/2026-06-30-foo-design.md\n+---\n+# Plan\n*** End Patch\n"}}'
assert_eq "apply_patch plan chain spec blocks unowned pending spec" "2" "$(run_gate "$chain_patch")"

# 5. Raw-string apply_patch input also exposes chain.spec for gating.
raw_chain_patch='{"session_id":"s2","tool_name":"apply_patch","tool_input":"*** Begin Patch\n*** Add File: docs/superpowers/plans/2026-06-30-raw-chain.md\n+---\n+chain:\n+  spec: docs/superpowers/specs/2026-06-30-foo-design.md\n+---\n+# Plan\n*** End Patch\n"}'
assert_eq "raw apply_patch chain spec blocks unowned pending spec" "2" "$(run_gate "$raw_chain_patch")"

# 6. Malformed review schema blocks instead of fail-opening.
write_spec_review "  phases: bad
  findings: []"
assert_eq "malformed phases block writing-plans" "2" "$(run_gate "$skill")"

write_spec_review "  phases:
    structure: { status: passed }
  findings: bad"
assert_eq "malformed findings block writing-plans" "2" "$(run_gate "$skill")"

write_spec_open_fm
assert_eq "unclosed frontmatter blocks writing-plans" "2" "$(run_gate "$skill")"

write_spec_invalid_yaml
assert_eq "invalid yaml frontmatter blocks writing-plans" "2" "$(run_gate "$skill")"

# 7. Artifact paths with shell metacharacters are hashed safely.
SHELL_SPEC_REL='docs/superpowers/specs/2026-06-30-shell-"quote"-design.md'
write_spec_file "$WORK/$SHELL_SPEC_REL" pending
shell_own="$(
  python3 - "$SHELL_SPEC_REL" <<'PY'
import json
import sys
print(json.dumps({
    "session_id": "shell",
    "tool_name": "Write",
    "tool_input": {"file_path": sys.argv[1], "content": "x"},
}))
PY
)"
run_gate "$shell_own" >/dev/null
shell_skill='{"session_id":"shell","tool_name":"Skill","tool_input":{"skill":"superpowers:writing-plans"}}'
assert_eq "quoted spec path blocks without shell fail-open" "2" "$(run_gate "$shell_skill")"

# 8. Malformed stdin -> fail-open (exit 0).
assert_eq "malformed stdin fail-open" "0" "$(run_gate 'not json')"

# 9. No owned artifact (session s2) -> escape/allow (exit 0).
skill2='{"session_id":"s2","tool_name":"Skill","tool_input":{"skill":"superpowers:writing-plans"}}'
assert_eq "unowned spec does not gate other session" "0" "$(run_gate "$skill2")"

check_directory_and_reason_regressions() {
  python3 - "$ROOT" <<'PY'
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch

hook = Path(sys.argv[1]) / '.codex-isolated/hooks/chain-gate.py'
marker = 'DO_NOT_ECHO_7e42'
failures = []
with tempfile.TemporaryDirectory() as temp:
    base = Path(temp)
    own, foreign, home = base/'own space', base/'foreign', base/'home'
    def plan(root, value):
        p = root/'docs/superpowers/plans'/('fixture-' + marker + '.md')
        p.parent.mkdir(parents=True, exist_ok=True)
        body = '# Plan\n'
        field = '  plan_hash: ' + value + '\n' if value is not None else '  body_sha256: unused\n'
        p.write_text('---\nreview:\n' + field + '  phases:\n    structure: {status: passed}\n  findings: []\n---\n' + body)
        return p
    digest = hashlib.sha256(b'# Plan\n').hexdigest()[:16]
    target = plan(own, '"' + digest + '"')
    bad = plan(foreign, '"0000000000000000"')
    env = dict(os.environ, CODEX_HOME=str(home))
    ledger = home/'state/idd-sessions.json'
    def call(label, params, cwd_value='absent', expected=0, category=None, extra=None):
        event = {'tool_name': 'Skill', 'session_id': label, 'tool_input': dict(skill='executing-plans', **params)}
        if cwd_value != 'absent':
            event['cwd'] = cwd_value
        if extra:
            event.update(extra)
        before = ledger.read_bytes() if ledger.exists() else None
        result = subprocess.run([sys.executable, str(hook)], cwd=foreign, env=env,
                                input=json.dumps(event), text=True, capture_output=True)
        if result.returncode != expected or (category and category not in result.stderr):
            failures.append((label, result.returncode, expected, category))
        if result.returncode == 2:
            if 'chain-gate.py' not in result.stderr or marker in result.stdout + result.stderr:
                failures.append((label, 'unsafe or unattributed diagnostic'))
        if category == 'invalid_workdir':
            after = ledger.read_bytes() if ledger.exists() else None
            if before != after:
                failures.append((label, 'ledger mutated'))
        return result
    call('event cwd', {}, str(own))
    call('explicit wins', {'workdir':str(own)}, str(foreign))
    call('ignore lower invalid', {'workdir':str(own)}, None)
    for value in (None, '', 'relative', str(base/'missing'), str(target), 1):
        call('bad workdir ' + str(value), {'workdir':value}, str(own), 2, 'invalid_workdir')
    call('invalid event', {}, str(base/marker), 2, 'invalid_workdir')
    call('no fields', {}, expected=2, category='stale_hash')
    for prefix in ('cd "' + str(own) + '" && ', 'cd -- "' + str(own) + '" && '):
        call('leading cd '+prefix, {'command':prefix+'cat /skills/executing-plans/SKILL.md'},
             extra={'tool_name':'Bash'})
    for prefix in ('cd ../own && ', 'cd "$TARGET" && '):
        call('unsupported cd '+prefix, {'command':prefix+'cat /skills/executing-plans/SKILL.md'},
             expected=2, category='invalid_workdir', extra={'tool_name':'Bash'})
    for value, category in [(None,'missing_hash'), ('null','invalid_hash'), ('123','invalid_hash'),
                            ('"BAD"','invalid_hash'), ('"0000000000000000"','stale_hash')]:
        plan(own, value)
        result = call('hash '+str(value), {'workdir':str(own)}, expected=2, category=category)
        wanted = hashlib.sha256(os.fsencode(os.path.abspath(target))).hexdigest()
        if wanted not in result.stderr:
            failures.append(('artifact locator mismatch', category))
    plan(own, '"' + digest + '"')
    for fragment in ('{status: '+marker+'}',):
        text=target.read_text(); target.write_text(text.replace('{status: passed}', fragment))
        call('phase secret', {'workdir':str(own)}, expected=2, category='phase_not_passed')
        target.write_text(text)
    text=target.read_text();target.write_text(text.replace('findings: []', 'findings:\n    - {id: '+marker+', severity: CRITICAL, verdict: open}'))
    call('finding secret', {'workdir':str(own)}, expected=2, category='open_critical')
    target.write_text(text)
    call('write directory', {'workdir':str(own)}, str(foreign),
         extra={'tool_name':'Write','tool_input':{'file_path':str(target.relative_to(own)), 'workdir':str(own), 'content':'x'}})
    # A draft body triggers a nudge from the selected checkout without echoing its name.
    plan(own, None)
    result=call('post directory', {}, str(own), extra={'tool_name':'Write','tool_input':{'file_path':str(target.relative_to(own))}, 'hook_event_name':'PostToolUse'})
    if 'chain-gate.py' not in result.stdout or marker in result.stdout+result.stderr:
        failures.append(('unsafe or missing nudge',))
    spec=importlib.util.spec_from_file_location('directory_fixture_gate',hook)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    payload=json.dumps({'tool_name':'Skill','tool_input':{'workdir':str(own),'skill':'executing-plans'}})
    import io
    from contextlib import redirect_stderr
    err=io.StringIO()
    with patch.object(sys, 'stdin', io.StringIO(payload)), patch.object(sys, 'argv', [str(hook)]), patch.object(module.os,'chdir',side_effect=OSError(marker)), redirect_stderr(err):
        try:
            module.main()
        except SystemExit as exc:
            if exc.code!=2:failures.append(('chdir error exit',exc.code))
        else:failures.append(('chdir error allowed',))
    if marker in err.getvalue() or 'invalid_workdir' not in err.getvalue():failures.append(('chdir diagnostic',))
assert not failures, failures
PY
}
assert_exit "directory selection and safe validation reasons" 0 check_directory_and_reason_regressions

finish
