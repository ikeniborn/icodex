---
review:
  plan_hash: 08f207ca06fb39bc
  spec_hash: 3934a4596bfccf78
  last_run: 2026-06-30
  phases:
    structure:     { status: passed }
    coverage:      { status: passed }
    dependencies:  { status: passed }
    verifiability: { status: passed }
    consistency:   { status: passed }
  findings:
    - id: F-001
      phase: verifiability
      severity: MINOR
      section: "Task 4 / Step 2"
      section_hash: 80964f537c0f9075
      fragment: "Run a real launch from a scratch project dir, then inspect the resolved home"
      text: >-
        Step 2 presented two procedures: the first used `./icodex.sh --help`,
        which the step's own Note then disclaimed (`--help` short-circuits in
        main() before setup_codex_home runs, so the .codex-homes/<id> dir and
        its skills/rules/AGENTS.md are never built and the first `ls` finds
        nothing). The reliable source-the-function fallback that followed was the
        actual DoD. Leaving the disclaimed first block inline risked a worker
        running it and reporting a false negative.
      fix: >-
        Demote the `--help` block to a parenthetical ("does NOT reach
        setup_codex_home — for reference only") or drop it, and lead with the
        source-based check as the single verification command.
      verdict: fixed
      verdict_at: 2026-06-30
      resolution: >-
        Body edited: the disclaimed `--help` block was removed; Step 2 now leads
        with the single source-based verification (source init.sh + isolated.sh,
        call setup_codex_home, inspect $ICODEX_HOME_DIR) and a single Expected
        block. Step 5 cleanup updated to "$ICODEX_HOME_DIR" (the $hd var is gone).
        Re-run of the verifiability checklist no longer detects the ambiguity.
chain:
  intent: null
  spec: docs/superpowers/specs/2026-06-30-codex-home-asset-wiring-design.md
---
# CODEX_HOME asset wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the committed `.codex-isolated/{skills,rules,AGENTS.md}` assets into every per-project Codex home so user skills, the execution-policy rules, and the global AGENTS.md base guidance are actually live at runtime.

**Architecture:** All changes are in one function (`setup_codex_home`) plus one new helper in `lib/config/isolated.sh`. `skills/` and `rules/` are symlinked into the home with the existing `_link_shared` helper (auto-current via the symlink). `AGENTS.md` cannot be symlinked (caveman mutates it), so its base content is maintained as a delimited `icodex:base` region, re-synced from the shared file on every launch — mirroring the existing caveman region mechanism in `lib/caveman/caveman.sh`.

**Tech Stack:** Bash, awk, the project's dependency-free test harness (`tests/helpers.sh`).

**Spec:** `docs/superpowers/specs/2026-06-30-codex-home-asset-wiring-design.md`

---

## Reference: current code

`lib/config/isolated.sh` — `_link_shared` and `setup_codex_home` as they exist now:

```sh
# Symlink a shared-store entry into the per-project home (idempotent).
_link_shared() { # <name>
  local name="$1"
  local target="$ICODEX_HOME_DIR/$name" src="$ICODEX_SHARED_DIR/$name"
  [[ -L "$target" ]] && return 0
  rm -rf "$target" 2>/dev/null || true
  ln -s "$src" "$target"
}

# Build the per-project home and export CODEX_HOME (run path).
setup_codex_home() {
  resolve_codex_home
  mkdir -p "$ICODEX_HOME_DIR"
  _link_shared plugins
  _link_shared hooks
  _link_shared hooks.json
  _link_shared auth.json
  [[ -f "$ICODEX_HOME_DIR/config.toml" ]] \
    || cp "$ICODEX_SHARED_DIR/config.toml" "$ICODEX_HOME_DIR/config.toml"
  export CODEX_HOME="$ICODEX_HOME_DIR"
}
```

The new helper deliberately mirrors `_caveman_write_agents_region` in `lib/caveman/caveman.sh` (same awk strip + write-if-changed shape).

---

## Task 1: Symlink `skills/` and `rules/` into the home

**Files:**
- Modify: `lib/config/isolated.sh` (`setup_codex_home`)
- Test: `tests/test_isolated.sh`

- [ ] **Step 1: Add shared-store fixtures for skills and rules**

In `tests/test_isolated.sh`, after the existing fixture block (the line `printf '#!/usr/bin/env python3\n' > "$ICODEX_SHARED_DIR/hooks/example.py"`), add:

```sh
# skills fixture: a user skill plus a codex-managed .system dir
mkdir -p "$ICODEX_SHARED_DIR/skills/sample-skill" "$ICODEX_SHARED_DIR/skills/.system"
printf 'name: sample\n' > "$ICODEX_SHARED_DIR/skills/sample-skill/SKILL.md"
# rules fixture: the execution-policy file
mkdir -p "$ICODEX_SHARED_DIR/rules"
printf 'prefix_rule(pattern=["git"], decision="allow")\n' > "$ICODEX_SHARED_DIR/rules/default.rules"
```

- [ ] **Step 2: Add the failing assertions**

In `tests/test_isolated.sh`, immediately after the existing line `assert_exit "config copied"      0 test -f "$ICODEX_HOME_DIR/config.toml"`, add:

```sh
assert_exit "skills symlink"     0 test -L "$ICODEX_HOME_DIR/skills"
assert_eq  "skills -> shared"    "$ICODEX_SHARED_DIR/skills" "$(readlink "$ICODEX_HOME_DIR/skills")"
assert_exit "rules symlink"      0 test -L "$ICODEX_HOME_DIR/rules"
assert_eq  "rules -> shared"     "$ICODEX_SHARED_DIR/rules" "$(readlink "$ICODEX_HOME_DIR/rules")"
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash tests/test_isolated.sh`
Expected: FAIL lines for `skills symlink`, `skills -> shared`, `rules symlink`, `rules -> shared` (the home has no `skills`/`rules` yet); `PASS=… FAIL=4` (or similar non-zero FAIL), exit non-zero.

- [ ] **Step 4: Implement — link skills and rules in `setup_codex_home`**

In `lib/config/isolated.sh`, inside `setup_codex_home`, add two `_link_shared` calls after `_link_shared auth.json`:

```sh
  _link_shared auth.json
  _link_shared skills      # user skills → runtime (variant A: whole-dir symlink)
  _link_shared rules       # codex execution-policy → runtime
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/test_isolated.sh`
Expected: the four new assertions PASS; `FAIL=0`, exit 0.

- [ ] **Step 6: Syntax check**

Run: `bash -n lib/config/isolated.sh && bash -n tests/test_isolated.sh`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/config/isolated.sh tests/test_isolated.sh
git commit -m "feat(home): symlink skills/ and rules/ into the per-project CODEX_HOME

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Sync the `AGENTS.md` base region each launch

**Files:**
- Modify: `lib/config/isolated.sh` (new helper `_sync_agents_base_region` + call in `setup_codex_home`)
- Test: `tests/test_isolated.sh`

- [ ] **Step 1: Add an AGENTS.md fixture**

In `tests/test_isolated.sh`, after the rules fixture added in Task 1, add:

```sh
# AGENTS.md base fixture (the global guidance that must reach the home)
printf '# Base guidelines\nLine one.\n' > "$ICODEX_SHARED_DIR/AGENTS.md"
```

- [ ] **Step 2: Add the failing base-region assertions**

In `tests/test_isolated.sh`, immediately after the `rules -> shared` assertion from Task 1, add:

```sh
assert_exit "AGENTS.md created"  0 test -f "$ICODEX_HOME_DIR/AGENTS.md"
agents="$(cat "$ICODEX_HOME_DIR/AGENTS.md")"
assert_contains "AGENTS base marker start" "$agents" "<!-- icodex:base:start -->"
assert_contains "AGENTS base content"      "$agents" "Base guidelines"
assert_contains "AGENTS base marker end"   "$agents" "<!-- icodex:base:end -->"
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash tests/test_isolated.sh`
Expected: FAIL for `AGENTS.md created` and the three `AGENTS base …` assertions (the home has no `AGENTS.md` yet), exit non-zero.

- [ ] **Step 4: Implement the `_sync_agents_base_region` helper**

In `lib/config/isolated.sh`, add the markers and helper **above** `setup_codex_home` (just below the `_link_shared` helper):

```sh
_AGENTS_BASE_REGION_START="<!-- icodex:base:start -->"
_AGENTS_BASE_REGION_END="<!-- icodex:base:end -->"

# Maintain a delimited base region in <file>, re-synced from the shared AGENTS.md
# on every launch so edits to .codex-isolated/AGENTS.md propagate to every home.
# Strips any existing base region and re-appends the current shared content; any
# other region (e.g. caveman) or free text outside the markers is preserved.
# Idempotent: writes only when the result differs. Mirrors the region mechanism
# in lib/caveman/caveman.sh (_caveman_write_agents_region).
_sync_agents_base_region() { # <file>
  local file="$1" src="$ICODEX_SHARED_DIR/AGENTS.md" base tmp
  [[ -f "$src" ]] || return 0
  base="$(cat "$src")"
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    awk -v s="$_AGENTS_BASE_REGION_START" -v e="$_AGENTS_BASE_REGION_END" '
      $0 == s { skip=1; next }
      $0 == e { skip=0; next }
      !skip { print }
    ' "$file" > "$tmp"
  fi
  printf '%s\n%s\n%s\n' "$_AGENTS_BASE_REGION_START" "$base" "$_AGENTS_BASE_REGION_END" >> "$tmp"
  if [[ ! -f "$file" ]] || ! cmp -s "$tmp" "$file"; then
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
}
```

- [ ] **Step 5: Call the helper from `setup_codex_home`**

In `lib/config/isolated.sh`, inside `setup_codex_home`, add the sync call after the `config.toml` copy and before `export CODEX_HOME`:

```sh
  [[ -f "$ICODEX_HOME_DIR/config.toml" ]] \
    || cp "$ICODEX_SHARED_DIR/config.toml" "$ICODEX_HOME_DIR/config.toml"
  _sync_agents_base_region "$ICODEX_HOME_DIR/AGENTS.md"
  export CODEX_HOME="$ICODEX_HOME_DIR"
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash tests/test_isolated.sh`
Expected: the `AGENTS.md created` and three `AGENTS base …` assertions PASS; `FAIL=0`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/config/isolated.sh tests/test_isolated.sh
git commit -m "feat(home): sync AGENTS.md base region into CODEX_HOME each launch

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Test re-sync, coexistence, and idempotency of the base region

**Files:**
- Test: `tests/test_isolated.sh`

These behaviors are already implemented by Task 2; this task locks them with tests. Note the ordering: the coexistence step appends a foreign region after the base region, which on the next `setup_codex_home` moves the base region to the end (one-time reorder). Every subsequent run keeps the base region last, so the idempotency assertion must come **after** the coexistence step.

- [ ] **Step 1: Add the dynamic base-region tests**

In `tests/test_isolated.sh`, after the existing config-idempotency block (the line `assert_eq "config not clobbered on re-run" "$before" "$(cat "$ICODEX_HOME_DIR/config.toml")"`), add:

```sh
# base region re-syncs when the shared AGENTS.md changes
printf '# Base guidelines v2\nNew line.\n' > "$ICODEX_SHARED_DIR/AGENTS.md"
setup_codex_home
assert_contains "AGENTS base re-synced" "$(cat "$ICODEX_HOME_DIR/AGENTS.md")" "New line."
assert_exit "old base line removed" 1 grep -qF "Line one." "$ICODEX_HOME_DIR/AGENTS.md"

# a foreign (caveman-style) region outside the base markers must survive a re-sync;
# this run also stabilizes region order to [foreign][base]
printf '\n<!-- icodex:caveman:start -->\nCAVEMAN\n<!-- icodex:caveman:end -->\n' >> "$ICODEX_HOME_DIR/AGENTS.md"
setup_codex_home
agents_after="$(cat "$ICODEX_HOME_DIR/AGENTS.md")"
assert_contains "foreign region preserved"   "$agents_after" "CAVEMAN"
assert_contains "base region still present"   "$agents_after" "New line."

# idempotent: with the shared AGENTS.md unchanged and order already stable, a
# further setup leaves AGENTS.md byte-identical
before_agents="$(cat "$ICODEX_HOME_DIR/AGENTS.md")"
setup_codex_home
assert_eq "AGENTS.md stable on re-run" "$before_agents" "$(cat "$ICODEX_HOME_DIR/AGENTS.md")"
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `bash tests/test_isolated.sh`
Expected: all new assertions PASS (`AGENTS base re-synced`, `old base line removed`, `foreign region preserved`, `base region still present`, `AGENTS.md stable on re-run`); `FAIL=0`, exit 0.

- [ ] **Step 3: Run the full test suite**

Run: `for t in tests/test_*.sh; do echo "== $t =="; bash "$t" || echo "FAILED: $t"; done`
Expected: every test file ends `FAIL=0`; no `FAILED:` line printed. In particular `tests/test_caveman_wiring.sh` and `tests/test_codex_hooks.sh` still pass (the AGENTS.md change must not disturb caveman wiring).

- [ ] **Step 4: Commit**

```bash
git add tests/test_isolated.sh
git commit -m "test(home): cover base-region re-sync, coexistence, idempotency

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Real-launch verification (skills visible, rules honored)

**Files:** none (manual verification of runtime behavior the unit tests cannot reach).

This confirms the Risk in the spec: that Codex actually reads `$CODEX_HOME/skills` and `$CODEX_HOME/rules`.

- [ ] **Step 1: Confirm the binary is present**

Run: `test -x .codex-isolated/bin/codex && echo present || echo "run ./icodex.sh --install"`
Expected: `present`. If not, run `./icodex.sh --install` first.

- [ ] **Step 2: Build a scratch home and inspect the links**

`setup_codex_home` runs only on the default (run) path — `--help`, `version`, and `--install` short-circuit earlier in `main()` and never build the home. Drive the function directly against a scratch project root:

```bash
tmpproj="$(mktemp -d)"
cd "$tmpproj"
ICODEX_ROOT=/home/altuser/Документы/Project/icodex
source "$ICODEX_ROOT/lib/core/init.sh"
source "$ICODEX_ROOT/lib/config/isolated.sh"
setup_codex_home
ls -la "$ICODEX_HOME_DIR"/skills "$ICODEX_HOME_DIR"/rules
sed -n '1,3p' "$ICODEX_HOME_DIR/AGENTS.md"
```

Expected: `skills -> …/.codex-isolated/skills` and `rules -> …/.codex-isolated/rules` (both symlinks), and `AGENTS.md` begins with `<!-- icodex:base:start -->` followed by the base guidance.

- [ ] **Step 3: Confirm Codex sees the user skills**

Start an interactive Codex session in `$tmpproj` via `./icodex.sh` and confirm the user skills (`context-awareness`, `git-workflow`, `html-report`, `intent`, `mermaid-obsidian`) are listed/available. If Codex does not surface them, record the finding — variant A may need the per-skill fallback noted in the spec.

- [ ] **Step 4: Confirm rules consumption (or record the negative result)**

Verify whether Codex honors `$CODEX_HOME/rules/default.rules` (e.g. a `git` command is auto-allowed while `curl` prompts, per the policy). If Codex ignores `$CODEX_HOME/rules/`, the `rules` symlink is inert — per the spec Risk, drop the `_link_shared rules` line (revert that one line in `setup_codex_home` and its two test assertions) and note it. Do NOT block the skills/AGENTS work on this.

- [ ] **Step 5: Clean up the scratch home**

```bash
rm -rf "$tmpproj" "$ICODEX_HOME_DIR"
```

---

## Task 5: Update wiki docs

**Files:**
- Modify (via iwiki): `docs/wiki/architecture.md` (or the page iwiki maps `lib/config/isolated.sh` to)

- [ ] **Step 1: Re-ingest the changed source**

Invoke the `iwiki:iwiki-ingest` skill on `lib/config/isolated.sh` so the home-build description reflects the new `skills`/`rules` symlinks and the `AGENTS.md` base-region sync. Review the shown diff before accepting.

- [ ] **Step 2: Lint the wiki**

Invoke the `/iwiki-lint` skill. Expected: no broken `[[refs]]`, no orphan/stale pages introduced.

- [ ] **Step 3: Commit the doc update**

```bash
git add docs/wiki
git commit -m "docs(wiki): document CODEX_HOME skills/rules links and AGENTS base sync

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Definition of Done

- `setup_codex_home` symlinks `skills/` and `rules/` and syncs the `AGENTS.md` base region.
- `tests/test_isolated.sh` covers symlinks, base-region presence, re-sync, coexistence with a foreign region, and idempotency — and the full `tests/` suite passes.
- Real launch confirms user skills are visible; rules consumption verified (or the `rules` link reverted with a recorded rationale).
- `docs/wiki/` re-ingested and lint-clean.
- Caveman wiring untouched and still passing (`tests/test_caveman_wiring.sh`).
