---
review:
  plan_hash: 1e7060ab0c91f233
  spec_hash: 12d0ef2ea1b81b29
  last_run: 2026-06-29
  phases:
    structure:     { status: passed }
    coverage:      { status: passed }
    dependencies:  { status: passed }
    verifiability: { status: passed }
    consistency:   { status: passed }
  findings:
    - id: F-003
      phase: coverage
      severity: WARNING
      section: "Task 5: Documentation (iwiki)"
      section_hash: aff67d847ae44527
      fragment: "Run: `/iwiki-lint`"
      text: >-
        Spec Documentation section (lines 274-279) lists four doc actions, but
        Task 5 covers only three. Two spec items have no plan step: (a) "Update
        docs/wiki/architecture.md / docs/wiki/command.md (launch-path step)" and
        (b) "Run iwiki:iwiki-ingest on changed sources". Task 5 writes caveman.md,
        edits config.md, and runs /iwiki-lint, but never updates architecture.md or
        command.md and never invokes iwiki:iwiki-ingest. Non-blocking: documentation
        cross-references only; no success criterion becomes unverifiable.
      fix: >-
        Add to Task 5 a step updating docs/wiki/architecture.md and/or
        docs/wiki/command.md with the launch-path caveman step (ensure_caveman_wiring
        after ensure_superpowers_wiring), and an iwiki:iwiki-ingest invocation on the
        changed sources before /iwiki-lint, matching spec lines 278-279.
      verdict: fixed
      verdict_at: 2026-06-29
      resolution: >-
        Resolved. Task 5 now adds Step 3 ("Record the launch-path step in
        architecture.md / command.md") covering spec item (a), and Step 4
        ("Regenerate/index the wiki via iwiki, then lint") which runs
        iwiki:iwiki-ingest before /iwiki-lint, covering spec item (b). The Files
        list now lists architecture.md and command.md, and the self-review
        spec-coverage bullet names architecture/command launch-path step +
        iwiki-ingest. All four spec Documentation actions (lines 274-279) are now
        covered.
chain:
  intent: null
  spec: docs/superpowers/specs/2026-06-29-caveman-icodex-design.md
---

# Caveman integration for icodex — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give icodex an opt-in, caveman-style token-compression layer for Codex that costs ≈0 input tokens per turn in its active launch mode.

**Architecture:** Two layers in the icodex-owned isolated `CODEX_HOME`. Layer 1 — a small, prompt-cached caveman block written into `$CODEX_HOME/AGENTS.md` (mode substituted at launch). Layer 2 — a `UserPromptSubmit` python3 hook merged into the per-project home `hooks.json`; it stays silent while the session's current mode equals the active launch mode and only injects context on a `/caveman` switch or deviation. Wiring is done by `ensure_caveman_wiring` on the launch path, gated on `ICODEX_CAVEMAN_MODE`.

**Tech Stack:** Bash (wrapper modules + tests), python3 stdlib (hook + JSON merge), Codex CLI hooks (`hooks.json`) and AGENTS.md instruction injection.

## Global Constraints

- Shell scripts start with `#!/usr/bin/env bash`; executables use `set -euo pipefail`, tests use `set -uo pipefail`.
- Two-space indentation inside functions/conditionals; functions named `lowercase_with_underscores`; wrapper env vars use the `ICODEX_` prefix.
- python3 **stdlib only** — no pip dependencies.
- The caveman `AGENTS.md` block must stay **< 2 KiB** (global scope is first in Codex's lookup order; an oversized block truncates project docs against `project_doc_max_bytes`).
- All file rewrites are **idempotent**: regenerate into a temp file, write back only when `cmp -s` shows a change.
- Tests are dependency-free, use `mktemp` temp dirs, and perform **no network access**.
- Commits follow Conventional Commits (`feat(caveman): …`, `test(caveman): …`, `docs(wiki): …`).
- Documentation is English; update `docs/wiki/` via iwiki before finishing (repo guideline).
- Ship default is **off**: caveman activates only when `ICODEX_CAVEMAN_MODE` is set to `lite|full|ultra`.

---

### Task 1: Caveman `UserPromptSubmit` hook

**Files:**
- Create: `.codex-isolated/hooks/caveman-hook.py`
- Test: `tests/test_caveman_hook.sh`

**Interfaces:**
- Consumes: stdin JSON from Codex `UserPromptSubmit` — fields `prompt` (string) and `session_id` (string); env `ICODEX_CAVEMAN_MODE` (active launch mode) and `CODEX_HOME`.
- Produces: stdout = either empty (no-op) or a JSON object `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":<str>}}`. Exit code always 0. Side effect: writes the per-session mode file `$CODEX_HOME/.caveman/mode-<session_id>`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_caveman_hook.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

HOOK="$ROOT/.codex-isolated/hooks/caveman-hook.py"

# Each run gets a clean CODEX_HOME so the per-session mode file starts empty.
run() { # <launch_mode> <prompt> -> prints "<exit>\n<stdout>"
  local mode="$1" prompt="$2" home out code
  home="$(mktemp -d)"
  out="$(CODEX_HOME="$home" ICODEX_CAVEMAN_MODE="$mode" \
    python3 "$HOOK" <<EOF
{"prompt": $(printf '%s' "$prompt" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'), "session_id": "s1"}
EOF
)"
  code=$?
  printf '%s\n%s' "$code" "$out"
  rm -rf "$home"
}

assert_exit "hook file exists" 0 test -f "$HOOK"

# 1. Steady state: current mode == active launch mode -> zero output.
steady="$(run full "list the files")"
assert_eq  "steady exit 0"      "0" "$(sed -n '1p' <<<"$steady")"
assert_eq  "steady empty stdout" ""  "$(sed -n '2,$p' <<<"$steady")"

# 2. /caveman switch injects the new mode.
switch="$(run full "/caveman lite")"
assert_contains "switch injects additionalContext" "$switch" "additionalContext"
assert_contains "switch names lite"                 "$switch" "lite"

# 3. /caveman off injects a disable line.
off="$(run full "/caveman off")"
assert_contains "off disables" "$off" "DISABLED"

# 4. 'stop caveman' also disables.
stop="$(run full "stop caveman")"
assert_contains "stop caveman disables" "$stop" "DISABLED"

# 5. Persisted deviation: after switching to lite, a later plain turn still injects.
dev_home="$(mktemp -d)"
mkdir -p "$dev_home/.caveman"
printf 'lite' > "$dev_home/.caveman/mode-s1"
dev="$(CODEX_HOME="$dev_home" ICODEX_CAVEMAN_MODE="full" python3 "$HOOK" <<'EOF'
{"prompt": "do the thing", "session_id": "s1"}
EOF
)"
assert_contains "deviation re-injects active mode" "$dev" "lite"
rm -rf "$dev_home"

finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_caveman_hook.sh`
Expected: FAIL — `hook file exists` fails (`.codex-isolated/hooks/caveman-hook.py` does not exist yet), subsequent assertions error.

- [ ] **Step 3: Write the hook implementation**

Create `.codex-isolated/hooks/caveman-hook.py`:

```python
#!/usr/bin/env python3
"""icodex caveman UserPromptSubmit hook.

Injects the active caveman mode into model context only when the session's
current mode deviates from the active launch mode (ICODEX_CAVEMAN_MODE), so the
steady state costs zero tokens. Also handles in-session /caveman switches.
Registered only when caveman is enabled (see lib/caveman/caveman.sh).
"""
import json
import os
import re
import sys

MODES = ("off", "lite", "full", "ultra")
SWITCH_RE = re.compile(r"^\s*/caveman\s+(off|lite|full|ultra)\b", re.IGNORECASE)
STOP_RE = re.compile(r"^\s*(stop caveman|normal mode)\s*$", re.IGNORECASE)

STYLE = {
    "lite": "lite — drop filler words only; keep articles and full sentences.",
    "full": "full — drop articles, filler, pleasantries; fragments OK; short synonyms.",
    "ultra": "ultra — fragments + maximum abbreviation; technical terms exact.",
}
DISABLED = ("CAVEMAN DISABLED for this session — respond normally; "
            "ignore the caveman block.")


def state_path(session_id):
    home = os.environ.get("CODEX_HOME", os.path.expanduser("~/.codex"))
    sid = re.sub(r"[^A-Za-z0-9_.-]", "_", session_id or "default")
    return os.path.join(home, ".caveman", "mode-" + sid)


def read_mode(path, fallback):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            value = fh.read().strip()
        return value if value in MODES else fallback
    except FileNotFoundError:
        return fallback


def write_mode(path, mode):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(mode)


def emit(text):
    if text:
        json.dump({"hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": text,
        }}, sys.stdout)
    sys.exit(0)


def active_line(mode):
    return "CAVEMAN ACTIVE MODE: %s Apply the '%s' row of the caveman mode table." % (
        STYLE[mode], mode)


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        emit("")  # malformed input -> no-op
    prompt = data.get("prompt", "") or ""
    session_id = data.get("session_id", "") or ""

    launch_mode = os.environ.get("ICODEX_CAVEMAN_MODE", "full").strip().lower()
    if launch_mode not in MODES:
        launch_mode = "full"

    path = state_path(session_id)
    current = read_mode(path, launch_mode)

    switch = SWITCH_RE.match(prompt)
    if switch:
        new = switch.group(1).lower()
        write_mode(path, new)
        emit(DISABLED if new == "off" else active_line(new))
    if STOP_RE.match(prompt):
        write_mode(path, "off")
        emit(DISABLED)

    if current == launch_mode:
        emit("")  # AGENTS.md already specifies behaviour -> 0 tokens
    if current == "off":
        emit(DISABLED)
    emit(active_line(current))


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_caveman_hook.sh`
Expected: PASS — all assertions report `PASS`, final line `PASS=N FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add .codex-isolated/hooks/caveman-hook.py tests/test_caveman_hook.sh
git commit -m "feat(caveman): add UserPromptSubmit compression hook"
```

---

### Task 2: Wiring module + AGENTS.md block template

**Files:**
- Create: `.codex-isolated/caveman/agents-block.md`
- Create: `lib/caveman/caveman.sh`
- Test: `tests/test_caveman_wiring.sh`

**Interfaces:**
- Consumes: env `ICODEX_CAVEMAN_MODE`, `ICODEX_SHARED_DIR`, `ICODEX_HOME_DIR`; `log_warn` (from `lib/core/logging.sh`); the shared `hooks.json` and the template `.codex-isolated/caveman/agents-block.md`; the hook from Task 1.
- Produces: `ensure_caveman_wiring()` (called from `icodex.sh` in Task 3). Maintains `$ICODEX_HOME_DIR/AGENTS.md` (delimited caveman region) and `$ICODEX_HOME_DIR/hooks.json` (real merged file when enabled, symlink to shared when disabled).

- [ ] **Step 1: Create the AGENTS.md block template**

Create `.codex-isolated/caveman/agents-block.md` (the `__CAVEMAN_MODE__` token is substituted at launch; keep this file < 2 KiB):

```markdown
# Caveman output compression (icodex)

Active mode: **__CAVEMAN_MODE__**. Compress your prose output to save tokens. This
governs how you WRITE, never WHAT you do.

Mode table:
- lite  — drop filler words (just/really/basically); keep articles and full sentences.
- full  — drop articles, filler, pleasantries; sentence fragments OK; prefer short
  synonyms (big not extensive, fix not "implement a solution for"). Technical terms exact.
- ultra — full, plus maximum abbreviation and heavy fragments.

Pattern: `[thing] [action] [reason]. [next step].`

Write NORMALLY (no compression) for:
- security warnings and irreversible-action confirmations (deletes, force-push, drops);
- multi-step sequences where dropping conjunctions or order would risk a misread;
- code, code comments, commit messages, and PR descriptions;
- exact error messages (quote verbatim).

Language: compress in the conversation's language — never switch language to compress.
Docs, code comments, commits, and PRs stay in English.

Switching: if a turn injects a line starting `CAVEMAN ACTIVE MODE:` or `CAVEMAN
DISABLED`, that injected line is authoritative for the current mode — follow it over the
active mode named above. The user switches with `/caveman lite|full|ultra|off` (or
`stop caveman` / `normal mode`).
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_caveman_wiring.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"

# Build a fake shared store + per-project home.
tmp="$(mktemp -d)"
export ICODEX_ROOT="$tmp"
export ICODEX_SHARED_DIR="$tmp/.codex-isolated"
export ICODEX_HOME_DIR="$tmp/.codex-homes/proj"
mkdir -p "$ICODEX_SHARED_DIR/caveman" "$ICODEX_HOME_DIR"

# Shared hooks.json with the existing secret-guard hook (the merge must preserve it).
cat > "$ICODEX_SHARED_DIR/hooks.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "python3 \"$CODEX_HOME/hooks/block-secrets.py\"" } ] }
    ]
  }
}
EOF
# Minimal template with the mode placeholder.
printf 'Active mode: **__CAVEMAN_MODE__**.\n' > "$ICODEX_SHARED_DIR/caveman/agents-block.md"
# Home hooks.json starts as a symlink, like setup_codex_home leaves it.
ln -s "$ICODEX_SHARED_DIR/hooks.json" "$ICODEX_HOME_DIR/hooks.json"

source "$ROOT/lib/caveman/caveman.sh"
agents="$ICODEX_HOME_DIR/AGENTS.md"
hooks="$ICODEX_HOME_DIR/hooks.json"

# 1. Enabled: region rendered, hooks.json merged into a real file.
export ICODEX_CAVEMAN_MODE=full
ensure_caveman_wiring
assert_contains "agents has region start" "$(cat "$agents")" "icodex:caveman:start"
assert_contains "agents substitutes mode" "$(cat "$agents")" "Active mode: **full**"
assert_exit "home hooks.json is a real file" 0 test -f "$hooks"
assert_eq  "home hooks.json is not a symlink" "1" "$([[ -L "$hooks" ]] && echo 0 || echo 1)"
assert_contains "merge keeps secret guard" "$(cat "$hooks")" "block-secrets.py"
assert_contains "merge adds caveman hook"  "$(cat "$hooks")" "caveman-hook.py"
assert_contains "merge wires UserPromptSubmit" "$(cat "$hooks")" "UserPromptSubmit"

# 2. Idempotent: second call leaves both files byte-identical.
a_before="$(cat "$agents")"; h_before="$(cat "$hooks")"
ensure_caveman_wiring
assert_eq "agents idempotent" "$a_before" "$(cat "$agents")"
assert_eq "hooks idempotent"  "$h_before" "$(cat "$hooks")"

# 3. Disabled: region removed, hooks.json restored to a symlink.
unset ICODEX_CAVEMAN_MODE
ensure_caveman_wiring
assert_eq "agents region removed" "0" "$(grep -c 'icodex:caveman:start' "$agents" 2>/dev/null || echo 0)"
assert_eq "home hooks.json back to symlink" "0" "$([[ -L "$hooks" ]] && echo 0 || echo 1)"

rm -rf "$tmp"
finish
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash tests/test_caveman_wiring.sh`
Expected: FAIL — sourcing `lib/caveman/caveman.sh` fails (file does not exist), so `ensure_caveman_wiring` is undefined.

- [ ] **Step 4: Write the wiring module**

Create `lib/caveman/caveman.sh`:

```bash
#!/usr/bin/env bash
# Wire caveman (token-compression) into the per-project Codex home at launch.
#
# Two idempotent actions, gated on ICODEX_CAVEMAN_MODE (lite|full|ultra; unset/off
# disables): (1) maintain a delimited caveman region in $CODEX_HOME/AGENTS.md;
# (2) register the caveman UserPromptSubmit hook by merging it into the home
# hooks.json (a real file when enabled, a symlink to the shared secret-guard file
# when disabled). Mirrors the launch-path, idempotent style of lib/plugin/superpowers.sh.

_CAVEMAN_REGION_START="<!-- icodex:caveman:start -->"
_CAVEMAN_REGION_END="<!-- icodex:caveman:end -->"

# Echo the active launch mode (lite|full|ultra), or empty when caveman is disabled.
_caveman_mode() {
  local m
  m="$(printf '%s' "${ICODEX_CAVEMAN_MODE:-}" | tr '[:upper:]' '[:lower:]')"
  case "$m" in
    lite|full|ultra) printf '%s\n' "$m" ;;
    *) printf '\n' ;;
  esac
}

# Echo the rendered caveman block (mode substituted) from the tracked template.
_caveman_render_block() { # <mode>
  local mode="$1" tpl="$ICODEX_SHARED_DIR/caveman/agents-block.md"
  [[ -f "$tpl" ]] || return 1
  sed "s/__CAVEMAN_MODE__/$mode/g" "$tpl"
}

# Insert/replace (or remove) the delimited caveman region in <file>. Idempotent.
_caveman_write_agents_region() { # <file> <block_or_empty>
  local file="$1" block="$2" tmp
  if [[ -z "$block" && ! -f "$file" ]]; then
    return 0  # nothing to remove and nothing to add
  fi
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    awk -v s="$_CAVEMAN_REGION_START" -v e="$_CAVEMAN_REGION_END" '
      $0 == s { skip=1; next }
      $0 == e { skip=0; next }
      !skip { print }
    ' "$file" > "$tmp"
  fi
  if [[ -n "$block" ]]; then
    printf '%s\n%s\n%s\n' "$_CAVEMAN_REGION_START" "$block" "$_CAVEMAN_REGION_END" >> "$tmp"
  fi
  if [[ ! -f "$file" ]] || ! cmp -s "$tmp" "$file"; then
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
}

# Build the home hooks.json = shared hooks + caveman UserPromptSubmit entry. Idempotent.
_caveman_enable_hooks_json() {
  local shared="$ICODEX_SHARED_DIR/hooks.json" home="$ICODEX_HOME_DIR/hooks.json" tmp
  [[ -f "$shared" ]] || return 0
  tmp="$(mktemp)"
  python3 - "$shared" > "$tmp" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    cfg = json.load(fh)
hooks = cfg.setdefault("hooks", {})
ups = hooks.setdefault("UserPromptSubmit", [])
cmd = 'python3 "$CODEX_HOME/hooks/caveman-hook.py"'
present = any(h.get("command") == cmd
              for entry in ups for h in entry.get("hooks", []))
if not present:
    ups.append({"hooks": [{
        "type": "command",
        "command": cmd,
        "timeout": 10,
        "statusMessage": "caveman",
    }]})
json.dump(cfg, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
  if [[ -L "$home" || ! -f "$home" ]] || ! cmp -s "$tmp" "$home"; then
    rm -f "$home"
    cat "$tmp" > "$home"
  fi
  rm -f "$tmp"
}

# Restore the home hooks.json symlink to the shared file (caveman not registered).
_caveman_disable_hooks_json() {
  local shared="$ICODEX_SHARED_DIR/hooks.json" home="$ICODEX_HOME_DIR/hooks.json"
  [[ -L "$home" ]] && return 0
  rm -f "$home"
  ln -s "$shared" "$home"
}

# Orchestrate caveman wiring on the launch path.
ensure_caveman_wiring() {
  local agents="$ICODEX_HOME_DIR/AGENTS.md" mode block
  mode="$(_caveman_mode)"
  if [[ -z "$mode" ]]; then
    _caveman_write_agents_region "$agents" ""
    _caveman_disable_hooks_json
    return 0
  fi
  if ! block="$(_caveman_render_block "$mode")"; then
    log_warn "caveman template missing — skipping caveman wiring"
    return 0
  fi
  _caveman_write_agents_region "$agents" "$block"
  _caveman_enable_hooks_json
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/test_caveman_wiring.sh`
Expected: PASS — final line `PASS=N FAIL=0`.

- [ ] **Step 6: Commit**

```bash
git add lib/caveman/caveman.sh .codex-isolated/caveman/agents-block.md tests/test_caveman_wiring.sh
git commit -m "feat(caveman): wire AGENTS.md block and home hooks.json merge"
```

---

### Task 3: Launch-path integration + config example

**Files:**
- Modify: `icodex.sh` (source list + `main()` run path)
- Modify: `.codex_config.example`
- Test: `tests/test_caveman_launch.sh`

**Interfaces:**
- Consumes: `ensure_caveman_wiring` (Task 2), `ensure_superpowers_wiring` (existing).
- Produces: caveman wiring runs on every default (launch) invocation, right after superpowers wiring; `ICODEX_CAVEMAN_MODE` is documented for users.

- [ ] **Step 1: Write the failing test**

Create `tests/test_caveman_launch.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

entry="$(cat "$ROOT/icodex.sh")"
assert_contains "entrypoint sources caveman module" "$entry" "caveman/caveman"
assert_contains "entrypoint calls caveman wiring"   "$entry" "ensure_caveman_wiring"

# ensure_caveman_wiring must run after ensure_superpowers_wiring on the run path.
sp_line="$(grep -n 'ensure_superpowers_wiring' "$ROOT/icodex.sh" | grep -v source | tail -1 | cut -d: -f1)"
cv_line="$(grep -n 'ensure_caveman_wiring' "$ROOT/icodex.sh" | tail -1 | cut -d: -f1)"
assert_eq "caveman wiring runs after superpowers" "1" \
  "$([[ -n "$sp_line" && -n "$cv_line" && "$cv_line" -gt "$sp_line" ]] && echo 1 || echo 0)"

example="$(cat "$ROOT/.codex_config.example")"
assert_contains "config example documents the var" "$example" "ICODEX_CAVEMAN_MODE"

finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_caveman_launch.sh`
Expected: FAIL — `icodex.sh` does not yet source `caveman/caveman` nor call `ensure_caveman_wiring`; `.codex_config.example` lacks `ICODEX_CAVEMAN_MODE`.

- [ ] **Step 3: Add the module to the source list**

In `icodex.sh`, edit the `for m in …` module list to add `caveman/caveman` (between `plugin/superpowers` and `launcher/launch`):

```bash
for m in core/logging core/init core/validation command/args \
         binary/detect binary/lockfile binary/install \
         config/isolated config/permissions config/sandbox config/env proxy/proxy symlink/symlink \
         plugin/superpowers caveman/caveman launcher/launch; do
  # shellcheck source=/dev/null
  source "$ICODEX_ROOT/lib/$m.sh"
done
```

- [ ] **Step 4: Call the wiring on the run path**

In `icodex.sh` `main()`, add `ensure_caveman_wiring` immediately after `ensure_superpowers_wiring`:

```bash
  ensure_superpowers_wiring
  ensure_caveman_wiring
  install_ensure || exit 1
```

- [ ] **Step 5: Document the variable in `.codex_config.example`**

Append to `.codex_config.example` (after the existing run-mode block):

```bash
# Caveman token-compression of model output. Unset/off disables (ship default).
# When set, a small caveman instruction block is added to the isolated CODEX_HOME
# AGENTS.md (prompt-cached, ~0 per-turn token overhead) and a UserPromptSubmit hook
# is registered. Switch in-session with `/caveman lite|full|ultra|off`.
#   lite   drop filler only
#   full   drop articles + filler + pleasantries (recommended)
#   ultra  fragments + maximum abbreviation
# ICODEX_CAVEMAN_MODE=full
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash tests/test_caveman_launch.sh`
Expected: PASS — final line `PASS=N FAIL=0`.

- [ ] **Step 7: Run the full suite to confirm no regressions**

Run: `for t in tests/test_*.sh; do bash "$t" || { echo "FAILED: $t"; break; }; done`
Expected: every test file ends with `PASS=N FAIL=0`.

- [ ] **Step 8: Commit**

```bash
git add icodex.sh .codex_config.example tests/test_caveman_launch.sh
git commit -m "feat(caveman): run caveman wiring on launch; document ICODEX_CAVEMAN_MODE"
```

---

### Task 4: Upstream rules refresh helper

**Files:**
- Create: `scripts/vendor-caveman.sh`
- Test: `tests/test_caveman_vendor.sh`

**Interfaces:**
- Consumes: env `ICODEX_PROXY` (optional, reused from `.codex_config` conventions).
- Produces: downloads the upstream caveman `SKILL.md` to `.codex-isolated/caveman/upstream-SKILL.md` as a reference snapshot for hand-curating `agents-block.md`. Network-only; never run during tests.

- [ ] **Step 1: Write the failing test**

Create `tests/test_caveman_vendor.sh` (structural only — no network):

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

script="$ROOT/scripts/vendor-caveman.sh"
assert_exit "vendor script exists"      0 test -f "$script"
assert_exit "vendor script executable"  0 test -x "$script"
body="$(cat "$script")"
assert_contains "targets upstream SKILL.md" "$body" "JuliusBrussee/caveman"
assert_contains "writes reference snapshot" "$body" "upstream-SKILL.md"

finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_caveman_vendor.sh`
Expected: FAIL — `scripts/vendor-caveman.sh` does not exist.

- [ ] **Step 3: Write the vendor helper**

Create `scripts/vendor-caveman.sh` and `chmod +x` it:

```bash
#!/usr/bin/env bash
# Refresh the upstream caveman SKILL.md reference snapshot. Manual, network-only.
# The curated block lives in .codex-isolated/caveman/agents-block.md and is
# hand-maintained from this snapshot (hybrid source: upstream rules, native hook).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/.codex-isolated/caveman/upstream-SKILL.md"
URL="https://raw.githubusercontent.com/JuliusBrussee/caveman/main/skills/caveman/SKILL.md"

proxy_args=()
[[ -n "${ICODEX_PROXY:-}" ]] && proxy_args+=("--proxy" "$ICODEX_PROXY")

mkdir -p "$(dirname "$DEST")"
echo "Fetching $URL"
curl -fsSL "${proxy_args[@]}" -o "$DEST" "$URL"
echo "Wrote $DEST"
echo "Now hand-update .codex-isolated/caveman/agents-block.md from this snapshot (keep it < 2 KiB)."
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_caveman_vendor.sh`
Expected: PASS — final line `PASS=N FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/vendor-caveman.sh tests/test_caveman_vendor.sh
git commit -m "feat(caveman): add upstream SKILL.md refresh helper"
```

---

### Task 5: Documentation (iwiki)

**Files:**
- Create: `docs/wiki/caveman.md`
- Modify: `docs/wiki/config.md` (add the `ICODEX_CAVEMAN_MODE` entry)
- Modify: `docs/wiki/architecture.md` and `docs/wiki/command.md` (launch-path step)

**Interfaces:**
- Consumes: nothing at runtime — documentation only.
- Produces: a wiki page describing the caveman layer, a config-variable entry, and an
  updated launch-path description, all link-clean per `/iwiki-lint`.

- [ ] **Step 1: Write `docs/wiki/caveman.md`**

Create `docs/wiki/caveman.md` covering: purpose (output-token savings, ≈0 self-overhead), the two layers (cached `AGENTS.md` block + `UserPromptSubmit` hook merged into home `hooks.json`), `ICODEX_CAVEMAN_MODE` modes (`off`/`lite`/`full`/`ultra`), in-session `/caveman` switching, the silent-when-steady token model, and the launch-path wiring (`ensure_caveman_wiring`, runs after `ensure_superpowers_wiring`). Cross-link with `[[config]]`, `[[plugins]]`, and `[[architecture]]`. Keep claims aligned with the spec at `docs/superpowers/specs/2026-06-29-caveman-icodex-design.md`.

- [ ] **Step 2: Add the config entry in `docs/wiki/config.md`**

Add an `ICODEX_CAVEMAN_MODE` entry to the config-variable section: values `off`(default)/`lite`/`full`/`ultra`, effect (renders the cached `AGENTS.md` caveman block + registers the `UserPromptSubmit` hook in the home `hooks.json`), and a `[[caveman]]` cross-link.

- [ ] **Step 3: Record the launch-path step in `architecture.md` / `command.md`**

In `docs/wiki/architecture.md` (the "Default run path" description) and `docs/wiki/command.md` (the launch sequence), add that `ensure_caveman_wiring` runs right after `ensure_superpowers_wiring` on the default run path, gated on `ICODEX_CAVEMAN_MODE`. Add a `[[caveman]]` cross-link from each.

- [ ] **Step 4: Regenerate/index the wiki via iwiki, then lint**

Run: `iwiki:iwiki-ingest lib/caveman/caveman.sh` (regenerate/update the affected page and re-index the changed sources).
Then run: `/iwiki-lint`
Expected: no broken `[[refs]]`, no orphan/stale pages introduced by the new page. Fix any reported issues inline.

- [ ] **Step 5: Commit**

```bash
git add docs/wiki/caveman.md docs/wiki/config.md docs/wiki/architecture.md docs/wiki/command.md
git commit -m "docs(wiki): document caveman integration and ICODEX_CAVEMAN_MODE"
```

---

## Self-Review

**1. Spec coverage**

- SC "output terse with `ICODEX_CAVEMAN_MODE=full`" → Task 2 (AGENTS.md block) + Task 3 (launch wiring).
- SC "0 tokens while current == active launch mode" → Task 1 Step 1 test case 1 (steady-state empty stdout).
- SC "`/caveman lite|full|ultra|off` + `stop caveman`/`normal mode` switches mid-session" → Task 1 (hook switch logic + tests 2–4).
- SC "target project files never touched" → all writes target `$ICODEX_HOME_DIR` (Task 2); covered by the isolated test harness.
- SC "ship default off; activates only when set" → Task 2 `_caveman_mode` empty branch + Task 2 test case 3 (disabled removes region, restores symlink).
- Layer 1 (cached AGENTS.md, < 2 KiB) → Task 2 template + Global Constraints.
- Layer 2 (one python3 `UserPromptSubmit` hook, lazy mode init) → Task 1.
- Wiring (per-home `hooks.json` merge, idempotent, after superpowers) → Task 2 + Task 3.
- Asset layout (hook in `.codex-isolated/hooks/`, template in `caveman/`, `vendor-caveman.sh`, `lib/caveman/caveman.sh`) → Tasks 1, 2, 4.
- Docs (wiki page + config entry + architecture/command launch-path step + `iwiki-ingest` + lint) → Task 5.

No spec requirement is left without a task.

**2. Placeholder scan:** No `TBD`/`TODO`/"handle edge cases"/"similar to Task N". Every code step contains complete code; every run step states the exact command and expected result.

**3. Type/name consistency:** `ensure_caveman_wiring` (defined Task 2, called Task 3); hook command string `python3 "$CODEX_HOME/hooks/caveman-hook.py"` identical in the hook path (Task 1), the merge (Task 2), and the test assertions; mode set `off|lite|full|ultra` consistent across hook, module `_caveman_mode`, template, and config example; region markers `<!-- icodex:caveman:start/end -->` identical in module and the Task 2 test.
