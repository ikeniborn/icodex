# icodex

Isolated bash wrapper for the [OpenAI Codex CLI](https://developers.openai.com/codex/cli),
built following the `iclaude` example. It keeps Codex fully contained inside the project:
a pinned static `codex` binary, **per-project** state, a **safe-by-default** filesystem
sandbox, and optional proxy routing — so Codex never touches your home directory or other
projects unless you ask it to.

_Russian version / Русская версия: [`docs/README.ru.md`](docs/README.ru.md)._

## Workflow boundaries

IDD->SDD/Superpowers and LoEn are separate workflow systems. Non-trivial
Superpowers work follows `fix-intent -> check-chain -> brainstorming ->
writing-plans -> implementation -> check-chain result`. Durable LoEn workspace
tasks use `loen:loop-*` skills and repository artifacts under `docs/loen/<topic>/`
instead; a LoEn loop does not require `fix-intent`, `superpowers:*`, or
`$check-chain` unless the user explicitly chooses the IDD->SDD chain for a
separate non-LoEn change.

Task naming uses one canonical kebab-case `<topic>` across controlled artifacts:
`docs/TODO.md`, the Superpowers chain topic or LoEn topic directory, and the
`dev-<topic>` branch suffix. Thread titles are best-effort only; if the Codex
surface cannot change or request a UI title, the agent records the chosen topic in
the conversation and continues.

## How isolation works

icodex keeps Codex state in two layers:

- **Shared store** — `.codex-isolated/` holds the expensive, stable assets shared by every
  project: the pinned `codex` binary, `uv`, the vendored Superpowers plugin cache, the
  shared `auth.json`, and the tracked `config.toml` template.
- **Per-project home** — each project you launch from gets its own `CODEX_HOME` under
  `.codex-homes/<project>-<hash>/`. It symlinks the shared assets (`plugins`, `skills`,
  `rules`, hook scripts, and `auth.json`), copies the `config.toml` template, keeps the global
  `AGENTS.md` guidance in sync, and stores that project's sessions, logs, and sqlite separately
  — see [What's in a per-project home](#whats-in-a-per-project-home). The home is keyed by the
  project's git root (or working directory), so two repos never share session state — but they
  do share one login and one binary.

`.codex-homes/` is runtime state and is git-ignored.

## Setup

1. **Install the binary** (once per clone):

       ./icodex.sh --install

   Fetches the pinned `codex` binary (version + sha256 from `.codex-lockfile.json`) into
   `.codex-isolated/bin/`, and creates an `icodex` symlink in `~/.local/bin` (override with
   `ICODEX_LINK_DIR`). Put that directory on your `PATH` to run `icodex` from anywhere. An
   existing non-symlink file at the link path is never overwritten.

2. **Authenticate** (pick one):

   - Run `codex login` — writes `.codex-isolated/auth.json` (git-ignored, shared across all
     projects), or
   - Set `ICODEX_API_KEY=sk-...` in `.codex_config` (see [Configuration variables](#configuration-variables)), or
   - Export `OPENAI_API_KEY` in your shell — an ambient key always wins.

3. **Run** from any project directory:

       icodex                      # launch Codex, isolated to the current project
       icodex -- exec "..."        # everything after -- is forwarded to codex verbatim

## Commands

    ./icodex.sh                 # launch codex in the isolated environment (default)
    icodex                      # same, once ~/.local/bin is on PATH
    ./icodex.sh --full-access   # launch with the filesystem sandbox fully open (warns)
    ./icodex.sh --proxy http://p:8080 -- exec "..."   # route via proxy, forward args to codex
    ./icodex.sh --no-proxy      # skip the proxy for this run
    ./icodex.sh --install       # fetch the pinned binary + create the icodex symlink
    ./icodex.sh --update        # update + re-pin the codex binary only
    ./icodex.sh --clear         # remove the saved config file (.codex_config)
    ./icodex.sh --version       # icodex + codex versions
    ./icodex.sh --help          # full flag list

Anything after the first non-flag argument (or after `--`) is passed straight to `codex`.
On `--install`/`--update` the `icodex` symlink is created in `ICODEX_LINK_DIR`. `--install`
and `--update` fetch only the Codex binary. `--update` resolves the latest release first;
if that version already matches the installed stamp and lockfile pin, it skips the archive
download, extraction, and lockfile rewrite. When a newer release exists, `--update` prints
each network/install stage with curl's download progress bar. The Superpowers plugin and
skills ship through git and are updated only by maintainer scripts.

## Configuration variables

Settings you want on every run live in a `.codex_config` file at the project root
(git-ignored, `chmod 600`). Start from the template:

    cp .codex_config.example .codex_config
    chmod 600 .codex_config

The file holds plain `KEY=value` lines. **Only `ICODEX_`-prefixed keys are honored**, and
the file is parsed — never sourced — so values can't execute code. Precedence is **built-in
defaults < `.codex_config` < command-line flags**. Every variable below can also be set as an
ordinary environment variable.

| Variable | Effect | Default |
|----------|--------|---------|
| `ICODEX_API_KEY` | OpenAI API key → exported as `OPENAI_API_KEY` (secret; an ambient `OPENAI_API_KEY` wins) | — |
| `ICODEX_MODE` | Run profile preset — sets sandbox, approval, and managed permissions together (see [Run mode](#run-mode-icodex_mode)) | `full-ask` |
| `ICODEX_SANDBOX` | Granular override: filesystem sandbox only — `read-only`, `workspace-write`, or `danger-full-access`; takes precedence over `ICODEX_MODE` for the sandbox field | — |
| `ICODEX_APPROVAL` | Granular override: approval policy only — `untrusted`, `on-failure`, `on-request`, or `never`; takes precedence over `ICODEX_MODE` for the approval field | — |
| `ICODEX_PERMISSIONS` | Granular override: managed permission profile only — `dev-safe`, `ssh-on-request`, or `none`; takes precedence over `ICODEX_MODE` for the permissions field | — |
| `ICODEX_PROXY` | Proxy URL, exported as `HTTPS_PROXY` / `HTTP_PROXY` for codex | — |
| `ICODEX_NO_PROXY` | Comma-separated host bypass list, exported as `NO_PROXY` (e.g. `localhost,127.0.0.1,github.com`) | — |
| `ICODEX_CA_FIX` | curl TLS-trust workaround: `auto` detects an OpenSSL bundle it can't decode and routes curl via a filtered copy; `off` disables it | `auto` |
| `ICODEX_CA_BUNDLE` | Explicit CA bundle for curl/OpenSSL — exported as `CURL_CA_BUNDLE` / `SSL_CERT_FILE`; skips detection | — |
| `ICODEX_REPO` | GitHub repo the codex binary is fetched from | `openai/codex` |
| `ICODEX_LINK_DIR` | Directory for the `icodex` symlink (leading `~/` is expanded) | `~/.local/bin` |
| `ICODEX_UNAME_S` / `ICODEX_UNAME_M` | Force the release-asset platform instead of auto-detecting via `uname` | auto |

`ICODEX_NO_PROXY` is a bypass list (standard `NO_PROXY` semantics), **not** a disable switch
— to skip the proxy for a single run use the `--no-proxy` flag. `./icodex.sh --proxy <url>`
writes `ICODEX_PROXY` into `.codex_config` (preserving other keys); `./icodex.sh --clear`
removes the file.

If `ICODEX_PROXY` is set but the proxy is unreachable, icodex warns and — when run
interactively — asks whether to continue without the proxy (default yes) or exit;
without a TTY it continues without the proxy. Use `--no-proxy` to skip the proxy (and
the probe) entirely.

> `ICODEX_*` keys reserved for the iwiki plugin (e.g. `ICODEX_IWIKI_*`) are intentionally
> ignored by the wrapper config.

On hosts whose curl is linked against an OpenSSL build that cannot decode every CA in the
system trust bundle (e.g. ALT Linux, whose bundle ships GOST-algorithm roots that OpenSSL
1.1.1 rejects), curl aborts the whole handshake with `x509_pubkey_decode: unsupported
algorithm` and every HTTPS call fails. codex itself is unaffected (it uses rustls with
bundled roots), but curl subprocesses are. On each run icodex detects this locally (no
network), writes a filtered, GOST-free copy of the bundle under `.codex-isolated/ca-trust/`,
and exports `CURL_CA_BUNDLE` / `SSL_CERT_FILE` so curl works again. It is idempotent (cached
by the source bundle's mtime), never edits the system trust, and is a no-op on healthy
hosts. Set `ICODEX_CA_BUNDLE` to force a specific bundle, or `ICODEX_CA_FIX=off` to disable.

### Run mode (`ICODEX_MODE`)

One preset sets the sandbox, approval policy, and managed permission profile together:

| `ICODEX_MODE` | Sandbox | Approval | Managed permissions | `.git` writable |
|---------------|---------|----------|---------------------|-----------------|
| `ro` | read-only | on-request | dev-safe | no |
| `safe` | workspace-write | on-request | dev-safe | yes |
| `full-ask` (default) | danger-full-access | on-request | ssh-on-request | yes |
| `full-auto` | danger-full-access | never (no prompts) | off | yes |

`full-auto` is the "full, no-stop" mode — equivalent to
`--dangerously-bypass-approvals-and-sandbox`. The granular keys `ICODEX_SANDBOX`,
`ICODEX_APPROVAL`, and `ICODEX_PERMISSIONS` override individual fields of the preset.

### Verifying `.git` write access

In every **writable** mode icodex grants `".git/" = "write"` under the active managed
permission profile's `:workspace_roots` table. This overrides the read-only re-mount Codex
applies to `.git/` under `workspace-write`, so `git commit` works from inside the sandbox.
That grant is what makes the difference under `workspace-write` (`safe`); under
`danger-full-access` (`full-ask` / `full-auto`) `.git` is writable through the sandbox
itself, and under `read-only` (`ro`) nothing is writable regardless of the grant.

To check the grant directly — no model, no network — run a write under the same sandbox
Codex applies, against a throwaway repo:

```bash
repo="$(mktemp -d)"; git -C "$repo" init -q
home="$(mktemp -d -p "$HOME")"
cp .codex-isolated/config.toml "$home/config.toml"
CODEX_HOME="$home" .codex-isolated/bin/codex sandbox -C "$repo" -P dev-safe --include-managed-config -- sh -c 'echo x > .git/probe && echo WROTE || echo DENIED'
rm -rf "$repo" "$home"
```

With the shipped `.git/` grant this prints `WROTE`; delete the `".git/" = "write"` line
from the `dev-safe` `:workspace_roots` table and the same command prints `DENIED`.

> **Mode precedence with `.codex_config`:** the wrapper exports each `ICODEX_*` key parsed
> from `.codex_config`, so a key pinned in the file overrides the same environment variable.
> To select a mode through the environment (e.g. `ICODEX_MODE=safe ./icodex.sh`), make sure
> that key is not set in `.codex_config`.

## Sandbox and trust

icodex is **safe by default**: every run writes the effective sandbox into the project's
`CODEX_HOME` config. The effective sandbox is resolved, lowest to highest precedence:

1. **`ICODEX_MODE` preset** — the default mode `full-ask` sets `danger-full-access`; `safe`
   and `ro` set `workspace-write` and `read-only` respectively. See [Run mode](#run-mode-icodex_mode).
2. **`ICODEX_SANDBOX`** — granular override for the sandbox field only: `read-only`,
   `workspace-write`, or `danger-full-access`. An invalid value is rejected with an error.
3. **`--full-access` flag** — forces `danger-full-access` for that single run.

`danger-full-access` grants full filesystem access; icodex always prints a warning to stderr
when it is active. icodex also **auto-trusts** the launched project in its per-project config,
so Codex does not re-prompt for trust on every run.

## What lives in git

Only the **codex binary** is fetched on demand (pinned by version + sha256 in the committed
`.codex-lockfile.json`); everything else ships with the repo, so a clone is ready to use
offline once the binary is present:

- **Committed** — the curated Codex config template under `.codex-isolated/`: `AGENTS.md`,
  `AGENTS.override.md`, **`config.toml`**, `rules/default.rules`, and the pre-installed
  **Superpowers plugin** — its skills (`.codex-isolated/skills/`, excluding codex-managed
  `.system/`) and its plugin cache (`.codex-isolated/plugins/cache/*/superpowers/…`). A clone
  has the full skills framework with **no plugin install** — only the binary is fetched on
  `--install`.
- **Git-ignored** — the downloaded binary (`.codex-isolated/bin/`), secrets
  (`.codex-isolated/auth.json`, `.codex_config`), and all per-project runtime state under
  `.codex-homes/` (sessions, logs, `*.sqlite`).

The `.codex-isolated/` ignore rule is a whitelist: everything is ignored except the committed
files above, so secrets and runtime churn can never be committed by accident.

> **Existing users with a custom `config.toml`:** the base `config.toml` is tracked and acts
> as a **template** — it is copied into each per-project `CODEX_HOME` on first launch. Keep
> secrets in `.codex_config` or `auth.json`, never in `config.toml`.

## What's in a per-project home

When you launch `icodex`, it builds that project's home under `.codex-homes/<project>-<hash>/`.
Nothing heavy is duplicated: the home **points back** to the shared `.codex-isolated/` store
for everything that is identical across projects, and keeps **real, private copies** only of
what must differ per project.

| In the home | How it's wired | Why |
|-------------|----------------|-----|
| Skills (`skills/`) | symlink to the shared store | the bundled skills (`context-awareness`, `git-workflow`, `html-report`, `intent`, `mermaid-obsidian`) are the same everywhere, so every project sees them; Codex still manages its own built-in `.system` skills alongside them |
| Command rules (`rules/`) | symlink | the `rules/default.rules` policy that auto-approves safe commands (e.g. `git`) and blocks dangerous ones (e.g. `shutdown`) applies in every project |
| Plugins, login, hook scripts (`plugins/`, `auth.json`, `hooks/`) | symlink | one shared plugin cache, one login, one set of hook scripts for all projects |
| Global guidance (`AGENTS.md`) | copy, re-synced every launch | carries the shared `AGENTS.md` instructions; refreshed on each launch so edits to `.codex-isolated/AGENTS.md` reach existing project homes, while leaving the optional caveman block in place |
| Runtime config (`config.toml`) | copied once | each project may diverge — later runs only re-apply the sandbox and project trust, and never clobber your edits |
| Sessions, logs, sqlite | created by Codex, per project | your history stays isolated — two repos never share session state |

Because the shared parts are symlinks, editing a skill, a rule, or the global `AGENTS.md` in
`.codex-isolated/` takes effect on the **next launch** of every project — there is no
per-project copy to update by hand. An existing home built before this wiring is converted
automatically on its next launch (the old real `skills/` directory is replaced by the symlink).

Two things stay out of the home on purpose: the `codex` **binary** (run directly from the
shared `bin/`) and the **caveman template** (rendered into `AGENTS.md` at launch only when
`ICODEX_CAVEMAN_MODE` is set — see [`docs/wiki/caveman.md`](docs/wiki/caveman.md)).

## Codex config quick guide

icodex uses two config files:

- `.codex_config` — local wrapper settings: API key, sandbox, proxy, install repo, symlink
  path. This file is git-ignored and is the right place for secrets.
- `.codex-isolated/config.toml` — the **template** for Codex runtime settings: model, sandbox,
  approvals, permissions, plugins, projects, and UI. It is copied into each project's
  `CODEX_HOME` (`.codex-homes/<id>/config.toml`) on first launch; later runs only re-manage
  `sandbox_mode` and project trust there and never clobber your edits to a project's copy.
  Edit the template to change defaults for *new* project homes.

Common `.codex-isolated/config.toml` keys:

| Key | Simple meaning |
|-----|----------------|
| `model` | Default model name used by Codex |
| `model_reasoning_effort` | Reasoning level, for example `low`, `medium`, `high` |
| `model_provider` | Named provider to use from `[model_providers.<name>]` |
| `sandbox_mode` | Filesystem sandbox: `read-only`, `workspace-write`, or `danger-full-access` |
| `approval_policy` | When Codex asks before commands: `untrusted`, `on-request`, `never`; `on-failure` is deprecated |
| `default_permissions` | Named managed permission profile from `[permissions.<name>]` |
| `web_search` | Web search mode used by Codex |
| `bypass_hook_trust` | Allows trusted bundled hooks to run without an interactive trust prompt |
| `[marketplaces.*]` / `[plugins.*]` | Plugin marketplace paths and enabled plugins |
| `[features]` | Feature flags, for example `multi_agent = true` |
| `[projects."<path>"]` | Project trust settings (icodex auto-adds the launched project) |
| `[tui]` | Terminal UI settings such as the status line |

Useful launch safety presets:

```toml
# Safer everyday mode: write inside the workspace, ask on risk.
sandbox_mode = "workspace-write"
approval_policy = "on-request"
default_permissions = "dev-safe"

# Full filesystem access, but still ask on risky actions.
sandbox_mode = "danger-full-access"
approval_policy = "on-request"
default_permissions = "ssh-on-request"

# No sandbox and no approval prompts.
# Equivalent to: codex --dangerously-bypass-approvals-and-sandbox
sandbox_mode = "danger-full-access"
approval_policy = "never"
default_permissions = "ssh-on-request"
```

`default_permissions` is not the same as `sandbox_mode`. It selects one of the named managed
profiles below in the same TOML file, such as `dev-safe` or `ssh-on-request`. Those profiles
describe allowed files, denied secrets, network access, and SSH access. They matter most when
Codex runs with managed permissions or `workspace-write`.

> `sandbox_mode` in the template is the **starting** value for a new project home; on each run
> icodex re-applies the effective sandbox (see [Sandbox and trust](#sandbox-and-trust)) into
> that home's `config.toml`.
