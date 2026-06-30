# Tooling

## Overview

This page covers tooling outside the runtime path.

The `scripts/vendor-*.sh` plugin vendoring tools and the dependency-free `tests/`
harness live here. Vendoring is "install once on one machine, deliver via git";
tests mirror the iclaude pattern. See [[architecture#What lives in git]] and
[[plugins#Superpowers wiring]].

## Plugin vendoring

`scripts/vendor-superpowers.sh <sha>` regenerates the Superpowers cache.

The script installs the plugin into a scratch `CODEX_HOME` via the
real `codex plugin` commands, then normalizes the produced cache into the
canonical repo path.

## Vendor normalization

Normalization copies the scratch cache into the repo, then de-lints it.

It removes `.git`, nested `.gitignore`, `.venv`, `.pytest_cache`, and `__pycache__`,
and asserts the plugin manifest survived. This keeps the committed cache clean
and self-contained.

## Test harness

`tests/helpers.sh` is a dependency-free harness.

`assert_eq`, `assert_exit`, and `assert_contains` track `PASS`/`FAIL` counters,
and `finish` prints the totals and returns non-zero on any failure. Each
`tests/test_*.sh` sources a module and exercises its functions directly — no
external test framework.

## Test coverage

The suite has one `test_*.sh` per module and concern.

These include `test_args`, `test_detect`, `test_lockfile`, `test_install`,
`test_env`, `test_isolated`, `test_proxy`, `test_symlink`, `test_validation`,
`test_logging`, `test_plugin`, `test_update_scope`, `test_gitignore`, `test_codex_hooks`,
`test_caveman_hook`, `test_caveman_wiring`, `test_caveman_launch`,
`test_caveman_vendor`, the IDD tests (`test_idd_gate`, `test_idd_nudge`,
`test_idd_wiring`, `test_idd_skills`), and an end-to-end `test_smoke`.
