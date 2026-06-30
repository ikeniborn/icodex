# IDD

## Overview

The IDD layer ports the IDD->SDD phase gates from iclaude into icodex.

It has three parts:

- `idd-gate.py`: a `PreToolUse` gate that blocks phase transitions until the
  upstream artifact is validated.
- `idd-nudge.py`: a `PostToolUse` advisory hook that suggests validating a newly
  written IDD artifact immediately.
- `check-intent`, `check-spec`, `check-plan`, `check-result`: standalone Codex
  skills under `.codex-isolated/skills/` that perform the validation steps.

See [[architecture#Default run path]] and [[config#CODEX_HOME isolation]] for how
the shared hooks and skills become visible inside each per-project `CODEX_HOME`.

## Hook wiring

`ensure_idd_wiring` lives in `lib/idd/idd.sh`.

It merges two hook entries into `$CODEX_HOME/hooks.json`:

- `PreToolUse`, matcher `Skill|apply_patch|Write|Edit`, command
  `python3 "$CODEX_HOME/hooks/idd-gate.py"`;
- `PostToolUse`, matcher `apply_patch|Write`, command
  `python3 "$CODEX_HOME/hooks/idd-nudge.py"`.

The merge is idempotent. It strips old IDD entries first, then adds exactly one
gate and one nudge entry when enabled. It runs after `ensure_caveman_wiring`, so
caveman's `UserPromptSubmit` hook and the base secret-guard hooks compose with IDD.

## Opt-out

IDD is on by default.

Set `ICODEX_IDD=off` to disable it. The value is case-insensitive. When disabled,
`ensure_idd_wiring` removes IDD hook entries. If the resulting `hooks.json` matches
the shared base file, the per-project home is restored to a symlink to
`.codex-isolated/hooks.json`; if other local hook merges remain, such as caveman,
the real home file is preserved.

## Gate behavior

`idd-gate.py` is fail-open for hook-level failures and malformed stdin, but blocks
invalid artifact validation state.

It records artifact ownership in `$CODEX_HOME/state/idd-sessions.json`, keyed by
absolute path, so one session is gated only by artifacts it wrote or claimed. It
extracts touched paths from `Write`, `Edit`, and Codex `apply_patch` payloads using
`_codex_paths.py`. Plan creation can resolve `chain.spec` from an `apply_patch`
Add File body, including raw-string and dict-shaped payloads.

The gate checks the same frontmatter contract that the validator skills write:
`review.intent_hash`, `review.spec_hash`, `review.plan_hash`, and
`result_check.plan_hash`. Hashing uses the validator-compatible body hash pipeline,
with paths passed safely to bash as argv.

## Nudge behavior

`idd-nudge.py` is advisory and always exits 0.

When a `Write` or `apply_patch` touches an intent, spec, or plan artifact that is not
validated for its current body, it emits `PostToolUse` `additionalContext` asking the
agent to dispatch a clean-context subagent to run the corresponding `check-*` skill.
Validated artifacts stay silent. Malformed artifact frontmatter is treated as
unvalidated and nudges; malformed hook stdin stays silent.

## Validator skills

The four validators are standalone skills:

- `check-intent`: validates `docs/superpowers/intents/*-intent.md`;
- `check-spec`: validates `docs/superpowers/specs/*-design.md`;
- `check-plan`: validates `docs/superpowers/plans/*.md`;
- `check-result`: reconciles a plan with the implementation diff before finishing.

They live in `.codex-isolated/skills/`, and `setup_codex_home` symlinks that shared
directory into each per-project `CODEX_HOME/skills`. This is required for Codex to
list them in the model-visible skill catalog.

## Tests

Coverage lives in:

- `tests/test_idd_gate.sh`;
- `tests/test_idd_nudge.sh`;
- `tests/test_idd_wiring.sh`;
- `tests/test_idd_skills.sh`;
- `tests/test_isolated.sh` for the shared `skills` symlink.
