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
