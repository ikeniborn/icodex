---
title: icodex IDD→SDD integration design
date: 2026-06-30
status: draft
review:
  spec_hash: 53cf73c1480846c0
  last_run: 2026-06-30
  phases:
    structure:    { status: passed }
    coverage:     { status: passed }
    clarity:      { status: passed }
    consistency:  { status: passed }
  findings: []
chain:
  intent: null
---

# icodex IDD→SDD integration

## Objective

Port the iclaude IDD→SDD enforcement system — the 4 `/check-*` validator commands
plus the two phase-gate hooks `idd-gate.py` / `idd-nudge.py` — into icodex. The
central constraint: **Codex has no slash commands**, so each `/check-*` command
becomes a Codex skill, and the hooks are re-pointed at Codex tool names and the
Codex home layout.

Scope decisions (confirmed with the user):

- **Full parity** — all 4 validators + both hooks + the session ownership ledger.
- **On by default, controlled via `ICODEX_IDD`** — process control over
  specifications applies on every session without having to opt in, but it is
  still governed by an `ICODEX_*` env variable (project convention, cf.
  `ICODEX_CAVEMAN_MODE` / `ICODEX_MODE`). IDD is enabled unless `ICODEX_IDD=off`
  (opt-out). A small per-launch wiring step (mirroring caveman) applies this.
- **Subagent validators** — `check-*` runs in a clean-context subagent (Codex
  `multi_agent = true`); verdicts are collected in the main session. This
  preserves the author/reviewer separation that is the point of the original
  system.

## Background — the source system

The iclaude IDD→SDD chain enforces that each design artifact is validated before
the chain advances:

```
intent skill → /check-intent → brainstorming → /check-spec → writing-plans
  → /check-plan → executing-plans / subagent-driven-development
  → /check-result → finishing-a-development-branch
```

Two hooks enforce it:

- `idd-gate.py` (PreToolUse, matcher `Skill|Write|Edit|MultiEdit`) — **only**
  blocks/allows; never validates. It blocks a chain transition (Skill call) or a
  downstream write (spec→plan file creation, plan→impl code edit) while the
  upstream artifact has not passed validation: no `review:`/`result_check:`
  block, body hash stale, a phase not `passed`, or an open `CRITICAL` finding.
  Ownership is session-scoped via a ledger (`CLAUDE_CONFIG_DIR/state/idd-sessions.json`);
  a session is gated only by artifacts it owns. Fail-open on any internal error.
- `idd-nudge.py` (PostToolUse, matcher `Write`) — advisory. After an artifact is
  written, injects `additionalContext` suggesting the matching `/check-*` until
  the artifact validates for its current body (then falls silent — no loop).

The validators (`/check-*`) are deterministic, phase-based, hash-cached checkers
that read/write only the artifact's `review:` frontmatter (never the body), and
emit an HTML chain report via the `html-report` skill.

## icodex target — established mechanisms

Research confirmed the host facts the port relies on:

| Capability | Evidence | Consequence |
|------------|----------|-------------|
| Codex honors Claude-style `hooks.json` (PreToolUse/PostToolUse/UserPromptSubmit, `matcher`, exit 2 = block, `additionalContext`) | `.codex-isolated/hooks.json`, `tests/test_codex_hooks.sh` | both hooks port directly |
| Home `hooks.json` and `hooks/` are **symlinks** to the shared `.codex-isolated/` store | `lib/config/isolated.sh` (`_link_shared hooks`, `_link_shared hooks.json`); confirmed on a live home | the ported scripts under shared `hooks/` reach every home via the symlink; the `hooks.json` entries are merged per-launch by `ensure_idd_wiring` (which breaks the home `hooks.json` symlink into a real file when merging, exactly as caveman already does) |
| Caveman merges its `UserPromptSubmit` entry onto the **shared base** when enabled, and restores the symlink when disabled | `lib/caveman/caveman.sh` | `ensure_idd_wiring` runs after `ensure_caveman_wiring` and is the final authority on the IDD entries, so the two compose without changing caveman code |
| Codex supports skills natively | `.codex-isolated/skills/` (incl. the existing `intent` skill) | commands → skills is a proven path |
| Codex Skill invocation = `Skill(skill="…")` | `intent/SKILL.md` body | the `Skill` matcher *may* reach the gate (see Risks) |
| Codex multi-agent | `config.toml [features] multi_agent = true` | subagent validators viable |
| Codex passes `session_id` in hook payload | `caveman-hook.py`, `tests/test_caveman_hook.sh` | ledger ownership works |
| PyYAML present | `python3 -c import yaml` → 6.0.1 | the gate's frontmatter parse works — enforcement is real, not perpetually fail-open |
| Codex edit tool is `apply_patch` (`tool_input.patch`, not `file_path`) | `tests/test_codex_hooks.sh`, `block-secrets.py` | gate must extract paths from the patch |

## Architecture

The integration adds assets in the shared store plus one small launch-path wiring
module that toggles the hooks per `ICODEX_IDD`:

```
.codex-isolated/
  hooks/idd-gate.py                 # ported gate
  hooks/idd-nudge.py                # ported nudge
  skills/check-intent/SKILL.md      # validators (always present)
  skills/check-spec/SKILL.md
  skills/check-plan/SKILL.md
  skills/check-result/SKILL.md
lib/idd/idd.sh                      # ensure_idd_wiring (default-on; off when ICODEX_IDD=off)
```

The shared `hooks.json` is left unchanged. At launch, `ensure_idd_wiring`
(mirroring `lib/caveman/caveman.sh`) merges the idd-gate (PreToolUse) and
idd-nudge (PostToolUse) entries into the per-project home `hooks.json` unless
`ICODEX_IDD=off`. It runs **after** `ensure_caveman_wiring`, making it the final
authority on the IDD entries: whether caveman left the home `hooks.json` as a
symlink to the shared base or as a real merged file, the IDD step adds (or, when
opted out, strips) its own entries on top. The `hooks/` directory is itself a
symlink to the shared store, so the ported scripts are available regardless.

Data flow is unchanged from the source: the hooks never validate (block/allow +
advisory only); a `check-*` skill running in a clean-context subagent validates;
verdicts are collected in the main session; all cross-step communication is
through artifact frontmatter (`review.{intent,spec,plan}_hash`, `phases`,
`findings`; `result_check.verdict`) and the ownership ledger
`$CODEX_HOME/state/idd-sessions.json`.

## Component 1 — validator skills

Each `/check-*` command becomes `.codex-isolated/skills/check-<x>/SKILL.md`,
format matching the existing `intent` skill (frontmatter `name` + `description`).
The command body (phase algorithm, canonical body/section hashing via the
`awk … | sha256sum | cut -c1-16` Bash pipeline, the `review:`/`result_check:`
frontmatter contract, the closed per-phase checklists, the final `html-report`
call) ports near-verbatim. Changes:

- **Trigger via description, not slash.** The `description` carries the activation
  phrases (e.g. "check the intent doc", "/check-intent", "validate the spec
  against tasks") so Codex activates the skill by intent.
- **Subagent execution, self-described.** Each skill states that it runs in a
  clean-context subagent and that verdicts are reported back to the main session.
  The check-runner protocol is embedded in the skills and in the hook messages
  (below), not in a separate global doc — this avoids depending on a
  global-`AGENTS.md` seeding path that is not currently wired for Codex homes.
- **Self-contained.** The advisory `alignment` phase's `iwiki` / `lat_*` MCP
  calls are skipped silently when the tools are unavailable (parity).
- **Shared chain key.** All four skills converge on one `<topic>` derived from
  the artifact basename (strip date prefix, strip `-intent`/`-design`/`-plan`
  suffix) so the single `docs/superpowers/reports/<topic>-results.html` chain
  report merges per-tab — identical rule to the source commands.

The `html-report` skill these depend on already exists in `.codex-isolated/skills/`.

**Open item (resolve in the plan):** how standalone `.codex-isolated/skills/`
entries are activated in a Codex session. A live home shows only `skills/.system`
(built-ins); no `lib/` code links the five existing standalone skills into a
home. The `check-*` skills are placed alongside the existing `intent` /
`html-report` skills and share whatever activation path those use; if that path
turns out to be unwired, wiring it is a prerequisite tracked by the plan.

## Component 2 — ported hooks

Both hooks are copied to `.codex-isolated/hooks/` with fail-open preserved (a bug
in the gate must not break every tool call). Five targeted edits:

| # | Concern | Source (iclaude) | Port (icodex) |
|---|---------|------------------|---------------|
| 1 | Ledger path | `CLAUDE_CONFIG_DIR/state/idd-sessions.json` | `CODEX_HOME/state/idd-sessions.json` |
| 2 | Path extraction | `file_path` from `Edit/Write/MultiEdit` | reuse `patch_text_from_input()` + `patch_paths()` + `path_fields()` from `block-secrets.py` to parse `apply_patch` (`Add/Update/Delete File:`) and `Write/Edit` |
| 3 | Tool names | `Write/Edit/MultiEdit` | `apply_patch/Write/Edit` |
| 4 | Validator reference in messages | "run /check-intent" | "dispatch a clean-context subagent to invoke the check-intent skill" (the check-runner protocol, inline) |
| 5 | spec→plan trigger | `Write` of a plan file | `apply_patch` Add File **or** `Write` of a plan file |

Unchanged: `GATE_MAP` (the gated skills `brainstorming` / `writing-plans` /
`executing-plans` / `subagent-driven-development` / `finishing-a-development-branch`
all exist in the vendored superpowers plugin); `normalize_skill`
(`superpowers:writing-plans` → `writing-plans`); the body-hash Bash pipeline; the
ledger ownership model (`record_owner` / `owns` / `resolve_candidate`); the
`evaluate_gate` predicate; `BLOCK_ON = {CRITICAL}`; the impl-gate freshness
window. The nudge keeps its "silent once validated" loop-guard.

`handle_write` must apply its spec→plan and plan→impl predicates **per extracted
path** (an `apply_patch` may touch several files), rather than a single
`file_path`.

### Hook registration

The two entries are merged into the per-project home `hooks.json` by
`ensure_idd_wiring` (Component 3) — the committed shared `hooks.json` is left
unchanged:

- `PreToolUse` += `{ matcher: "Skill|apply_patch|Write|Edit", command: idd-gate.py }`
- `PostToolUse` += `{ matcher: "apply_patch|Write", command: idd-nudge.py }`

(the nudge matcher includes `apply_patch` because a producing skill may create an
artifact via `apply_patch` Add File rather than `Write`).

## Component 3 — wiring (`lib/idd/idd.sh`)

A small launch-path module mirroring `lib/caveman/caveman.sh`. One orchestrator,
`ensure_idd_wiring`:

- **Default-on / opt-out.** Enabled unless `ICODEX_IDD=off` (project convention is
  the `ICODEX_*` prefix, cf. `ICODEX_CAVEMAN_MODE` / `ICODEX_MODE`). Unset or any
  value other than `off` → enabled.
- **Enabled** → idempotently merge the idd-gate (PreToolUse, matcher
  `Skill|apply_patch|Write|Edit`) and idd-nudge (PostToolUse, matcher
  `apply_patch|Write`) entries into the home `hooks.json` (the
  `_caveman_enable_hooks_json` `present`-check pattern, keyed on the hook
  `command` string).
- **Opted out (`ICODEX_IDD=off`)** → idempotently remove those two entries from
  the home `hooks.json`, restoring the shared symlink when nothing else broke it.
- **Ordering.** Called from `icodex.sh` after `ensure_caveman_wiring` so it is the
  final authority on the IDD entries; the merge is additive and order-stable, so
  the two never clobber each other.

The other non-asset change is **`.gitignore` whitelisting** for the newly tracked
paths under `.codex-isolated/` (`hooks/idd-*.py`, `skills/check-*/`), following
the existing whitelist model (cf. the caveman directory whitelist commit).

## Error handling

Fail-open everywhere (parity, opposite of fail-closed `block-secrets.py`): broken
stdin, missing `yaml`, unreachable/corrupt ledger, missing `CODEX_HOME`, or any
internal exception → the gate exits 0 (allow) and the nudge stays silent. A
defective gate degrades to "no enforcement", never to "every tool call breaks".

## Risks

1. **Skill-transition gate depends on Codex emitting `PreToolUse` for `Skill`.**
   No direct evidence Codex fires PreToolUse on a Skill invocation (the existing
   `block-secrets` matcher does not include `Skill`). If it does not fire, the
   chain-transition gate is inert, but the **Write/apply_patch gate** (spec→plan
   file creation, plan→impl code edit) still fires and is the load-bearing
   enforcement — no worse than the source's hotfix-path behavior, not a
   regression. Mitigation: a probe test during implementation confirms whether
   the `Skill` matcher fires; correctness does not depend on it.

2. **Artifact-creation tool in Codex.** Skills may create artifacts via
   `apply_patch` (Add File) rather than `Write`. The nudge matcher includes
   `apply_patch` and both hooks parse the patch for target paths (reused
   `block-secrets` helpers), so artifact birth is detected regardless of tool.

3. **Standalone-skill activation (see Component 1 open item).** If
   `.codex-isolated/skills/` entries are not actually surfaced to Codex sessions,
   the validators cannot run as skills. Confirmed as the first implementation
   step; placement mirrors the existing `intent` skill.

4. **PyYAML in the hook runtime.** Confirmed present (6.0.1). If a host lacks it
   the gate fail-opens (no enforcement) rather than erroring — acceptable
   degradation, flagged so the implementation can surface a one-time warning.

## Testing

Standalone `tests/test_idd_*.sh` (sourcing `tests/helpers.sh`, no network,
temp-dir filesystem side effects):

- `test_idd_gate.sh` — block on an invalid artifact (open CRITICAL / stale body
  hash / a phase not `passed`); allow on a fully-validated artifact; fail-open on
  malformed stdin / missing ledger; `apply_patch` path extraction (Add File of a
  plan → spec gate evaluated).
- `test_idd_nudge.sh` — nudge emitted after an artifact write; silence once the
  artifact validates for its current body (no loop); fail-open on garbage.
- `test_idd_wiring.sh` — `ensure_idd_wiring` with `ICODEX_IDD` unset/non-`off`
  merges both entries into the home `hooks.json` (valid JSON, idempotent across
  repeated runs); `ICODEX_IDD=off` removes them; run after a caveman merge, the
  result contains block-secrets, redact-secrets, idd-gate, idd-nudge, and the
  caveman entry (composition check), and the opt-out path strips only the IDD
  entries.

## Out of scope

- Porting `block-secrets.py` / `redact-secrets.py` (already in icodex).
- Changing the validator phase algorithms or checklists (verbatim parity).
- A standalone CLI surface for the validators (invocation is via the Skill tool /
  subagent only — there are no Codex slash commands by design).
- Additional `ICODEX_IDD` sub-options beyond the on/off toggle (e.g. per-severity
  strictness): YAGNI; the single opt-out variable is the whole control surface.
