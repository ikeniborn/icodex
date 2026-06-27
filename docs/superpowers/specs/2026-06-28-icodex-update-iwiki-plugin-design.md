---
review:
  spec_hash: 320e4f616a95a071
  last_run: 2026-06-28
  phases:
    structure:   { status: passed }
    coverage:    { status: passed }
    clarity:     { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: null
---

# icodex --update Hardening and iwiki Plugin Integration Design

> Date: 2026-06-28
> Status: Approved (design phase)
> Scope: Keep `--update` binary-only, and add a full git-delivered Codex port of `iwiki`

## 1. Purpose

This design covers two related changes to `icodex`:

1. Harden the existing `--update` path so it is clearly and verifiably limited to updating the Codex binary and `.codex-lockfile.json`.
2. Add `/home/ikeniborn/Documents/Project/ai-wiki-plugin` as a vendored Codex plugin in `icodex`, with skills, engine, and hook automation.

The integration follows the existing Superpowers delivery model: the plugin cache is committed to git, the launcher rewrites machine-specific marketplace `source` paths at runtime, and users do not run `codex plugin add` after cloning.

## 2. Decisions

- `--update` updates only the Codex release asset, installed binary stamp, and `.codex-lockfile.json`.
- `--update` does not update vendored plugins, user skills, `.codex-isolated/config.toml.example`, or plugin cache directories.
- `iwiki` is added through a dedicated `lib/plugin/iwiki.sh` module beside `lib/plugin/superpowers.sh`.
- The existing Superpowers wiring is not refactored into a shared plugin framework in this iteration.
- `--install` and `--update` remain binary-only paths and do not call `ensure_iwiki_wiring`.
- A Codex hook probe is required before enabling the full iwiki hook port, because local examples confirm `PostToolUse` and `Stop` hooks, but not every iwiki event.

The dedicated `iwiki.sh` module is intentionally less abstract than a generic plugin-wiring framework. This reduces risk to the existing Superpowers integration and keeps the first `iwiki` port focused. The duplication is acceptable until a third vendored plugin needs the same pattern.

## 3. Current Context

`icodex` is a bash wrapper around a pinned OpenAI Codex binary. The current code already has:

- `--update` parsing in `lib/command/args.sh`.
- An `update` branch in `icodex.sh`.
- `install_ensure --update` behavior in `lib/binary/install.sh`.
- Offline tests in `tests/test_args.sh` and `tests/test_install.sh`.
- A vendored Superpowers plugin with launch-time `source` rewriting in `lib/plugin/superpowers.sh`.

The `ai-wiki-plugin` project is currently a Claude-oriented plugin. It contains:

- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
- Four skills: `iwiki-init`, `iwiki-ingest`, `iwiki-query`, and `iwiki-lint`.
- A Python engine under `engine/` run via `uv`.
- Hook automation under `hooks/`.
- Slash command markdown files under `commands/`.

The Claude plugin uses `CLAUDE_PLUGIN_ROOT` and `CLAUDE_CONFIG_DIR`. The Codex port must not depend on those variables.

## 4. CLI Behavior

`./icodex.sh --update` continues to:

1. Load `.codex_config`.
2. Apply API key environment handling.
3. Parse args.
4. Run `require_tools`.
5. Honor `ICODEX_PROXY` for GitHub release API and asset download.
6. Run `setup_codex_home`.
7. Run `install_ensure --update`.
8. Refresh the `icodex` symlink.
9. Exit.

It must not:

- Call `ensure_superpowers_wiring`.
- Call `ensure_iwiki_wiring`.
- Run `codex plugin add`.
- Modify `.codex-isolated/plugins/`.
- Modify `.codex-isolated/skills/`.
- Modify `.codex-isolated/config.toml.example`.

The user-facing docs should describe `--update` as Codex-binary update only.

## 5. iwiki Architecture

`icodex.sh` sources both plugin modules:

```text
lib/plugin/superpowers.sh
lib/plugin/iwiki.sh
```

The default launch path runs plugin wiring before launching Codex:

```text
setup_codex_home
ensure_superpowers_wiring
ensure_iwiki_wiring
install_ensure
proxy_apply
launch_codex
```

`ensure_iwiki_wiring` is scoped to the `iwiki` plugin:

1. If `.codex-isolated/config.toml` is missing, copy it from `.codex-isolated/config.toml.example`.
2. Find the vendored cache directory matching `.codex-isolated/plugins/cache/*/iwiki/*/`.
3. Derive the marketplace name from the cache path, for example `ai-wiki`.
4. Rewrite only the `source = ...` line in `[marketplaces.<derived-name>]`.
5. Use the absolute cache path from the current clone.
6. If no cache exists, log a warning and continue.

The committed config template gains iwiki wiring:

```toml
[marketplaces.ai-wiki]
source_type = "local"
source = "__ICODEX_ROOT__/.codex-isolated/plugins/cache/ai-wiki/iwiki/<ver>"

[plugins."iwiki@ai-wiki"]
enabled = true
```

The live `.codex-isolated/config.toml` remains runtime state. The template is the committed source of default wiring.

## 6. Vendored Plugin Layout

The Codex port of `iwiki` is committed under the existing plugin cache whitelist:

```text
.codex-isolated/plugins/cache/ai-wiki/iwiki/<version>/
├── .codex-plugin/plugin.json
├── skills/
│   ├── iwiki-init/SKILL.md
│   ├── iwiki-ingest/SKILL.md
│   ├── iwiki-query/SKILL.md
│   └── iwiki-lint/SKILL.md
├── engine/
│   ├── pyproject.toml
│   ├── uv.lock
│   └── iwiki_engine/
├── hooks/
│   ├── iwiki-bootstrap.py
│   ├── iwiki_common.py
│   ├── iwiki-recall.py
│   ├── iwiki-reindex.py
│   ├── iwiki-sync.py
│   └── iwiki-validate.py
└── hooks.json
```

The vendored copy excludes generated and environment-specific artifacts:

- `.git/`
- `.venv/`
- `.pytest_cache/`
- `__pycache__/`
- `*.pyc`

The `commands/` directory from the Claude plugin is not part of the required Codex port unless Codex slash-command support is confirmed separately. The four workflows are exposed through skills.

## 7. Codex Manifest

The new `.codex-plugin/plugin.json` declares:

- `name`: `iwiki`
- `version`: copied from the source plugin version at vendoring time
- `description`, `author`, `homepage`, `repository`, `keywords`, and `license` from the source plugin
- `skills`: `./skills/`
- `hooks`: `./hooks.json`, if Codex manifest probing confirms this key is recognized for local plugins

If hook discovery is based only on a root `hooks.json` file and not a manifest key, the manifest remains skills-only and `hooks.json` stays at the plugin root.

## 8. Skill Adaptation

The four iwiki skills are ported from Claude wording to Codex wording.

Path resolution inside skill shell snippets must:

1. Prefer an explicit plugin root environment variable if Codex provides one.
2. Fall back to an in-repo `engine/` directory when running from the plugin source tree.
3. Fall back to the newest `$CODEX_HOME/plugins/cache/*/iwiki/*/engine`.

The skills must not reference `CLAUDE_PLUGIN_ROOT` or `CLAUDE_CONFIG_DIR`.

`iwiki-ingest` keeps its guarded behavior:

- Read only the requested source path.
- Write or update a `docs/wiki/<topic>.md` page.
- Show the diff before reporting completion.
- Run `iwiki_engine index`.
- Append the canonical ingest record to `docs/wiki/.iwiki/log.jsonl`.

`iwiki-query` and `iwiki-lint` remain stop-on-halt workflows. If the engine reports missing `IWIKI_LLM_*`, the agent reports the halt message and does not fabricate answers.

## 9. Hook Port

The desired full hook set is:

- `SessionStart`: establish baseline and nudge `/iwiki-init` when a project has documentable source but no wiki.
- `UserPromptSubmit`: recall relevant `docs/wiki` sections for the prompt.
- `PreToolUse` with `Write|Edit|MultiEdit`: validate wiki page section structure.
- `PostToolUse` with `Write|Edit|MultiEdit`: mark source/wiki edits for later reindex.
- `Stop`: batch reindex changed wiki pages and remind about stale or missing wiki pages for sources touched in the session.

Before enabling all hooks, implementation must run a Codex hook probe fixture that confirms:

- Which event names are supported by the current pinned Codex binary.
- Whether relative hook commands run from plugin root.
- Which environment variables Codex provides to hook commands.
- Whether `hooks.json` is discovered automatically or through `.codex-plugin/plugin.json`.

Known local Codex examples confirm `PostToolUse` and `Stop`. They do not prove `SessionStart` or `UserPromptSubmit`, so those events require explicit verification.

If a desired event is unsupported by the current Codex binary, the plugin ships a degraded but explicit mode:

- Supported hooks remain enabled.
- Unsupported automation is documented as manual skill usage.
- No unsupported hook is silently represented as working.

## 10. Hook Runtime Adaptation

Python hook helpers must resolve paths without Claude-specific environment variables:

- Project root: prefer a Codex-provided project directory if present, otherwise use `git rev-parse --show-toplevel` from the hook process cwd.
- Plugin root: prefer a Codex-provided plugin root if present, otherwise derive from the hook script path.
- Codex home: use `$CODEX_HOME` for cache lookup and session state.
- Session state: store under `$CODEX_HOME/.cache/iwiki`.
- Engine lookup: prefer `<plugin-root>/engine`, then project-local `engine`, then newest `$CODEX_HOME/plugins/cache/*/iwiki/*/engine`.
- `uv`: use `$UV_BIN`, then `uv` from `PATH`.

The hooks remain fail-soft. A missing engine, missing `uv`, or missing `IWIKI_LLM_*` must not block normal Codex work, except for deliberate wiki section validation failures in `PreToolUse`.

## 11. Configuration

`.codex_config.example` documents iwiki settings but does not include secrets:

- `IWIKI_LLM_BASE_URL`
- `IWIKI_LLM_KEY`
- `IWIKI_EMBED_MODEL`
- `IWIKI_EMBED_DIMENSIONS`
- `IWIKI_TOP_K`
- `IWIKI_SCORE_THRESHOLD`
- `IWIKI_GRAPH_DEPTH`
- `IWIKI_CHUNK_SIZE`
- `IWIKI_CHUNK_OVERLAP`
- `IWIKI_SUMMARY_MAX_CHARS`
- `IWIKI_AUTO_BOOTSTRAP`
- `IWIKI_AUTO_QUERY`
- `IWIKI_AUTO_REINDEX`
- `IWIKI_AUTO_SYNC`
- `IWIKI_VALIDATE_SECTIONS`
- `IWIKI_SYNC_MAX_ASK`
- `UV_BIN`

Current config parsing only honors `ICODEX_*` keys. Therefore iwiki configuration has two viable implementation choices:

1. Extend `.codex_config` parsing to allow `IWIKI_*` and `UV_BIN`, then export them for Codex and hooks.
2. Document that iwiki variables must be exported in the shell or configured in Codex's own environment mechanism.

The preferred implementation is option 1 because it keeps isolated icodex configuration in one file. It must preserve the current safety property: parsed key-value lines only, never sourced.

## 12. Maintainer Workflow

A maintainer script vendors `iwiki` from `/home/ikeniborn/Documents/Project/ai-wiki-plugin` or an explicit source path:

```text
scripts/vendor-iwiki.sh <source-plugin-root>
```

The script:

1. Reads source plugin version.
2. Creates the destination cache path under `.codex-isolated/plugins/cache/ai-wiki/iwiki/<version>/`.
3. Copies `skills/`, `engine/`, `hooks/`, `README.md`, and required metadata.
4. Writes or updates `.codex-plugin/plugin.json`.
5. Writes or adapts `hooks.json`.
6. Removes generated artifacts and nested ignore files that would hide vendored files.
7. Verifies the vendored cache hygiene.

The maintainer script updates plugins only when explicitly run. It is not called by `--install` or `--update`.

## 13. Tests

### `--update`

- Existing arg parser test continues to assert `--update` maps to `ICODEX_CMD=update`.
- Existing install test continues to assert `install_ensure --update` resolves latest, installs, and rewrites `.codex-lockfile.json`.
- Add or preserve coverage that the `update` command path does not call plugin wiring.
- README and help text must describe `--update` as Codex-binary update only.

### `lib/plugin/iwiki.sh`

- Creates live config from `.codex-isolated/config.toml.example`.
- Rewrites only `[marketplaces.ai-wiki].source`.
- Does not touch `[marketplaces.superpowers-dev].source`.
- Is independent of process cwd.
- Is idempotent.
- Missing cache warns and continues.

### Vendored Plugin Hygiene

- `.codex-plugin/plugin.json` exists.
- `skills/iwiki-*` exist.
- `engine/pyproject.toml` exists.
- `hooks.json` exists when hooks are enabled.
- No `.git`, `.venv`, `.pytest_cache`, `__pycache__`, or `*.pyc` remains.
- `.gitignore` does not exclude the vendored iwiki cache.

### Hook Port

- Unit tests cover Python path resolution without `CLAUDE_*`.
- Hook probe fixture records supported events and relative command behavior.
- Supported hooks run without blocking normal work when `uv` or `IWIKI_LLM_*` are absent.
- `PreToolUse` validation blocks malformed wiki pages and fails open on internal errors.

### Engine

- Config-free commands such as `lint`, `status`, or `validate` run without `IWIKI_LLM_*`.
- Embedding-backed commands such as `index` and `search` are not part of the default offline test suite unless `IWIKI_LLM_*` are explicitly present.

## 14. Documentation

Update `README.md` to explain:

- `--update` updates only the Codex binary pin.
- Superpowers and iwiki ship through git as vendored Codex plugins.
- Users do not run plugin installation commands after clone.
- iwiki requires `uv` and an OpenAI-compatible embeddings endpoint for indexing/search.
- Manual iwiki skills remain available even if a hook event is unsupported by the pinned Codex binary.

Update `.codex_config.example` with iwiki configuration if implementation chooses to export `IWIKI_*` from the parsed config file.

The current `icodex` project has no `docs/wiki/`, so iwiki ingest/lint is not required for this design-only change.

## 15. Verification Checklist

The implementation is complete when:

1. `bash tests/test_args.sh` passes.
2. `bash tests/test_install.sh` passes.
3. `bash tests/test_plugin.sh` still passes for Superpowers.
4. New iwiki wiring tests pass.
5. New vendored iwiki hygiene tests pass.
6. Hook probe result is recorded in the implementation notes or test output.
7. Config-free iwiki engine smoke test passes.
8. `codex plugin list --json` shows `iwiki` enabled when a Codex binary is available.
9. `./icodex.sh --update` updates only the Codex binary pin and does not modify plugin artifacts.

## 16. Assumptions and Risks

- The branch is created from the current local `main`; no `git pull` was run because the worktree had pre-existing uncommitted changes and network access is restricted.
- Codex hook support may differ from Claude hook support. This is handled by a mandatory probe before claiming full automation.
- Extending `.codex_config` to export `IWIKI_*` increases the set of accepted environment variables. The parser must remain non-executing and explicit.
- Vendoring `engine/uv.lock` improves reproducibility, but `uv` still needs network for first dependency resolution unless dependencies are already cached.
- The dedicated `iwiki.sh` module duplicates the Superpowers wiring pattern. This is deliberate for this iteration.
