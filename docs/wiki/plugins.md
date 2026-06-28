# Plugins

## Overview

The `lib/plugin/` modules wire the two git-vendored plugins into `config.toml`.

Superpowers and iwiki are wired at launch. Both rewrite a marketplace `source`
line to a host-absolute path so the committed plugin caches are portable across
machines. They run on the default run path. See [[architecture#Default run path]]
and [[tooling#Plugin vendoring]].

## Superpowers wiring

`ensure_superpowers_wiring` locates the vendored cache and rewrites its source.

It finds the cache under `.codex-isolated/plugins/cache/*/superpowers/*`, derives
the marketplace name from the path, builds a portable marketplace root under
`tmp/marketplaces/`, and rewrites the `[marketplaces.<mkt>]` source to it. Missing
cache is a warning, not a failure.

## Marketplace root synthesis

`_ensure_superpowers_marketplace_root` creates a synthetic marketplace directory.

It makes a `plugins/superpowers` symlink to the cache plus a generated
`marketplace.json` (and `api_marketplace.json`) describing a local plugin source.
This lets Codex load the committed plugin without a network plugin install. See
[[architecture#What lives in git]].

## iwiki wiring

`ensure_iwiki_wiring` finds the vendored cache under `ai-wiki/iwiki/*`.

It rewrites the `[marketplaces.ai-wiki]` source directly to that cache path. If
`config.toml` is absent it is seeded from `config.toml.example` first. The iwiki
engine relies on `UV_BIN`/`IWIKI_*` env from [[config#Allowed keys and mapping]].

## Idempotent source rewrite

Both modules share the same awk-based rewrite of the `source` line.

Inside the matching `[marketplaces.<mkt>]` section, the `source = ...` line is
replaced with the absolute path, and the file is overwritten only when the content
changed (`cmp -s`), preserving inode and permissions. This keeps repeated launches
from churning the config.
