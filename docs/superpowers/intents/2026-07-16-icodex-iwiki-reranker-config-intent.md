---
review:
  intent_hash: ab3f6219df317890
  last_run: 2026-07-16
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
---
# Intent: icodex iwiki reranker config

**Date:** 2026-07-16
**Status:** approved

## Objective

Update icodex's built-in `iwiki-mcp` Codex server wiring to match the newer upstream `iwiki-mcp` configuration surface.

The immediate need is that upstream `iwiki-mcp` added reranker support and new environment variables, but icodex currently exposes only the older optional `ICODEX_IWIKI_*` subset in generated Codex `config.toml`. At the same time, upstream documentation now states that Codex should pass an explicit project directory through `--project` or `IWIKI_PROJECT_DIR` because Codex does not reliably launch the MCP server from the project root. icodex should therefore add the missing `ICODEX_IWIKI_*` passthrough variables and make project binding deterministic by generating `IWIKI_PROJECT_DIR` from the known project root.

## Desired Outcomes

- Generated per-home Codex `config.toml` includes the newer iwiki server variables only when the matching `ICODEX_IWIKI_*` values are set in `.codex_config`.
- Generated per-home Codex `config.toml` includes `IWIKI_PROJECT_DIR` pointing at the real project root without requiring the user to configure it manually in `.codex_config`.
- In Codex sessions, `wiki_status` reports the intended project directory and the expected project `read` and `write` binding.
- Reranker support can be enabled through `.codex_config`, and when it is unset, iwiki search keeps the previous non-reranked behavior.
- `.codex_config.example` documents the current iwiki configuration surface, including reranker-related variables and generated project-dir behavior.

## Health Metrics

- `IWIKI_LLM_KEY` remains secret and is not written literally into generated Codex `config.toml`, tracked files, docs, tests, or examples.
- Codex launch does not fail when iwiki required settings are incomplete; iwiki wiring continues to warn and skip instead.
- Unset optional iwiki variables are omitted from generated TOML so upstream server defaults still apply.
- Existing project-root `.iwiki.toml` files remain user-owned and are not overwritten.
- Focused iwiki Bash tests remain green, especially wiring, binding, and env-mapping tests.

## Strategic Context

- Interacts with: `lib/iwiki/iwiki.sh`, `lib/config/env.sh`, `tests/test_iwiki_wiring.sh`, `tests/test_iwiki_env.sh`, `tests/test_iwiki_binding.sh`, `.codex_config.example`, `.codex_config`, `docs/superpowers/`, `docs/TODO.md`, the icodex iwiki domain page `iwiki-mcp-integration`, and upstream `iwiki-mcp` configuration documented in `../iwiki-mcp/README.md` and `../iwiki-mcp/src/iwiki_mcp/engine/config.py`.
- Priority trade-off: trust first, then implementation speed and maintenance cost.

## Constraints

### Steering (behavioral guidance)

- Follow the upstream `iwiki-mcp` environment reference instead of guessing variable names.
- Preserve the existing `ICODEX_IWIKI_*` wrapper pattern for `.codex_config`.
- Prefer adding passthrough variables to the existing optional-variable mechanism over creating one-off branches for each new setting.
- Keep iwiki enabled as the existing always-on integration when required settings resolve; do not add a new enable flag.
- Update `.codex_config.example` so users can discover the new settings without reading source code.

### Hard (architectural enforcement)

- Do not write secrets into tracked files or generated Codex `config.toml`; `IWIKI_LLM_KEY` must continue to flow through `env_vars`.
- Keep raw `IWIKI_*` keys rejected by `.codex_config`; user configuration must use the `ICODEX_IWIKI_*` wrapper.
- Generate `IWIKI_PROJECT_DIR` from `$ICODEX_PROJECT_ROOT`; do not require or accept a manual `ICODEX_IWIKI_PROJECT_DIR` value in `.codex_config`.
- Do not overwrite an existing project-root `.iwiki.toml`.
- Do not touch unrelated dirty user changes, including the currently modified `.iwiki.toml`.

## Autonomy Zones

- Full autonomy (reversible, low risk): choose exact focused test assertions, update `.codex_config.example`, update English docs/spec wording, and add optional iwiki variables that are directly present in upstream `iwiki-mcp` documentation or config code.
- Guarded (log + confidence threshold): change `lib/iwiki/iwiki.sh` TOML generation, required-setting guard behavior, and generated project-dir behavior, provided focused tests verify the result.
- Proposal-first (needs approval): change the secret-forwarding model, expose variable names that conflict between upstream README and config code, add a new enable/disable flag, or change how Codex invokes `iwiki-mcp` from `command` to `args`.
- No autonomy (human only): change real secret values in `.codex_config`, delete or overwrite user-owned `.iwiki.toml`, run destructive git operations, or push/merge without explicit approval.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if: any generated or tracked artifact contains the literal iwiki API key.
- Halt if: upstream `iwiki-mcp` requires an incompatible config model that cannot be represented by the existing `ICODEX_IWIKI_*` wrapper plus generated `IWIKI_PROJECT_DIR`.
- Halt if: focused tests show generated `IWIKI_PROJECT_DIR` points at `CODEX_HOME` or any directory other than the real project root.
- Escalate if: upstream README and `Config.load()` disagree on a variable name or default relevant to reranking, search mode, seed retrieval, chat classification, or project-dir resolution.
- Done when: focused iwiki tests pass and show the generated TOML contains expected new optional variables when set.
- Done when: focused iwiki tests pass and show unset optional variables are omitted.
- Done when: focused iwiki tests pass and show `IWIKI_PROJECT_DIR` is generated from the project root without a manual `.codex_config` setting.
- Done when: `.codex_config.example` documents the current iwiki configuration surface, including reranker support and generated project-dir behavior.
- Done when: repository docs and the icodex iwiki page agree with the changed behavior.
