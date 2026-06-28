# Binary

## Overview

The `lib/binary/` modules fetch, pin, and verify the codex binary, plus provision uv.

`detect.sh` maps host OS/arch to a release asset, `lockfile.sh` reads and writes
the pin file, and `install.sh` orchestrates the idempotent download, sha256
verification, and extraction. See [[core#Portable sha256]] and
[[architecture#What lives in git]].

## Asset detection

`detect_asset` maps `uname -s`/`uname -m` to a GitHub release asset name.

`ICODEX_UNAME_S`/`ICODEX_UNAME_M` override the probe for tests. Linux becomes
`unknown-linux-musl`, Darwin `apple-darwin`; `x86_64`/`amd64` and `aarch64`/
`arm64` are accepted. Unsupported OS or arch is an error. Output form:
`codex-<arch>-<os>.tar.gz`.

## Lockfile pinning

`lockfile.sh` manages `.codex-lockfile.json`, a flat self-controlled JSON pin.

It holds `version`, `asset`, and `sha256`. `lockfile_get` extracts a key with
`sed` (no jq dependency); `lockfile_write` regenerates the file. The committed
lockfile makes a clone reproducible — see [[architecture#What lives in git]].

## Install and update

`install_ensure [--update]` is the core routine.

Without `--update` it is idempotent: if the binary is executable and the version
stamp matches the pin, it returns immediately. Otherwise it resolves a tag
(pinned, or latest via the GitHub API on update), downloads, verifies, extracts,
and stamps. Update mode also rewrites the lockfile and logs each stage.

## Tamper guard

On a non-update install with a pinned sha256, the digest must match or install aborts.

The downloaded tarball's digest (via [[core#Portable sha256]]) is compared to the
lockfile, erroring before extraction on mismatch. Update mode skips this check
because it is establishing a new pin. Download failures print a manual-fetch hint.

## Extraction

`_extract_codex` untars into a temp dir and stages the binary atomically.

It finds the `codex*` file (excluding `.tar*`/`.sigstore`), stages it to a
`.codex.new.$$` path, marks it executable, then `mv -f`s it onto `ICODEX_BIN`.
Every failure cleans up. This staged-then-move pattern avoids a half-written binary.

## uv dependency

`ensure_uv_dependency` guarantees a `uv` binary at `.codex-isolated/bin/uv`.

It is needed by the vendored plugins' engines. A system `uv` is copied in if
present; otherwise the Astral installer is fetched (honoring the proxy). The
resolved path is exported as `CODEX_UV_BIN`/`UV_BIN` and persisted to
`.codex_config` via [[config#Config upsert]].

## Proxy-aware downloads

`_curl_proxy_args` emits `--proxy <url>` curl arguments from `ICODEX_PROXY`.

It is skipped when `ICODEX_DISABLE_PROXY` is set. All network helpers (`_download`,
`_resolve_latest`, the uv installer fetch) route through it, so installs work
behind a proxy. See [[launch#Proxy persist and apply]] for proxy configuration.
