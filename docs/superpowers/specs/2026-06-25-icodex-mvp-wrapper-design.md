---
review:
  spec_hash: c474263773319527
  last_run: 2026-06-25
  phases:
    structure:   { status: passed }
    coverage:    { status: passed }
    clarity:     { status: passed }
    consistency: { status: passed }
  findings:
    - id: F-001
      phase: clarity
      severity: WARNING
      section: "3.3 binary/install.sh"
      section_hash: 36fb95ef495aa280
      fragment: "if .codex-isolated/bin/codex exists AND matches lockfile → nothing, return"
      text: "The idempotency check 'matches lockfile' is underspecified for an already-extracted binary: the lockfile sha256 is over the downloaded tarball, not the extracted binary, so re-deriving it from bin/codex is not defined."
      fix: "Specify the install marker mechanism — e.g. write an installed-version stamp file alongside bin/codex and compare lockfile.version against it, or store the extracted-binary sha separately."
      verdict: open
      verdict_at: null
chain:
  intent: null
---

# icodex — MVP Wrapper Design

> Date: 2026-06-25
> Status: Approved (design phase)
> Scope: MVP core

---

## 1. Purpose

`icodex` is a bash wrapper for the [OpenAI Codex CLI](https://developers.openai.com/codex/cli),
built following the example of the existing `iclaude` wrapper for Claude Code.

The MVP delivers a self-contained launcher that:

1. **Isolates the codex install** — downloads a pinned static binary into the project, no global install, no Node toolchain.
2. **Isolates codex state** — redirects `CODEX_HOME` to a project-local directory so auth, config, and sessions never touch the user's home.
3. **Passes traffic through a proxy** — exports `HTTPS_PROXY`/`HTTP_PROXY` so codex routes through a corporate or local proxy.
4. **Launches codex transparently** — forwards all unrecognized arguments straight to the real `codex` binary.

### Why a wrapper (problems solved)

- **No global pollution / no Node dependency.** A system `npm i -g @openai/codex` needs Node 22+ and competes with other global packages. icodex downloads the prebuilt static `musl` binary directly — reproducible, pinned, Node-free.
- **Per-project isolation.** Codex stores credentials and config under `CODEX_HOME` (default `~/.codex`). Pointing it at `.codex-isolated/` keeps every project's auth and config separate and inside the repo's ignore boundary.
- **Proxy out of the box.** Codex respects standard proxy env vars but doesn't persist them. icodex saves the proxy URL and re-exports it on every launch.

### Codex facts that shape this design

- Codex CLI is a native Rust binary distributed via npm (`@openai/codex`), Homebrew, an installer script, and **prebuilt static binaries on GitHub Releases**. The `x86_64-unknown-linux-musl` build is statically linked and runs on any Linux distro with no runtime deps.
- Release tags use the form `rust-v<semver>` (e.g. `rust-v0.142.2`). Linux asset name: `codex-x86_64-unknown-linux-musl.tar.gz` (also `aarch64`, and `*-apple-darwin` for macOS). Each asset ships a `.sigstore` attestation alongside.
- Codex stores state under `CODEX_HOME` (default `~/.codex`): `auth.json` (credentials) + `config.toml` (settings). It honors the `CODEX_HOME` env var.
- Codex honors `HTTPS_PROXY`/`https_proxy` for network-level proxying (Rust `reqwest`).
- Auth is via `codex login` (ChatGPT) or `OPENAI_API_KEY`; both write into `CODEX_HOME`.

### Explicitly out of MVP scope

The following `iclaude` modules do **not** map cleanly to codex or are deferred:

- **Security hooks (PreToolUse/PostToolUse)** — codex has no equivalent rich hook system.
- **Statusline** — codex is a TUI with no custom statusline injection point.
- **Router (alternative LLMs)** — codex supports `model_providers` natively in `config.toml`; no separate router proxy needed.
- **PII proxy, Firecracker sandbox, OAuth manager, iwiki, GSD, caveman** — deferred to later iterations.

---

## 2. Architecture

Approach: **standalone mirror** of the `iclaude` module pattern, scoped to MVP modules only.
No shared library and no fork — `icodex` is self-contained with zero coupling to `iclaude`.

`icodex.sh` only sources modules and orchestrates; all logic lives in `lib/`. Each module has a single responsibility.

### File layout

```
icodex/
├── icodex.sh                 # entrypoint: parse args → setup → exec codex
├── lib/
│   ├── core/
│   │   ├── init.sh           # global vars, paths, PROJECT_ID
│   │   ├── logging.sh        # log_info / log_warn / log_error
│   │   └── validation.sh     # preconditions (curl, tar, sha256sum present)
│   ├── command/
│   │   └── args.sh           # flag parsing + --help text
│   ├── binary/
│   │   ├── detect.sh         # OS + arch → release asset name
│   │   ├── install.sh        # download, verify sha256, extract into bin/
│   │   └── lockfile.sh       # read/write .codex-lockfile.json (version + sha)
│   ├── config/
│   │   └── isolated.sh       # prepare CODEX_HOME (.codex-isolated/)
│   ├── proxy/
│   │   └── proxy.sh          # passthrough HTTPS_PROXY/HTTP_PROXY + persist url
│   └── launcher/
│       └── launch.sh         # final exec of codex with prepared env
├── .codex-isolated/          # gitignored: CODEX_HOME (auth.json, config.toml, bin/)
│   └── bin/codex             # downloaded binary
├── .codex_config             # gitignored, chmod 600: saved proxy url
├── .codex-lockfile.json      # committed: pinned version + sha256
├── .gitignore
├── VERSION
└── README.md
```

---

## 3. Components

### 3.1 `icodex.sh` (orchestration)

```
1. source lib/core/*          → paths, logging
2. command/args.sh            → parse flags
3. branch on command:
     --update / --install      → binary/install.sh (then exit for these)
     --clear                   → wipe .codex_config, exit
     --version                 → print icodex + codex version, exit
     --help                    → help text, exit
     (default)                 → full setup → launch
4. config/isolated.sh         → export CODEX_HOME
5. binary/install.sh          → ensure binary present (per lockfile)
6. proxy/proxy.sh             → export *_PROXY env (unless --no-proxy)
7. launcher/launch.sh         → exec codex "$@"
```

### 3.2 `binary/detect.sh`

Maps `uname -s` + `uname -m` to a GitHub release asset name:

| OS | Arch | Asset |
|----|------|-------|
| Linux | x86_64 | `codex-x86_64-unknown-linux-musl.tar.gz` |
| Linux | aarch64/arm64 | `codex-aarch64-unknown-linux-musl.tar.gz` |
| Darwin | arm64 | `codex-aarch64-apple-darwin.tar.gz` |
| Darwin | x86_64 | `codex-x86_64-apple-darwin.tar.gz` |

Unknown platform → explicit error listing supported targets.

### 3.3 `binary/install.sh` (core)

```
if .codex-isolated/bin/codex exists AND matches lockfile → nothing, return
else:
  version  = lockfile.version           (or 'latest' when --update)
  asset    = detect.sh asset name
  url      = GitHub release download URL for tag + asset
  download tar.gz to temp file
  sha256   = compute over downloaded tarball
  if lockfile.sha is set AND != sha256 → ERROR (tamper guard), stop
  extract into .codex-isolated/bin/, chmod +x
  on --update: write lockfile { version, sha256, asset }
```

- **Reproducibility:** the lockfile is committed to git, so every clone fetches the same binary and verifies the same sha256.
- **`--update`** is the only path that re-pins; it is an explicit, deliberate action.
- **`latest` resolution:** query the GitHub releases API (`releases/latest`) for the current `tag_name`.

### 3.4 `binary/lockfile.sh`

Reads and writes `.codex-lockfile.json`:

```json
{
  "version": "rust-v0.142.2",
  "asset": "codex-x86_64-unknown-linux-musl.tar.gz",
  "sha256": "<hex>"
}
```

Note: `sha256` is per-asset (per-platform). For the MVP we pin the host platform's asset.
A multi-platform lockfile (sha per asset) is a possible later refinement; out of scope here.

### 3.5 `config/isolated.sh`

- `export CODEX_HOME="$PROJECT_DIR/.codex-isolated"`
- Create the directory if missing.
- All codex state (`auth.json`, `config.toml`, sessions) lives inside the repo's ignore boundary.
- **Auth:** `codex login` / `OPENAI_API_KEY` write into `CODEX_HOME` themselves. The wrapper never reads, stores, or injects credentials.

### 3.6 `proxy/proxy.sh`

- `--proxy <url>` → save URL to `.codex_config` (chmod 600).
- On launch (default): read saved URL and `export HTTPS_PROXY HTTP_PROXY https_proxy http_proxy`.
- `--no-proxy` → skip the export for this run (saved value untouched).
- Codex (Rust `reqwest`) honors these env vars natively. No CA-cert handling, no git-proxy sync, no `--test` in the MVP.

### 3.7 `launcher/launch.sh`

- `exec "$CODEX_HOME/bin/codex" "$@"` — transparent forward of all remaining arguments to codex.

### Data flow

```
user flags
  → env (CODEX_HOME + *_PROXY)
  → exec codex (inherits env)
  → codex reads its own isolated config.toml / auth.json
```

---

## 4. CLI surface (MVP)

| Flag | Action |
|------|--------|
| `--proxy <url>` | Save proxy URL, export to env |
| `--no-proxy` | Run without proxy (ignore saved value) |
| `--clear` | Wipe `.codex_config` |
| `--update` | Update binary to latest, rewrite lockfile pin |
| `--install` | Install binary per lockfile (no launch) |
| `--version` | icodex version + codex binary version |
| `--help` | Help text |
| `--` / anything else | Transparent passthrough to `codex` |

Anything not an icodex flag is forwarded to codex verbatim (e.g. `icodex exec "..."`, `icodex --model ...`).

---

## 5. Error handling

- Missing `curl` / `tar` / `sha256sum` → early error with install instructions.
- Unknown OS/arch in `detect.sh` → explicit error, list of supported targets.
- Sha256 mismatch on install → stop, do not launch (binary tamper guard).
- GitHub release unreachable (network / 404) → error with the manual download URL.
- No binary and no network → hint about offline `--install`.
- No error handling for impossible scenarios (simplicity principle).

---

## 6. Testing

Bash test harness in `tests/` (bats or simple bash, following the `iclaude` pattern):

- `detect.sh`: mock `uname` → correct asset name for each platform.
- `lockfile.sh`: read/write/compare round-trip.
- `install.sh`: mock download of a local tar → sha mismatch stops, match proceeds.
- `proxy.sh`: `--proxy` writes config and env is exported; `--no-proxy` skips export.
- `config/isolated.sh`: `CODEX_HOME` set to the right path, directory created.
- smoke: `icodex --version` without network (when binary present) does not crash.

### MVP success criteria

On a clean machine, `./icodex.sh`:

1. downloads the pinned binary and verifies its sha256,
2. isolates `CODEX_HOME` into `.codex-isolated/`,
3. starts `codex` in a fully isolated per-project environment.

And `--proxy <url>` demonstrably routes codex traffic through the proxy.

---

## 7. Open refinements (post-MVP)

- Multi-platform lockfile (sha256 per asset) for cross-platform reproducibility.
- Sigstore attestation verification (`.sigstore`) in addition to sha256.
- Proxy parity with iclaude (custom CA cert, git-proxy sync, `--test`).
- Later modules: security boundary on project-local `.codex/config.toml`, telemetry, PII proxy.
