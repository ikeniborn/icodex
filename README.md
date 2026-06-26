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

### What lives in git

Only the **codex binary** is fetched on demand (pinned by version + sha256 in the
committed `.codex-lockfile.json`); everything else ships with the repo, so a clone is
ready to use offline once the binary is present:

- **Committed** — curated codex config under `CODEX_HOME`: `.codex-isolated/AGENTS.md`
  (instructions codex reads — note the plural name), `AGENTS.override.md`, and `config.toml`.
- **Git-ignored** — the downloaded binary (`.codex-isolated/bin/`), secrets (`auth.json`,
  `.codex_config`), and all runtime state (`*.sqlite`, logs, sessions, `version.json`).

The `.codex-isolated/` ignore rule is a whitelist: everything is ignored except the three
config files above, so secrets and runtime churn can never be committed by accident.

Auth: run `codex login`, set the key once in `.codex_config` (`ICODEX_API_KEY`), or export
`OPENAI_API_KEY` — the key stays out of git either way.

## Persistent configuration

Settings you want every run can live in a `.codex_config` file at the project root
(git-ignored, `chmod 600`). Start from the template:

    cp .codex_config.example .codex_config

The file holds plain `KEY=value` lines; **only `ICODEX_`-prefixed keys are honored**, and
the file is parsed (never sourced), so values can't execute code. Precedence is
**built-in defaults < `.codex_config` < command-line flags**.

| Variable | Effect |
|----------|--------|
| `ICODEX_API_KEY` | OpenAI API key → exported as `OPENAI_API_KEY` (secret; an ambient `OPENAI_API_KEY` wins) |
| `ICODEX_PROXY` | Proxy URL exported as `HTTPS_PROXY`/`HTTP_PROXY` for codex |
| `ICODEX_NO_PROXY` | Comma-separated host bypass list, exported as `NO_PROXY` (e.g. `localhost,127.0.0.1,github.com`) |
| `ICODEX_REPO` | GitHub repo for the codex binary (default `openai/codex`) |
| `ICODEX_UNAME_S` / `ICODEX_UNAME_M` | Force the release-asset platform |
| `ICODEX_LINK_DIR` | Directory for the `icodex` symlink (default `~/.local/bin`) |

`ICODEX_NO_PROXY` is a bypass list (standard `NO_PROXY` semantics), **not** a disable
switch — to skip the proxy for a single run use the `--no-proxy` flag.
`./icodex.sh --proxy <url>` writes `ICODEX_PROXY` into `.codex_config` (preserving other
keys); `./icodex.sh --clear` removes the file.
