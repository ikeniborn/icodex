---
title: icodex iwiki full config externalization implementation plan
date: 2026-07-01
chain:
  intent: null
  spec: docs/superpowers/specs/2026-07-01-icodex-iwiki-path-config-design.md
review:
  plan_hash: dcc4a4f8e0fc6c19
  spec_hash: c49c1770bb5cff4b
  last_run: 2026-07-01
  phases:
    structure:     { status: passed }
    coverage:      { status: passed }
    dependencies:  { status: passed }
    verifiability: { status: passed }
    consistency:   { status: passed }
  findings: []
---

# icodex iwiki Full Config Externalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the whole `IWIKI_*` server env surface configurable from the git-ignored `.codex_config` (via `ICODEX_IWIKI_*`) and drop the machine-specific literals from `lib/iwiki/iwiki.sh`.

**Architecture:** `ensure_iwiki_wiring` resolves `command` (auto-detect + `ICODEX_IWIKI_COMMAND`) and the required tier `base_dir` / `llm_base_url` / `llm_key`; if any is empty it warns and skips wiring. `_iwiki_region_body` always writes `command` / `IWIKI_BASE_DIR` / `IWIKI_LLM_BASE_URL`, then loops eight optional var names, writing `IWIKI_<NAME>` only when `ICODEX_IWIKI_<NAME>` is set (indirect expansion) — unset optionals fall through to the server's own default. The secret `IWIKI_LLM_KEY` stays forwarded via `env_vars` (never written literally); the guard only checks its presence. `IWIKI_PROJECT_DIR` is not touched (binding is owned by `ensure_iwiki_binding`). The `ICODEX_*` allowlist already admits every key — no parser change.

**Tech Stack:** Bash (`set -uo pipefail`), the dependency-free `tests/helpers.sh` assertion library.

Spec: `docs/superpowers/specs/2026-07-01-icodex-iwiki-path-config-design.md`

---

## File Structure

- **Modify** `lib/iwiki/iwiki.sh` — `_iwiki_region_body` writes required lines + a loop over optional `ICODEX_IWIKI_*`; `ensure_iwiki_wiring` resolves the required tier and guards. Responsibility unchanged: emit/refresh the `[mcp_servers.iwiki]` region.
- **Modify** `tests/test_iwiki_wiring.sh` — config-driven assertions incl. optional emit-if-set and required-missing guard.
- **Modify** `.codex_config.example` — document the full iwiki key set.
- **Modify** `.codex_config` (local, git-ignored) — set this machine's required keys + embedding overrides. Not committed.
- **No change** to `lib/config/env.sh` or `ensure_iwiki_binding`.

---

## Task 1: Capture current iwiki literals into the local `.codex_config` (prep)

Run this **before** editing `lib/iwiki/iwiki.sh` (Task 2), while the literal values still live in source.

**Files:**
- Read: `lib/iwiki/iwiki.sh:20-23`
- Modify: `.codex_config` (local, git-ignored — NOT committed)

- [ ] **Step 1: Append the required + embedding keys, copying the literals from source**

Run (from the repo root):

```bash
url="$(sed -n 's/^[[:space:]]*IWIKI_LLM_BASE_URL = "\(.*\)"$/\1/p' lib/iwiki/iwiki.sh)"
model="$(sed -n 's/^[[:space:]]*IWIKI_EMBED_MODEL = "\(.*\)"$/\1/p' lib/iwiki/iwiki.sh)"
dims="$(sed -n 's/^[[:space:]]*IWIKI_EMBED_DIMENSIONS = "\(.*\)"$/\1/p' lib/iwiki/iwiki.sh)"
sed -i '/^ICODEX_IWIKI_BASE_DIR=/d;/^ICODEX_IWIKI_LLM_BASE_URL=/d;/^ICODEX_IWIKI_EMBED_MODEL=/d;/^ICODEX_IWIKI_EMBED_DIMENSIONS=/d' .codex_config
{
  echo "ICODEX_IWIKI_BASE_DIR=/home/altuser/Документы/Project/iwiki-personal"
  echo "ICODEX_IWIKI_LLM_BASE_URL=$url"
  echo "ICODEX_IWIKI_EMBED_MODEL=$model"
  echo "ICODEX_IWIKI_EMBED_DIMENSIONS=$dims"
} >> .codex_config
chmod 600 .codex_config
```

(The `sed -i` delete-first keeps it idempotent. `ICODEX_IWIKI_LLM_KEY` is already present in `.codex_config`; the six tuning vars stay unset so the server keeps its defaults — this preserves today's runtime behavior exactly.)

- [ ] **Step 2: Verify the required + embedding values resolve from config**

Run:

```bash
bash -c '
source lib/core/logging.sh
source lib/config/env.sh
load_config .codex_config
echo "base=[$ICODEX_IWIKI_BASE_DIR]"
echo "url=[$ICODEX_IWIKI_LLM_BASE_URL]"
echo "model=[$ICODEX_IWIKI_EMBED_MODEL]"
echo "dims=[$ICODEX_IWIKI_EMBED_DIMENSIONS]"
echo "key_set=[${ICODEX_IWIKI_LLM_KEY:+yes}]"
'
```

Expected: `base=[/home/altuser/Документы/Project/iwiki-personal]`, non-empty `url`, `model=[ollama-bge-m3]`, `dims=[1024]`, `key_set=[yes]`.

---

## Task 2: Tiered block resolution from `ICODEX_IWIKI_*` (test + implementation)

**Files:**
- Modify: `lib/iwiki/iwiki.sh:1-46`
- Test: `tests/test_iwiki_wiring.sh` (full rewrite)

- [ ] **Step 1: Rewrite the test (config-driven, optional emit-if-set, guards)**

Replace the entire contents of `tests/test_iwiki_wiring.sh` with:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

assert_exit "iwiki module exists" 0 test -f "$ROOT/lib/iwiki/iwiki.sh"
if [[ ! -f "$ROOT/lib/iwiki/iwiki.sh" ]]; then
  finish; exit $?
fi
source "$ROOT/lib/core/logging.sh"   # provides log_warn used by the guard
source "$ROOT/lib/iwiki/iwiki.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Required tier + command driven explicitly. Two optional passthrough vars are set;
# the other six are unset and must be OMITTED (server default applies).
export ICODEX_IWIKI_COMMAND="$tmp/bin/iwiki-mcp"
export ICODEX_IWIKI_BASE_DIR="$tmp/wiki-base"
export ICODEX_IWIKI_LLM_BASE_URL="http://test-llm:1234/v1"
export ICODEX_IWIKI_LLM_KEY="test-key"
export ICODEX_IWIKI_EMBED_MODEL="ollama-bge-m3"
export ICODEX_IWIKI_TOP_K="5"
unset ICODEX_IWIKI_EMBED_DIMENSIONS ICODEX_IWIKI_SCORE_THRESHOLD \
      ICODEX_IWIKI_GRAPH_DEPTH ICODEX_IWIKI_CHUNK_SIZE \
      ICODEX_IWIKI_CHUNK_OVERLAP ICODEX_IWIKI_SUMMARY_MAX_CHARS

export ICODEX_HOME_DIR="$tmp/home"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "gpt-5.5"\n[features]\nmulti_agent = true\n' > "$ICODEX_HOME_DIR/config.toml"
ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_contains "block header present"     "$cfg" "[mcp_servers.iwiki]"
assert_contains "resolved command"         "$cfg" "command = \"$tmp/bin/iwiki-mcp\""
assert_contains "env_vars present"         "$cfg" 'env_vars = ["IWIKI_LLM_KEY"]'
assert_contains "resolved base dir"        "$cfg" "IWIKI_BASE_DIR = \"$tmp/wiki-base\""
assert_contains "resolved llm url"         "$cfg" 'IWIKI_LLM_BASE_URL = "http://test-llm:1234/v1"'
assert_contains "set optional embed model" "$cfg" 'IWIKI_EMBED_MODEL = "ollama-bge-m3"'
assert_contains "set optional top_k"       "$cfg" 'IWIKI_TOP_K = "5"'
assert_eq "unset optional dims absent"    "0" "$(grep -c 'IWIKI_EMBED_DIMENSIONS' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unset optional chunk absent"   "0" "$(grep -c 'IWIKI_CHUNK_SIZE' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unset optional summary absent" "0" "$(grep -c 'IWIKI_SUMMARY_MAX_CHARS' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "secret not written literally"  "0" "$(grep -c 'test-key' "$ICODEX_HOME_DIR/config.toml")"
assert_contains "original key kept"        "$cfg" 'model = "gpt-5.5"'
assert_eq "no hardcoded home path" "0" "$(grep -c '/home/ikeniborn' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "exactly one start marker" "1" "$(grep -c '# icodex:iwiki:start' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "region is at end of file" "# icodex:iwiki:end" "$(tail -n1 "$ICODEX_HOME_DIR/config.toml")"

# --- idempotent: second run is byte-identical ---
before="$(cat "$ICODEX_HOME_DIR/config.toml")"
ensure_iwiki_wiring
after="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_eq "idempotent second run" "$before" "$after"

# --- stale region is replaced, not duplicated ---
cat > "$ICODEX_HOME_DIR/config.toml" <<'EOF'
model = "gpt-5.5"
# icodex:iwiki:start
[mcp_servers.iwiki]
command = "/old/path/iwiki-mcp"
# icodex:iwiki:end
EOF
ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_eq "stale: one start marker" "1" "$(grep -c '# icodex:iwiki:start' "$ICODEX_HOME_DIR/config.toml")"
assert_contains "stale: new command" "$cfg" "command = \"$tmp/bin/iwiki-mcp\""
assert_eq "stale: old command gone" "0" "$(grep -c '/old/path/iwiki-mcp' "$ICODEX_HOME_DIR/config.toml")"

# --- command auto-detected from PATH when ICODEX_IWIKI_COMMAND is unset ---
mkdir -p "$tmp/fakebin"
printf '#!/usr/bin/env bash\n' > "$tmp/fakebin/iwiki-mcp"
chmod +x "$tmp/fakebin/iwiki-mcp"
unset ICODEX_IWIKI_COMMAND
export ICODEX_HOME_DIR="$tmp/home-auto"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
PATH="$tmp/fakebin:$PATH" ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_contains "auto-detected command from PATH" "$cfg" "command = \"$tmp/fakebin/iwiki-mcp\""
export ICODEX_IWIKI_COMMAND="$tmp/bin/iwiki-mcp"

# --- guard: missing required llm_base_url -> no region, returns 0 ---
unset ICODEX_IWIKI_LLM_BASE_URL
export ICODEX_HOME_DIR="$tmp/home-guard-url"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
assert_exit "missing url -> noop 0" 0 ensure_iwiki_wiring
assert_eq "guard url: no region" "0" "$(grep -cF '[mcp_servers.iwiki]' "$ICODEX_HOME_DIR/config.toml")"
export ICODEX_IWIKI_LLM_BASE_URL="http://test-llm:1234/v1"

# --- guard: missing required llm_key -> no region, returns 0 ---
unset ICODEX_IWIKI_LLM_KEY IWIKI_LLM_KEY
export ICODEX_HOME_DIR="$tmp/home-guard-key"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
assert_exit "missing key -> noop 0" 0 ensure_iwiki_wiring
assert_eq "guard key: no region" "0" "$(grep -cF '[mcp_servers.iwiki]' "$ICODEX_HOME_DIR/config.toml")"
export ICODEX_IWIKI_LLM_KEY="test-key"

# --- no-op when home is unset ---
unset ICODEX_HOME_DIR
assert_exit "unset home -> noop 0" 0 ensure_iwiki_wiring

# --- no-op when config.toml is absent ---
export ICODEX_HOME_DIR="$tmp/empty"
mkdir -p "$ICODEX_HOME_DIR"
assert_exit "absent config -> noop 0" 0 ensure_iwiki_wiring
assert_eq "absent config not created" "1" "$([[ -f "$ICODEX_HOME_DIR/config.toml" ]] && echo 0 || echo 1)"

finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_iwiki_wiring.sh`
Expected: FAIL. The current code emits hardcoded `command`/`IWIKI_BASE_DIR` and a fixed env set, so `resolved command/base dir/llm url`, the optional emit-if-set assertions, `no hardcoded home path`, `stale: new command`, `auto-detected command from PATH`, and both guard cases fail.

- [ ] **Step 3: Replace the top comment + `_iwiki_region_body`**

In `lib/iwiki/iwiki.sh`, replace lines 1-25 (the shebang/header comment through the end of the current `_iwiki_region_body`):

```bash
#!/usr/bin/env bash
# Wire the iwiki MCP server into the per-project Codex home config.toml at launch.
# Always on: a delimited region registers [mcp_servers.iwiki]. Non-secret settings
# are literal; the secret IWIKI_LLM_KEY is forwarded from the environment via
# env_vars (mapped by apply_iwiki_env in lib/config/env.sh). Mirrors the region
# mechanism in lib/config/isolated.sh (_sync_agents_base_region).

_IWIKI_REGION_START="# icodex:iwiki:start"
_IWIKI_REGION_END="# icodex:iwiki:end"

# Emit the static [mcp_servers.iwiki] block (without the region markers).
# command/env_vars precede the [.env] subtable header so they bind to the
# parent table, not the subtable.
_iwiki_region_body() {
  cat <<'EOF'
[mcp_servers.iwiki]
command = "/home/ikeniborn/.local/bin/iwiki-mcp"
env_vars = ["IWIKI_LLM_KEY"]
[mcp_servers.iwiki.env]
IWIKI_BASE_DIR = "/home/ikeniborn/Documents/Project/iwiki-personal"
IWIKI_LLM_BASE_URL = REDACTED
IWIKI_EMBED_MODEL = "ollama-bge-m3"
IWIKI_EMBED_DIMENSIONS = "1024"
EOF
}
```

with:

```bash
#!/usr/bin/env bash
# Wire the iwiki MCP server into the per-project Codex home config.toml at launch.
# Always on: a delimited region registers [mcp_servers.iwiki]. The block is built
# from ICODEX_IWIKI_* config: command falls back to `command -v iwiki-mcp`;
# IWIKI_BASE_DIR / IWIKI_LLM_BASE_URL and the secret IWIKI_LLM_KEY are required
# (any unresolved -> warn + skip). Every other IWIKI_* server var is written only
# when its ICODEX_IWIKI_* is set, else the server default applies. The secret is
# forwarded via env_vars (mapped by apply_iwiki_env in lib/config/env.sh), never
# written literally. Mirrors the region mechanism in lib/config/isolated.sh
# (_sync_agents_base_region).

_IWIKI_REGION_START="# icodex:iwiki:start"
_IWIKI_REGION_END="# icodex:iwiki:end"

# Optional IWIKI_* server vars (each has a server-side default). Written only when
# the matching ICODEX_IWIKI_<NAME> is set. Extend this list to expose new vars.
_IWIKI_OPTIONAL_VARS="EMBED_MODEL EMBED_DIMENSIONS TOP_K SCORE_THRESHOLD GRAPH_DEPTH CHUNK_SIZE CHUNK_OVERLAP SUMMARY_MAX_CHARS"

# Emit the [mcp_servers.iwiki] block (without the region markers) from resolved
# values. command/env_vars precede the [.env] subtable header so they bind to the
# parent table, not the subtable. Optional vars are appended only when set.
_iwiki_region_body() { # <command> <base_dir> <llm_base_url>
  local cmd="$1" base="$2" url="$3" name cfg val
  printf '[mcp_servers.iwiki]\n'
  printf 'command = "%s"\n' "$cmd"
  printf 'env_vars = ["IWIKI_LLM_KEY"]\n'
  printf '[mcp_servers.iwiki.env]\n'
  printf 'IWIKI_BASE_DIR = "%s"\n' "$base"
  printf 'IWIKI_LLM_BASE_URL = "%s"\n' "$url"
  for name in $_IWIKI_OPTIONAL_VARS; do
    cfg="ICODEX_IWIKI_${name}"
    val="${!cfg:-}"
    [[ -n "$val" ]] && printf 'IWIKI_%s = "%s"\n' "$name" "$val"
  done
}
```

- [ ] **Step 4: Replace the head of `ensure_iwiki_wiring` with the resolve + guard**

In `lib/iwiki/iwiki.sh`, replace:

```bash
ensure_iwiki_wiring() {
  [[ -n "${ICODEX_HOME_DIR:-}" ]] || return 0
  local file="$ICODEX_HOME_DIR/config.toml" body tmp
  [[ -f "$file" ]] || return 0
  body="$(_iwiki_region_body)"
```

with:

```bash
ensure_iwiki_wiring() {
  [[ -n "${ICODEX_HOME_DIR:-}" ]] || return 0
  local file="$ICODEX_HOME_DIR/config.toml" body tmp cmd base url key
  [[ -f "$file" ]] || return 0
  cmd="${ICODEX_IWIKI_COMMAND:-$(command -v iwiki-mcp || true)}"
  base="${ICODEX_IWIKI_BASE_DIR:-}"
  url="${ICODEX_IWIKI_LLM_BASE_URL:-}"
  key="${ICODEX_IWIKI_LLM_KEY:-${IWIKI_LLM_KEY:-}}"
  if [[ -z "$cmd" || -z "$base" || -z "$url" || -z "$key" ]]; then
    log_warn "iwiki: required setting (command/base_dir/llm_base_url/llm_key) unresolved, skipping iwiki wiring"
    return 0
  fi
  body="$(_iwiki_region_body "$cmd" "$base" "$url")"
```

(The rest of the function — the `awk` region strip, the `printf` append of the region, the `cmp`/`cat`, `rm -f "$tmp"` — is unchanged.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/test_iwiki_wiring.sh`
Expected: PASS — final line `PASS=<N> FAIL=0`.

- [ ] **Step 6: Sanity-check the script parses**

Run: `bash -n lib/iwiki/iwiki.sh`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/iwiki/iwiki.sh tests/test_iwiki_wiring.sh
git commit -m "feat(iwiki): build server block from ICODEX_IWIKI_*, tiered required/optional

command auto-detected (ICODEX_IWIKI_COMMAND override); base_dir/llm_base_url/llm_key
required (guard warn+skip); 8 optional IWIKI_* vars emitted only when set, else
server default. Secret IWIKI_LLM_KEY forwarding unchanged; drops all source literals.

Co-Authored-By: Claude Opus 4.8 <REDACTED>"
```

---

## Task 3: Document the full iwiki key set in `.codex_config.example`

**Files:**
- Modify: `.codex_config.example` (tracked)

- [ ] **Step 1: Replace the iwiki block**

Replace this block in `.codex_config.example`:

```bash
# iwiki MCP server (always on in every Codex home). All non-secret settings are
# fixed in the [mcp_servers.iwiki] block (see lib/iwiki/iwiki.sh): base dir, LLM
# base URL, embed model/dimensions. The ONLY key needed here is the secret API
# key, forwarded to the server as IWIKI_LLM_KEY via the config.toml `env_vars`
# allowlist. Keep it here (this file is git-ignored, chmod 600) — never in a
# tracked config.
#ICODEX_IWIKI_LLM_KEY=sk-...
```

with:

```bash
# iwiki MCP server (always on in every Codex home). The [mcp_servers.iwiki] block
# is assembled at launch from the keys below (see lib/iwiki/iwiki.sh).
#
# Command + required tier (iwiki is NOT wired if a required value is missing):
#   ICODEX_IWIKI_COMMAND    Path to the iwiki-mcp binary. OPTIONAL: auto-detected
#                           via `command -v iwiki-mcp` (uv-tool launcher on
#                           ~/.local/bin) when unset. Set for non-standard installs.
#   ICODEX_IWIKI_BASE_DIR   Personal wiki store path. REQUIRED.
#   ICODEX_IWIKI_LLM_BASE_URL  Embeddings endpoint base URL. REQUIRED.
#   ICODEX_IWIKI_LLM_KEY    Secret embeddings API key, forwarded as IWIKI_LLM_KEY
#                           via the config.toml `env_vars` allowlist. REQUIRED,
#                           SECRET (git-ignored, chmod 600) — never in a tracked file.
#
# Optional tuning (written to the block only if set; otherwise the server default
# shown applies):
#   ICODEX_IWIKI_EMBED_MODEL       (default text-embedding-3-small)
#   ICODEX_IWIKI_EMBED_DIMENSIONS  (default 1536; must match the embed model)
#   ICODEX_IWIKI_TOP_K             (default 8)
#   ICODEX_IWIKI_SCORE_THRESHOLD   (default 0.2)
#   ICODEX_IWIKI_GRAPH_DEPTH       (default 2)
#   ICODEX_IWIKI_CHUNK_SIZE        (default 512)
#   ICODEX_IWIKI_CHUNK_OVERLAP     (default 64)
#   ICODEX_IWIKI_SUMMARY_MAX_CHARS (default 400)
#
#ICODEX_IWIKI_COMMAND=/home/you/.local/bin/iwiki-mcp
#ICODEX_IWIKI_BASE_DIR=/home/you/Documents/Project/iwiki-personal
#ICODEX_IWIKI_LLM_BASE_URL=http://localhost:11434/v1
#ICODEX_IWIKI_LLM_KEY=sk-...
#ICODEX_IWIKI_EMBED_MODEL=ollama-bge-m3
#ICODEX_IWIKI_EMBED_DIMENSIONS=1024
```

- [ ] **Step 2: Commit the tracked example only**

```bash
git add .codex_config.example
git commit -m "docs(iwiki): document full ICODEX_IWIKI_* key set (required + optional)

Co-Authored-By: Claude Opus 4.8 <REDACTED>"
```

---

## Task 4: Full-suite verification and IDD closeout

**Files:**
- No source changes. Verification + docs.

- [ ] **Step 1: Confirm no hardcoded home path and no value-literals remain in tracked source**

Run:

```bash
grep -RIn "/home/ikeniborn" lib/ tests/
grep -n 'IWIKI_LLM_BASE_URL = "http' lib/iwiki/iwiki.sh
grep -n 'IWIKI_EMBED_MODEL = "ollama-bge-m3"' lib/iwiki/iwiki.sh
grep -n 'IWIKI_EMBED_DIMENSIONS = "1024"' lib/iwiki/iwiki.sh
```

Expected: all four print nothing (exit 1). Each targets a *value* literal, so the post-change template line `IWIKI_LLM_BASE_URL = "$url"` and the loop-emitted optional lines (which use the config value, not `ollama-bge-m3`/`1024` literals) are correctly not matched. If any prints, that literal was not externalized — fix before continuing.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
fail=0; for t in tests/test_*.sh; do bash "$t" >/tmp/t.log 2>&1 || { echo "FAILED: $t"; tail -3 /tmp/t.log; fail=1; }; done; [ "$fail" = 0 ] && echo "ALL GREEN"
```

Expected: `ALL GREEN` (no `FAILED:` lines). `test_iwiki_wiring.sh`, `test_iwiki_env.sh`, `test_iwiki_binding.sh`, and `test_smoke.sh` in particular must pass.

- [ ] **Step 3: Update the iwiki wiki page for the changed module**

Only if the iwiki MCP server reports a domain bound to this project:

Run `wiki_status`. If a domain named `icodex` is bound (note: current binding is domain `codex` — if the bound write domain differs, use it), update the page describing the iwiki wiring to reflect the tiered model (command auto-detect; three required with warn+skip guard; eight optional emit-if-set passthrough; secret unchanged; `IWIKI_PROJECT_DIR` excluded), then:
- `wiki_write_page(domain=<bound write domain>, slug=<iwiki-wiring page slug>, markdown=<updated>, source="lib/iwiki/iwiki.sh")`
- `wiki_index(<bound write domain>)`
- `wiki_lint` — expect no broken `[[refs]]`, no orphan/stale pages.

If no project domain is bound, skip this step.

- [ ] **Step 4: Run check-result to close the IDD chain**

Dispatch a clean-context subagent to run `/check-result` for topic `icodex-iwiki-path-config` against this plan and the implemented changes; collect the verdict in the main session. On verdict `OK`, `docs/TODO.md` is closed (`Result: OK`, `Status: done`, `Closed: <today>`) by that command.

---

## Self-Review

**Spec coverage:**
- Spec §`command` (auto-detect + override) → Task 2 Step 4 (`cmd=...`). ✓
- Spec required tier + guard (base/url/key, command resolvable) → Task 2 Step 4 guard. ✓
- Spec optional-passthrough loop (8 vars, emit-if-set) → Task 2 Step 3 `_IWIKI_OPTIONAL_VARS` loop; Task 2 Step 1 asserts set-present + unset-absent. ✓
- Spec "secret never written literally, guard checks presence" → block keeps `env_vars`; test `secret not written literally`; guard `key` case. ✓
- Spec `IWIKI_PROJECT_DIR` out of scope → not referenced in code/tasks. ✓
- Spec §Implementation surface `.codex_config.example` → Task 3; local `.codex_config` → Task 1; `tests/test_iwiki_wiring.sh` → Task 2. ✓
- Spec "no change to env.sh / binding" → not in tasks. ✓
- Spec §Success criteria → Task 4 Step 1-2 + Task 2 Step 1 assertions. ✓

**Placeholder scan:** No TODO/TBD/"handle edge cases". Every code step shows exact old/new text or full content. `REDACTED` in the Step 3 "old" block is the harness's display redaction of the current `IWIKI_LLM_BASE_URL` literal; the "new" block does not carry it (the URL comes from `$url`). ✓

**Type/name consistency:** `_iwiki_region_body "$cmd" "$base" "$url"` (3 args) matches the new `$1..$3` signature; the loop reads `ICODEX_IWIKI_${name}` for names in `_IWIKI_OPTIONAL_VARS`, matching the test's `ICODEX_IWIKI_EMBED_MODEL` / `_TOP_K` set-cases and the unset six; guard var `key` reads `ICODEX_IWIKI_LLM_KEY` (fallback `IWIKI_LLM_KEY`); `log_warn` matches `lib/core/logging.sh:4`. ✓
