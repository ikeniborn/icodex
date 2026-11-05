#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

BLOCK_HOOK="$ROOT/.codex-isolated/hooks/block-secrets.py"
REDACT_HOOK="$ROOT/.codex-isolated/hooks/redact-secrets.py"
GWT_HOOK="$ROOT/.codex-isolated/hooks/gwt-gate.py"
HOOKS_JSON="$ROOT/.codex-isolated/hooks.json"

run_hook() { # <hook> <json>
  local hook="$1" payload="$2"
  printf '%s' "$payload" | python3 "$hook"
}

capture_hook() { # <hook> <json>
  local hook="$1" payload="$2"
  local out err code
  out="$(mktemp)"
  err="$(mktemp)"
  printf '%s' "$payload" | python3 "$hook" >"$out" 2>"$err"
  code=$?
  printf '%s\n%s\n%s' "$code" "$(cat "$out")" "$(cat "$err")"
  rm -f "$out" "$err"
}

assert_exit "block hook exists" 0 test -f "$BLOCK_HOOK"
assert_exit "redact hook exists" 0 test -f "$REDACT_HOOK"
assert_exit "GWT hook exists" 0 test -f "$GWT_HOOK"
assert_exit "hooks json exists" 0 test -f "$HOOKS_JSON"

safe_payload='{"tool_name":"Bash","tool_input":{"command":"cat .env.example"}}'
assert_exit "block hook allows safe env templates" 0 run_hook "$BLOCK_HOOK" "$safe_payload"

blocked_path_payload='{"tool_name":"Bash","tool_input":{"command":"cat .env"}}'
blocked_path_result="$(capture_hook "$BLOCK_HOOK" "$blocked_path_payload")"
blocked_path_code="$(sed -n '1p' <<<"$blocked_path_result")"
assert_eq "block hook blocks sensitive bash paths" "2" "$blocked_path_code"
assert_contains "block hook explains blocked path" "$blocked_path_result" "sensitive"

patch_path_payload='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Add File: .env\n+TOKEN=placeholder\n*** End Patch\n"}}'
patch_path_result="$(capture_hook "$BLOCK_HOOK" "$patch_path_payload")"
patch_path_code="$(sed -n '1p' <<<"$patch_path_result")"
assert_eq "block hook blocks sensitive patch targets" "2" "$patch_path_code"

secret_payload='{"tool_name":"Bash","tool_input":{"command":"export OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz123456"}}'
secret_result="$(capture_hook "$REDACT_HOOK" "$secret_payload")"
secret_code="$(sed -n '1p' <<<"$secret_result")"
assert_eq "redact hook blocks secrets in bash commands" "2" "$secret_code"
assert_contains "redact hook explains secret block" "$secret_result" "secret"

patch_secret_payload='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Add File: safe.txt\n+token=ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKL123456\n*** End Patch\n"}}'
patch_secret_result="$(capture_hook "$REDACT_HOOK" "$patch_secret_payload")"
patch_secret_code="$(sed -n '1p' <<<"$patch_secret_result")"
assert_eq "redact hook blocks secrets in patches" "2" "$patch_secret_code"

hooks_config="$(cat "$HOOKS_JSON" 2>/dev/null || true)"
assert_contains "hooks json wires PreToolUse" "$hooks_config" '"PreToolUse"'
assert_contains "hooks json wires block hook" "$hooks_config" 'block-secrets.py'
assert_contains "hooks json wires redact hook" "$hooks_config" 'redact-secrets.py'
assert_contains "hooks json wires GWT gate" "$hooks_config" 'gwt-gate.py'
assert_contains "hooks json matches GWT context" "$hooks_config" 'wiki_spec_context'
assert_contains "hooks json matches GWT mutation" "$hooks_config" 'wiki_update_page'
assert_contains "hooks json matches Bash" "$hooks_config" 'Bash'
assert_contains "hooks json matches apply_patch" "$hooks_config" 'apply_patch'

check_heredoc_regressions() {
  python3 - "$ROOT" <<'PY'
import json
from pathlib import Path
import subprocess
import sys
import tempfile

hooks = Path(sys.argv[1]) / '.codex-isolated/hooks'

def invoke(command, name='block-secrets.py', tool='Bash', params=None):
    payload = {'tool_name': tool, 'tool_input': params if params is not None else {'command': command}}
    return subprocess.run([sys.executable, str(hooks / name)], input=json.dumps(payload),
                          text=True, capture_output=True)

cases = [
    ('append literal prose', "cat >> note.md <<'EOF'\n/tmp/check.pyPASSneverprintssecret/body\nEOF", 0, None),
    ('reverse redirections', 'cat <<"EOF" > "note file.md"\n/secret prose\nEOF\n', 0, None),
    ('protected destination', "cat > .env <<'EOF'\nplain\nEOF", 2, 'protected_path'),
    ('relative credentials', "cat > config/credentials.txt <<'EOF'\nplain\nEOF", 2, 'protected_path'),
    ('unquoted delimiter', 'cat > note.md <<EOF\n$(cat /run/secrets/demo)\nEOF', 2, 'indeterminate_access'),
    ('shell consumer', "bash <<'EOF'\ncat /run/secrets/demo\nEOF", 2, 'protected_path'),
    ('python consumer', "python3 <<'EOF'\nprint('plain')\nEOF", 0, None),
    ('pipeline', "cat <<'EOF' | bash\necho ok\nEOF", 2, 'indeterminate_access'),
    ('multiple bodies', "cat <<'A' <<'B'\na\nA\nb\nB", 2, 'indeterminate_access'),
    ('unterminated body', "cat > note.md <<'EOF'\nplain", 2, 'unterminated_heredoc'),
    ('first terminator', "cat > note.md <<'EOF'\nplain\nEOF\necho suffix\nEOF", 2, 'ambiguous_heredoc'),
    ('literal operator', "printf '%s' '<<EOF'", 0, None),
    ('comment', 'echo ok # <<EOF', 0, None),
    ('arithmetic shift', 'echo $((1 << 2))', 0, None),
    ('arithmetic assignment', '((value <<= 1))', 0, None),
    ('here-string', 'cat <<< plain', 0, None),
    ('protected here-string', 'cat <<< /run/secrets/demo', 2, 'protected_path'),
    ('tab stripping', "cat > note.md <<-'EOF'\nplain\nEOF", 2, 'indeterminate_access'),
    ('descriptor override', "cat > note.md 3<<'EOF'\nplain\nEOF", 2, 'indeterminate_access'),
    ('escaped delimiter', "cat > note.md <<\\EOF\nplain\nEOF", 2, 'indeterminate_access'),
    ('mixed delimiter', "cat > note.md <<E'OF'\nplain\nEOF", 2, 'indeterminate_access'),
    ('substitution consumer', "echo $(cat <<'EOF'\n/secret prose\nEOF\n)", 2, 'indeterminate_access'),
    ('quoted substitution', 'echo "$(cat <<\'EOF\'\nplain\nEOF\n)"', 2, 'indeterminate_access'),
    ('hash after substitution is a word', "echo $(echo x)#word <<'EOF'\nplain\nEOF", 2, 'indeterminate_access'),
    ('escaped space before hash', 'echo x\\ # <<EOF\nordinary\nEOF', 2, 'indeterminate_access'),
    ('escaped separator before hash', 'echo x\\;# <<EOF\nordinary\nEOF', 2, 'indeterminate_access'),
    ('escaped space inside substitution', 'echo "$(echo x\\ # <<EOF\nordinary\nEOF\n)"', 2, 'indeterminate_access'),
    ('continued comment boundary', 'echo \\\n# <<EOF', 0, None),
    ('continued word before hash', 'echo x\\\n#word <<EOF\nordinary\nEOF', 2, 'indeterminate_access'),
    ('continued heredoc operator', 'bash <\\\n<EOF\necho ordinary\nEOF', 2, 'indeterminate_access'),
    ('escaped backslash before operator', 'bash \\\\\n<<EOF\necho ordinary\nEOF', 2, 'indeterminate_access'),
    ('arithmetic substitution', "echo $(( $(cat <<'EOF'\n1\nEOF\n) << 2))", 2, 'indeterminate_access'),
    ('malformed quotation', 'echo "bad <<EOF', 2, 'indeterminate_access'),
    ('line continuation', "cat > note.md \\\n<<'EOF'\nplain\nEOF", 2, 'indeterminate_access'),
]
for cat in ('cat', '/bin/cat', '/usr/bin/cat'):
    for quote in ("'", '"'):
        cases.append(('literal substitutions', cat + ' >> "note file.md" <<' + quote + 'END' + quote +
                      '\n$(cat /run/secrets/demo) `echo secret`\nEND\n  \n', 0, None))

failures = []
for label, command, code, category in cases:
    result = invoke(command)
    if result.returncode != code or (category and category not in result.stderr):
        failures.append((label, result.returncode, code, category))
    if result.returncode == 2 and category:
        if 'block-secrets.py' not in result.stderr or not json.loads(result.stdout).get('reason'):
            failures.append((label, 'missing hook attribution'))

marker = 'DO_NOT_ECHO_7e42'
for tool, params in [('Bash', {'command': 'cat /run/secrets/' + marker}),
                     ('Read', {'file_path': '/run/secrets/' + marker}),
                     ('apply_patch', {'patch': '*** Add File: /run/secrets/' + marker})]:
    result = invoke('', tool=tool, params=params)
    if result.returncode != 2 or marker in result.stdout + result.stderr:
        failures.append(('secret-safe path diagnostics', tool))

secret = 'sk-proj-' + 'A' * 32 + marker
command = "cat > note.md <<'EOF'\n" + secret + '\nEOF'
assert invoke(command).returncode == 0
result = invoke(command, 'redact-secrets.py')
if result.returncode != 2 or 'redact-secrets.py' not in result.stderr or 'secret_content' not in result.stderr:
    failures.append(('content still denied', result.returncode))
assert marker not in result.stdout + result.stderr

with tempfile.TemporaryDirectory() as directory:
    target = Path(directory) / 'must-not-exist'
    result = invoke("bash <<'EOF'\ntouch " + str(target) + '\nEOF')
    assert result.returncode == 2 and not target.exists()

assert not failures, failures
PY
}
assert_exit "literal heredoc and secret-safe diagnostics regressions" 0 check_heredoc_regressions

finish
