# Plugins

## Overview

The `lib/plugin/` module wires the git-vendored Superpowers plugin into `config.toml`.

Superpowers is wired at launch. The launcher rewrites its marketplace `source`
line to a host-absolute path so the committed plugin cache is portable across
machines. It runs on the default run path. See [[architecture#Default run path]]
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

## Idempotent source rewrite

The plugin module uses an awk-based rewrite of the `source` line.

Inside the matching `[marketplaces.<mkt>]` section, the `source = ...` line is
replaced with the absolute path, and the file is overwritten only when the content
changed (`cmp -s`), preserving inode and permissions. This keeps repeated launches
from churning the config.
