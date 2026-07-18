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

finish
