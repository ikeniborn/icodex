# icodex

Isolated bash wrapper for the [OpenAI Codex CLI](https://developers.openai.com/codex/cli),
built following the `iclaude` example. Installs a pinned static codex binary into the
project, isolates codex state via `CODEX_HOME`, and optionally routes traffic through a proxy.

## Usage

    ./icodex.sh --install          # fetch the pinned binary
    ./icodex.sh                    # launch codex in the isolated environment
    ./icodex.sh --proxy http://p:8080 exec "..."   # via proxy, args forwarded to codex
    ./icodex.sh --update           # update + re-pin the binary
    ./icodex.sh --version          # icodex + codex versions

State lives in `.codex-isolated/` (git-ignored). The binary is pinned by version + sha256
in `.codex-lockfile.json` (committed). Auth (`codex login` / `OPENAI_API_KEY`) is written
into the isolated `CODEX_HOME` by codex itself — the wrapper never stores credentials.
