---
review:
  spec_hash: 88e206f29d098b86
  last_run: 2026-07-01
  phases:
    - name: structure
      status: passed
    - name: coverage
      status: passed
    - name: clarity
      status: passed
    - name: consistency
      status: passed
  findings: []
chain:
  intent: null
---
# Design: unify the icodex IDD→SDD chain (port chain-gate.py + check-chain + fix-intent)

**Date:** 2026-07-01
**Status:** draft
**Topic:** icodex-idd-unify

## Objective

icodex already ports the IDD→SDD phase gate from iclaude, but in the *older split
architecture*: two hooks (`idd-gate.py` + `idd-nudge.py`), four validator skills
(`check-intent` / `check-spec` / `check-plan` / `check-result`), and one intent-capture
skill (`intent`). iclaude has since consolidated these into a *unified architecture*:

- one hook `chain-gate.py` (single file, branches on hook event: PreToolUse gate,
  PostToolUse nudge) that replaces `idd-gate.py` + `idd-nudge.py`;
- one validator skill `check-chain` (four stage profiles over a shared core) that
  replaces the four `check-*` skills;
- one intent-capture skill `fix-intent` that replaces `intent`.

The working tree has already **deleted** the old split artifacts (`idd-gate.py`,
`idd-nudge.py`, `check-intent/spec/plan/result`, `intent`) and pre-migrated the
`AGENTS.md` Task-Log wording to `/check-chain`. This design **completes** the
migration: add the codex-adapted unified files, rewire, and update tests + docs so the
whole suite stays green.

This is a re-sync/upgrade, not a first port. Keeping icodex in lockstep with iclaude's
unified shape makes future syncs a near-mechanical copy.

## Desired Outcomes

- `.codex-isolated/hooks/chain-gate.py` exists and enforces the same gate/nudge behavior
  the deleted split hooks did, driven off the same frontmatter contract.
- `.codex-isolated/skills/check-chain/SKILL.md` and `.../fix-intent/SKILL.md` exist and
  are listed in the codex skill catalog inside a per-project `CODEX_HOME`.
- `lib/idd/idd.sh` wires exactly one gate command and one nudge command, both pointing at
  `chain-gate.py`, and the opt-out (`ICODEX_IDD=off`) still restores the shared base.
- `tests/test_idd_gate.sh`, `test_idd_nudge.sh`, `test_idd_wiring.sh`,
  `test_idd_skills.sh` pass against the unified files; the full `tests/*.sh` suite has no
  regressions.
- `docs/wiki/idd.md` describes the unified architecture; `docs/TODO.md` carries the
  migration row.

## Non-goals

- No change to the IDD *validation semantics* (phase checklists, hashing, severities,
  ledger ownership, fail-open policy). Behavior is preserved; only the file/skill shape
  and codex adaptation change.
- No change to caveman, iwiki, secret-guard, or the launcher outside the IDD wiring.
- No new IDD features beyond what iclaude's unified source already has.

## Architecture

### Component map

```
.codex-isolated/hooks/chain-gate.py     (new)  gate (Pre) + nudge (Post), one file
.codex-isolated/hooks/_codex_paths.py   (kept) apply_patch/Write/Edit path extraction
.codex-isolated/skills/check-chain/     (new)  unified validator, 4 stage profiles
.codex-isolated/skills/fix-intent/      (new)  intent capture, runs before brainstorming
lib/idd/idd.sh                          (edit) wire chain-gate.py to Pre + Post
tests/test_idd_{gate,nudge,wiring,skills}.sh  (edit) target unified files
.codex-isolated/AGENTS.md               (edit) finish IDD/skill references
docs/wiki/idd.md                        (edit) unified architecture
docs/TODO.md                            (edit) migration row
```

### chain-gate.py — codex adaptation

Port the unified logic from iclaude `chain-gate.py`, then apply the codex layer that the
deleted `idd-gate.py` / `idd-nudge.py` already established:

1. **Event discrimination via argv, not `hook_event_name`.** There is no evidence codex
   passes `hook_event_name` on stdin (the existing hooks are single-event and never read
   it). The wiring routes two hooks.json entries into the same file:
   - PreToolUse  → `python3 "$CODEX_HOME/hooks/chain-gate.py"`
   - PostToolUse → `python3 "$CODEX_HOME/hooks/chain-gate.py" --post`
   `--post` in `sys.argv` deterministically selects the nudge branch. Fallback order when
   the flag is absent: `data["hook_event_name"]` → `"PostToolUse" if "tool_response" in
   data else "PreToolUse"` (matches the iclaude heuristic, so behavior is unchanged if
   codex ever does send the field).

2. **Ledger under `CODEX_HOME`.** `ledger_path()` reads `CODEX_HOME` (not
   `CLAUDE_CONFIG_DIR`) → `$CODEX_HOME/state/idd-sessions.json`. Unset → fail-open.

3. **Codex tool shapes.** `from _codex_paths import extract_paths, patch_text_from_input`.
   Gated tool set is `("apply_patch", "Write", "Edit")`. Carry over `patch_added_body()` /
   `patch_or_content()` from the deleted `idd-gate.py` so a plan created via `apply_patch`
   Add File can resolve `chain.spec` from the patch body (this is a codex-only feature the
   iclaude source lacks; `test_idd_gate.sh` cases 4–5 depend on it).

4. **Preserve icodex hardening (fail-closed on malformed schema).** The iclaude source
   relaxed some guards; the icodex tests assert the stricter behavior. Keep:
   - malformed / unclosed frontmatter, invalid YAML → gate **blocks**, nudge **emits**
     (treated as unvalidated), never fail-open;
   - non-dict `phases`, non-list `findings` → block / nudge.
   Body-hash pipeline shells out to the same bash as the validators, with the path passed
   as `argv` (`bash -c '… "$1" …' -- "$path"`) so shell metacharacters in a filename never
   execute (asserted by both gate and nudge tests).

5. **fix strings in codex form.** Skill invocation in codex is by name + argument, no
   slash. `fix` becomes `check-chain intent` / `check-chain spec` / `check-chain plan` /
   `check-chain result`. Block/nudge text: "dispatch a clean-context subagent to invoke
   the check-chain skill with argument `<stage>`, collect verdicts in the main session".

6. **Exit codes / fail-open** unchanged: gate 0=allow / 2=block; nudge always 0
   (JSON on stdout = nudge, empty = silent); any internal exception → fail-open (gate exit
   0, nudge exit 0).

7. Comments in English (docs language).

### check-chain skill — codex adaptation

Port iclaude `check-chain/SKILL.md` with its shared core (canonical hashing, Step 0
quick-exit, scope resolution, phase execution, final verdict, HTML report, TODO upsert)
and the four stage profiles (intent / spec / plan / result) verbatim in logic. Codex
edits:

- `name: check-chain`; description/triggers phrased for codex invocation (skill name +
  stage argument, drop the `/check-chain` slash examples where they imply a Claude slash
  command — keep them only as human shorthand in prose).
- Step 5 HTML report keeps `skill: html-report`, `mode: chain`, `tab: <stage>` — the
  `html-report` skill already exists in icodex; the four-tab report path is unchanged.
- Steps 0–4, 6 (frontmatter contract, `review:` / `result_check:` blocks, TODO upsert)
  are byte-compatible with what `chain-gate.py` reads — no drift.

### fix-intent skill — codex adaptation

Port iclaude `fix-intent/SKILL.md`. Codex edits:

- `name: fix-intent`; handoff points at `superpowers:brainstorming` (present in icodex).
- iwiki Step 0 is compatible — icodex ships the iwiki MCP server; keep the "skip silently
  if unavailable" contract.
- Intent doc template + Outcome Verification carried over unchanged.

### Wiring — lib/idd/idd.sh

Replace the two-command merge with a single-file, two-entry merge:

- `strip()` removes any prior IDD entries. To make the upgrade self-healing on first run,
  strip **both** the new `chain-gate.py` commands **and** the legacy `idd-gate.py` /
  `idd-nudge.py` commands.
- When enabled, `add()`:
  - `PreToolUse`, matcher `Skill|apply_patch|Write|Edit`, command
    `python3 "$CODEX_HOME/hooks/chain-gate.py"`, status "IDD phase gate";
  - `PostToolUse`, matcher `apply_patch|Write`, command
    `python3 "$CODEX_HOME/hooks/chain-gate.py" --post`, status "IDD nudge".
- Opt-out (`ICODEX_IDD=off`) strips both; if the result equals the shared base file, the
  per-project home is restored to a symlink (unchanged logic).

### Tests

- `test_idd_gate.sh`: `GATE` → `chain-gate.py`. Cases (skill gate, apply_patch spec→plan,
  chain.spec from patch, raw-string patch, malformed schema blocks, shell-quote safety,
  malformed stdin fail-open, unowned-session escape) are behavior-preserving — only the
  hook path changes.
- `test_idd_nudge.sh`: `NUDGE` → `chain-gate.py`, invoked with the `--post` flag; expected
  fix token `check-spec` → `check-chain`. All nudge cases (new artifact, apply_patch,
  non-artifact silent, malformed stdin silent, validated silent, stale hash, malformed
  review nudges, metachar safety) preserved.
- `test_idd_wiring.sh`: assertions on `idd-gate.py` / `idd-nudge.py` → `chain-gate.py`;
  add a check that the PostToolUse entry carries `--post`; idempotency (one gate entry);
  opt-out restores symlink; base + caveman hooks preserved.
- `test_idd_skills.sh`: replace the four `check_skill check-*` calls with checks for
  `check-chain` (single SKILL.md containing `name: check-chain`, a description, all of
  `intent_hash` / `spec_hash` / `plan_hash`, and the `result_check` stage marker) and
  `fix-intent` (`name: fix-intent`, a description, frontmatter parses). Do not assert
  per-stage `tab:` literals — the unified `check-chain` source carries a single templated
  `tab: <stage>` token, so the stage coverage is asserted via the hash keys + `result_check`.

### Docs

- `docs/wiki/idd.md`: rewrite Overview + Hook wiring + Gate/Nudge + Validator skills
  sections for the unified shape (one hook, one `check-chain` skill with four profiles,
  `fix-intent`); update the Tests list (same four files, new contract). Then
  `wiki_write_page` + `wiki_lint` per the AGENTS.md doc-keeping rule.
- `.codex-isolated/AGENTS.md`: verify no remaining reference to the old `check-*` /
  `intent` skill names or the split hooks in any IDD/check-runner passage; the Task-Log
  section is already migrated to `/check-chain`.
- `docs/TODO.md`: upsert row `icodex-idd-unify` (opened 2026-07-01).

## Data flow (unchanged semantics)

1. Author writes an IDD artifact (intent/spec/plan) via `apply_patch`/`Write`.
   → PostToolUse `chain-gate.py --post`: if the artifact is not validated for its current
   body → emit `additionalContext` nudging `check-chain <stage>`.
2. Agent dispatches a clean-context subagent → `check-chain <stage>` validates, writes the
   `review:` / `result_check:` frontmatter (body untouched), verdicts collected in main
   session.
3. Agent invokes the next chain skill (`brainstorming` → `writing-plans` →
   `executing-plans` → `finishing-a-development-branch`) or creates a downstream artifact.
   → PreToolUse `chain-gate.py`: resolves the session-owned upstream artifact; if its gate
   is closed (hash stale / phase not passed / open CRITICAL / malformed schema) → exit 2
   with a remediation message; else allow.

## Error handling

- **Gate (Pre):** fail-open on any internal exception or malformed stdin (exit 0). Blocks
  (exit 2) only on a resolvable, session-owned, invalid artifact. Malformed *artifact
  frontmatter* is fail-closed (block) — distinct from malformed *hook stdin* (fail-open).
- **Nudge (Post):** always exit 0; empty stdout on any error → never disrupts the write.
- **No `CODEX_HOME`:** ledger unreachable → every session owns nothing → all gates open
  (fail-open by construction).

## Testing strategy

- Unit/behavior: the four `test_idd_*.sh` scripts (above), run from a temp CWD with a
  synthetic `docs/superpowers` tree and a temp `CODEX_HOME` ledger.
- Regression: full `tests/*.sh` run — assert no other suite (caveman, iwiki, isolated,
  smoke) regresses from the wiring change.
- Integration smoke: launch path merges `chain-gate.py` into a per-project `hooks.json`
  (`test_idd_wiring.sh` covers the merge; `test_isolated.sh` covers the shared `skills`
  symlink so `check-chain` / `fix-intent` are catalog-visible).

## Acceptance criteria (Done when)

- `chain-gate.py`, `check-chain/SKILL.md`, `fix-intent/SKILL.md` present and
  codex-adapted per the sections above.
- `lib/idd/idd.sh` wires one gate + one nudge entry, both `chain-gate.py`, nudge with
  `--post`; opt-out restores the shared symlink.
- `bash tests/test_idd_gate.sh`, `test_idd_nudge.sh`, `test_idd_wiring.sh`,
  `test_idd_skills.sh` all exit 0; full `tests/*.sh` green.
- `docs/wiki/idd.md` updated (unified), `wiki_lint` clean; `docs/TODO.md` row present;
  no stray reference to the deleted split files in tracked sources.
