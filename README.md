# icodex

Isolated bash wrapper for the [OpenAI Codex CLI](https://developers.openai.com/codex/cli),
built following the `iclaude` example. Installs a pinned static codex binary into the
project, isolates codex state via `CODEX_HOME`, and optionally routes traffic through a proxy.

## Usage

    ./icodex.sh --install          # fetch the pinned binary + create the `icodex` symlink
    ./icodex.sh                    # launch codex in the isolated environment
    icodex                         # same, once ~/.local/bin is on PATH
    ./icodex.sh --proxy http://p:8080 exec "..."   # via proxy, args forwarded to codex
    ./icodex.sh --update           # update + re-pin the binary
    ./icodex.sh --version          # icodex + codex versions

On `--install`/`--update` a symlink `icodex` is created in `~/.local/bin` (override with
`ICODEX_LINK_DIR`) so you can run `icodex` from anywhere — provided that directory is on
your `PATH`. An existing non-symlink file at that path is never overwritten.

State lives in `.codex-isolated/` (git-ignored). The binary is pinned by version + sha256
in `.codex-lockfile.json` (committed). Auth (`codex login` / `OPENAI_API_KEY`) is written
into the isolated `CODEX_HOME` by codex itself — the wrapper never stores credentials.

## Persistent configuration

Settings you want every run can live in a `.codex_config` file at the project root
(git-ignored, `chmod 600`). Start from the template:

    cp .codex_config.example .codex_config

The file holds plain `KEY=value` lines; **only `ICODEX_`-prefixed keys are honored**, and
the file is parsed (never sourced), so values can't execute code. Precedence is
**built-in defaults < `.codex_config` < command-line flags**.

| Variable | Effect |
|----------|--------|
| `ICODEX_PROXY` | Proxy URL exported as `HTTPS_PROXY`/`HTTP_PROXY` for codex |
| `ICODEX_NO_PROXY` | Comma-separated host bypass list, exported as `NO_PROXY` (e.g. `localhost,127.0.0.1,github.com`) |
| `ICODEX_REPO` | GitHub repo for the codex binary (default `openai/codex`) |
| `ICODEX_UNAME_S` / `ICODEX_UNAME_M` | Force the release-asset platform |
| `ICODEX_LINK_DIR` | Directory for the `icodex` symlink (default `~/.local/bin`) |

`ICODEX_NO_PROXY` is a bypass list (standard `NO_PROXY` semantics), **not** a disable
switch — to skip the proxy for a single run use the `--no-proxy` flag.
`./icodex.sh --proxy <url>` writes `ICODEX_PROXY` into `.codex_config` (preserving other
keys); `./icodex.sh --clear` removes the file.
