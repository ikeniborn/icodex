---
title: 05 LoEn icodex integration design
date: 2026-07-02
status: draft
chain:
  intent: null
---

# 05 LoEn icodex integration design

## Purpose

Wire the standalone LoEn plugin source into the icodex isolated Codex runtime.
This layer is an adapter: it vendors, enables, disables, and verifies LoEn
without making LoEn depend on icodex internals.

## Files

```text
scripts/vendor-loen.sh
lib/plugin/loen.sh
tests/test_loen_plugin.sh
```

`icodex.sh` sources `plugin/loen` and calls `ensure_loen_wiring` on the default
launch path.

## Vendoring Flow

`scripts/vendor-loen.sh` copies:

```text
plugins/loen/
```

into:

```text
.codex-isolated/plugins/cache/icodex-local/loen/<version>/
```

The script strips generated artifacts, validates the manifest, and preserves
skills, hooks, agents, docs, and assets.

## Launch-time Wiring

`lib/plugin/loen.sh`:

- detects the installed LoEn cache directory;
- derives the marketplace name from the cache path;
- creates a runtime marketplace root under the per-project Codex home;
- symlinks `plugins/loen` in that marketplace root to the committed cache;
- writes marketplace manifests;
- rewrites `[marketplaces.<name>].source` in the per-project `config.toml`;
- enables `[plugins."loen@<name>"] enabled = true`;
- removes or disables LoEn entries when configured off.

This mirrors the existing portable plugin pattern but the runtime LoEn adapter
uses LoEn-specific code and does not call Superpowers modules.

## Runtime Configuration

LoEn is controlled through `ICODEX_LOEN_MODE` with accepted values:

```text
off
advisory
enforce
strict
```

Unset defaults to `advisory` for the first integration. A later change may make
`enforce` the default after trial runs pass.

## Legacy Exclusions

The integration must not use or recreate `lib/plugin/iwiki.sh`. Current iwiki
wiring lives under `lib/iwiki/iwiki.sh` and is unrelated to LoEn.

## Tests

This layer should add tests that validate:

- `vendor-loen.sh` creates `.codex-isolated/plugins/cache/icodex-local/loen/<version>/`;
- cache contains `.codex-plugin/plugin.json`, skills, hooks, agents, assets, and docs;
- launch wiring rewrites marketplace source to a current host path;
- plugin enablement is idempotent;
- `ICODEX_LOEN_MODE=off` strips or disables LoEn wiring;
- no runtime LoEn integration script references `lib/plugin/iwiki.sh` except
  test fixtures that assert the legacy path is excluded;
- `--install` and `--update` remain binary-only and do not vendor LoEn.

## Acceptance

- icodex can launch with LoEn enabled from the vendored cache.
- LoEn can be disabled without removing its source tree.
- The adapter is testable without network access.
