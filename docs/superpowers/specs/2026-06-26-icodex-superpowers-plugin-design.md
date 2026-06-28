---
review:
  spec_hash: b1eb4cd16243f9c4
  last_run: 2026-06-26
  phases:
    structure:   { status: passed }
    coverage:    { status: passed }
    clarity:     { status: passed }
    consistency: { status: passed }
  findings:
    - id: F-006
      phase: consistency
      severity: CRITICAL
      section: "4.1 vs 4.4"
      section_hash: 64ed5e7e0535dbd5
      fragment: "[plugins.\"superpowers@superpowers\"] vs codex plugin add superpowers@<marketplace>"
      text: "config.toml.example hard-codes the marketplace name `superpowers`, but `codex plugin marketplace add` has no --name flag and auto-derives it (observed: superpowers-dev). On a host where the name differs, the plugin would not load (R3 broken)."
      fix: "Vendor script canonicalizes the marketplace name to `superpowers` (renames cache dir + section names); launcher also derives the name from the cache path. Literal keys are now stable."
      verdict: fixed
      verdict_at: 2026-06-26
    - id: F-007
      phase: consistency
      severity: WARNING
      section: "4.2 vs 3"
      section_hash: 2a5c307d5fa9e20c
      fragment: "ABS = \"$ICODEX_ROOT/$CACHE\" with a relative glob"
      text: "Glob base/CWD was unspecified; a relative glob resolved from the launch CWD would miss, silently disabling the plugin."
      fix: "Anchor the glob at $ICODEX_ROOT (absolute); ABS is the matched dir itself, no re-concatenation. Added CWD-independence test."
      verdict: fixed
      verdict_at: 2026-06-26
    - id: F-008
      phase: consistency
      severity: WARNING
      section: "4.1 vs 4.2"
      section_hash: 2a5c307d5fa9e20c
      fragment: "rewrite the [marketplaces.*].source line"
      text: "Rewriting the first [marketplaces.*] is undefined once >1 marketplace is vendored (cf. §9)."
      fix: "Rewrite only [marketplaces.$MKT].source for the derived name."
      verdict: fixed
      verdict_at: 2026-06-26
    - id: F-003
      phase: clarity
      severity: WARNING
      section: "4.4"
      section_hash: 1adf110d03adad82
      fragment: "re-running against the same upstream ref reproduces the same files"
      text: "Determinism claim had no acceptance criterion and a moving tag is not reproducible."
      fix: "Pin by immutable sha; acceptance: second run yields empty `git diff --stat`."
      verdict: fixed
      verdict_at: 2026-06-26
    - id: F-004
      phase: clarity
      severity: WARNING
      section: "4.4"
      section_hash: 1adf110d03adad82
      fragment: "strip vendored .git and any nested .gitignore inside the copied tree"
      text: "No verification that a nested .gitignore is gone; a leftover would re-exclude plugin files and silently break R1."
      fix: "Added DoD: `find ... -name .gitignore` empty and `git ls-files ... | wc -l` > 0; mirrored as a test in §8."
      verdict: fixed
      verdict_at: 2026-06-26
    - id: F-010
      phase: consistency
      severity: INFO
      section: "4.1"
      section_hash: 64ed5e7e0535dbd5
      fragment: "source = \".../superpowers/superpowers/6.0.3\""
      text: "Hard-coded version in the sentinel could drift from the cache version."
      fix: "Changed to <ver> placeholder; documented that the launcher rewrites the whole source line, so the example version is non-binding."
      verdict: fixed
      verdict_at: 2026-06-26
chain:
  intent: null
---

# icodex — Superpowers Plugin Integration Design

> Date: 2026-06-26
> Status: Approved (design phase)
> Scope: Vendor the Superpowers skills framework into icodex as a git-delivered Codex plugin

---

## 1. Purpose

Integrate the [Superpowers](https://github.com/obra/superpowers) agentic-skills framework
(brainstorming, TDD, systematic-debugging, writing-plans, subagent-driven-development, …)
into `icodex` so the isolated Codex CLI ships with it preinstalled.

The integration is **git-first**: the installed plugin, the user skills, and the wiring all
travel inside the repository. A fresh clone needs **no plugin installation** — only the
codex binary is fetched on `--install` (and that fetch must honor the configured proxy).

### Requirements (from the requester)

1. The Superpowers plugin (skills + hooks) lands in git.
2. `.codex-isolated/skills/` (user-level skills) lands in git.
3. Installed plugins are delivered **through git, without re-installation** on other
   machines. The only thing `--install` builds is the binary.
4. The binary download must go through the proxy declared in `.codex_config`
   (`ICODEX_PROXY`).
5. The machine-specific absolute path problem is solved via `ICODEX_ROOT` — the wrapper
   always runs the isolated process and can derive the correct absolute path on any host.

### Why a Codex-native plugin (not loose skills)

Codex CLI 0.142.2 ships a first-class plugin system. A plugin registers its skills **and**
its hooks (the SessionStart hook that injects `using-superpowers`). Loose user skills under
`$CODEX_HOME/skills/` would load the skills but not the hook, so the
"You have superpowers" bootstrap would be lost. Vendoring the native plugin keeps the full
framework behavior.

---

## 2. Codex facts that shape this design

Established by direct probing of the pinned binary (`codex-cli 0.142.2`):

- **Plugin model is marketplace-based.** `codex plugin marketplace add <local|git>` builds a
  snapshot and writes `[marketplaces.<name>]` to `config.toml`; `codex plugin add
  <plugin>@<marketplace>` copies the plugin into
  `$CODEX_HOME/plugins/cache/<marketplace>/<plugin>/<version>/` and writes
  `[plugins."<plugin>@<marketplace>"] enabled = true`.
- **The installed cache is what loads at runtime** — a purely declarative, hand-written
  `config.toml` (marketplace + plugin enabled, no cache) does **not** load the plugin
  (`available: []`). The cache copy is required and is not lazily rebuilt.
- **The marketplace `source` path is validated on every launch.** If the path is missing or
  moved, codex aborts with `failed to load configured marketplace snapshot(s)` — not only on
  management commands. So `source` must resolve to a valid marketplace root at run time.
- **`source` must be absolute.** A relative `source` resolves against the process CWD, not
  `CODEX_HOME`, and fails to find the manifest.
- **A launch-time `-c marketplaces.<name>.source=...` override does NOT fix a stale path.**
  Rewriting the `source` line in `config.toml` before launch **does**.
- **`source` must point at a marketplace root, not the installed cache directory.** Current
  Codex validates the marketplace manifest before loading installed plugins; pointing
  `source` at `$CODEX_HOME/plugins/cache/<marketplace>/<plugin>/<version>/` fails with
  `marketplace root does not contain a supported manifest`. The launcher generates a small
  runtime marketplace root that links `./plugins/superpowers` to the committed installed cache.
- **`config.toml` keys** `marketplaces`, `plugins`, `skills`, `hooks`, `features`, and
  `bypass_hook_trust` are recognized. Subagent skills need `features.multi_agent = true`.
  Plugin hooks require trust; `bypass_hook_trust = true` lets the SessionStart hook fire
  non-interactively.
- **`$CODEX_HOME/skills/` is auto-discovered** as a separate user-skill catalog, independent
  of plugin skills. The Superpowers skill names do not collide with the existing icodex user
  skills (`context-awareness`, `git-workflow`, `html-report`, `intent`, `mermaid-obsidian`).
- **`icodex.sh` already exports `ICODEX_ROOT`** (resolved through symlinks), so the wrapper
  always knows its own absolute root on any host.

---

## 3. Architecture

**Git carries the installed artifacts; the launcher fixes the one machine-specific value
(`source`) at run time from `ICODEX_ROOT`.** No plugin install on clone.

### What is committed vs runtime

```
.codex-isolated/
├── skills/**                                  COMMITTED  user skills
│   └── .system/**                             ignored    codex-managed system skills
├── plugins/cache/<mkt>/superpowers/<ver>/**   COMMITTED  installed plugin (~2 MB, no .git)
├── config.toml.example                        COMMITTED  curated base + plugin wiring
├── config.toml                                ignored    live; source line fixed each launch
├── AGENTS.md / AGENTS.override.md             COMMITTED  (unchanged)
└── bin/codex                                  ignored    fetched on --install (via proxy)
```

The duplicate marketplace source tree is intentionally **not** vendored. At launch, icodex
generates a small runtime marketplace root under `.codex-isolated/tmp/marketplaces/` and
points `source` there. That generated root links back to the committed cache directory (§2).

### `.gitignore` (whitelist additions)

```gitignore
# user skills travel in git (system skills are codex-managed, stay ignored)
!.codex-isolated/skills/
!.codex-isolated/skills/**
.codex-isolated/skills/.system/

# installed plugins travel in git (no re-install on clone)
!.codex-isolated/plugins/
!.codex-isolated/plugins/**

# committed config template; live config.toml is runtime (source rewritten per host)
!.codex-isolated/config.toml.example
```

`config.toml` is removed from the whitelist (it was committed before this change). The live
`config.toml` becomes git-ignored runtime state, mirroring the existing
`.codex_config` / `.codex_config.example` split.

---

## 4. Components

### 4.1 `.codex-isolated/config.toml.example` (new, committed)

Curated base plus the Superpowers wiring. The `source` carries a sentinel token that the
launcher replaces with the real absolute path.

```toml
# ... existing curated examples (model_provider, etc.) ...

[marketplaces.superpowers]
source_type = "local"
source = "__ICODEX_ROOT__/.codex-isolated/plugins/cache/superpowers/superpowers/<ver>"

[plugins."superpowers@superpowers"]
enabled = true

[features]
multi_agent = true

bypass_hook_trust = true
```

> **Canonical marketplace name.** `codex plugin marketplace add` has no `--name` flag and
> auto-derives the name from the source (observed: `superpowers-dev`). The committed artifact
> must NOT depend on that. The refresh script (§4.4) therefore **canonicalizes** the name to
> `superpowers`: it renames the cache directory to
> `plugins/cache/superpowers/superpowers/<ver>/` and writes the marketplace/plugin section
> names as the literal `superpowers`. These literal keys are then stable across every clone.
> The `<ver>` segment in `source` is illustrative — the launcher (§4.2) rewrites the entire
> `source` line from the real cache path on each run, so a stale version here is harmless.
> The launcher additionally derives the marketplace name from the cache path, so it never
> depends on this literal either (belt and suspenders).

> **As-built note (implementation, adjudicated).** Canonicalization to the literal
> `superpowers` proved **not achievable**: Codex derives the marketplace name from the
> vendored `.claude-plugin/marketplace.json`, which is `superpowers-dev` — renaming the cache
> dir does not change it, and patching the upstream manifest would break vendoring hygiene.
> The implementation therefore standardizes on the **upstream-authoritative** name
> `superpowers-dev` everywhere (cache dir `plugins/cache/superpowers-dev/superpowers/<ver>/`,
> example sections `[marketplaces.superpowers-dev]` / `[plugins."superpowers@superpowers-dev"]`).
> This name is deterministic and machine-independent (it comes from upstream, not from the
> host), and the launcher's path-derived rewrite (§4.2) stays fully name-agnostic, so the
> F-006 portability guarantee holds. End-to-end verified: `codex plugin list` loads the plugin.

### 4.2 `lib/plugin/superpowers.sh` (new) — invoked from launch

Runs on the default launch path, before `launch_codex`. Pure, idempotent, offline:

```
ensure_superpowers_wiring():
  1. live config.toml missing  → cp config.toml.example → config.toml
  2. CACHE=( "$ICODEX_ROOT"/.codex-isolated/plugins/cache/*/superpowers/*/ )   # absolute glob, CWD-independent
     - 0 matches → log_warn "superpowers plugin not vendored", return (no hard fail)
     ABS="${CACHE[0]%/}"                                  # already absolute; no re-concatenation
     MKT=$(basename "$(dirname "$(dirname "$ABS")")")     # marketplace dir name (canonical: superpowers)
  3. generate `.codex-isolated/tmp/marketplaces/$MKT/`:
     - `.agents/plugins/marketplace.json`
     - `.agents/plugins/api_marketplace.json`
     - `plugins/superpowers` symlink to `ABS`
  4. rewrite ONLY the source line inside the [marketplaces.$MKT] section of config.toml to the
     generated marketplace root, and only if it differs (idempotent; sentinel or stale path →
     generated root)
```

Notes that make this correct regardless of host or CWD:

- The glob is anchored at `$ICODEX_ROOT` (absolute), so it does not depend on the process CWD
  at launch. `ABS` is the matched cache directory itself — not re-prefixed with `ICODEX_ROOT`.
- The rewrite targets the named section `[marketplaces.$MKT]` (not the first `[marketplaces.*]`),
  so it stays correct if other Codex plugins/marketplaces are vendored later (cf. §9).
- The generated marketplace root uses a relative plugin path (`./plugins/superpowers`) because
  Codex expects plugin entries in marketplace manifests to resolve from the marketplace root.

The rewrite is the entire `ICODEX_ROOT` mechanism: every host (and every relocated clone)
gets a correct absolute `source` without re-running `codex plugin` commands.

`icodex.sh` sources `plugin/superpowers` and calls `ensure_superpowers_wiring` in the default
(launch) branch, after `setup_codex_home`, before `launch_codex`. The `install` / `update`
branches do **not** call it (they only build the binary).

### 4.3 `lib/binary/install.sh` (edit) — proxy-aware binary fetch

The binary download must use `ICODEX_PROXY` when set and not disabled:

```
if ICODEX_PROXY set AND NOT ICODEX_DISABLE_PROXY:
    curl --proxy "$ICODEX_PROXY" ...        # download tarball through the proxy
else:
    curl ...                                # direct
```

This applies to both `--install` and `--update` (and the implicit install on first launch).
Today the binary fetch bypasses the proxy entirely; this closes that gap. The proxy value is
already loaded by `load_config` before the install runs, so no ordering change in `main()` is
required beyond reading `ICODEX_PROXY` inside the download.

### 4.4 `scripts/vendor-superpowers.sh` (new) — maintainer refresh

"Install once on one machine → deliver via git." Run by a maintainer when bumping the
Superpowers version:

```
1. SCRATCH=$(mktemp -d); export CODEX_HOME=$SCRATCH
2. codex plugin marketplace add <git-or-local superpowers> --ref <immutable-sha>
3. codex plugin add superpowers@<auto-derived-marketplace-name>
4. canonicalize the name: rsync the produced
   plugins/cache/<auto-name>/superpowers/<ver>/ into
   .codex-isolated/plugins/cache/superpowers/superpowers/<ver>/   (replace existing)
5. strip vendored .git and any nested .gitignore inside the copied tree
6. update the <ver> segment in config.toml.example's source line (illustrative only; see §4.1)
7. git add -A .codex-isolated/plugins .codex-isolated/config.toml.example
```

**Pin & verify (acceptance for the refresh):**

- Pin step 2 by an **immutable commit sha**, not a moving tag, so a re-run is reproducible:
  after a second run with the same sha, `git diff --stat .codex-isolated/plugins` is empty.
- After step 7, assert the vendored tree is fully tracked and not silently filtered:
  `git ls-files .codex-isolated/plugins/cache | wc -l` > 0, and
  `find .codex-isolated/plugins/cache -name .gitignore` is empty (a leftover nested
  `.gitignore` would re-exclude plugin files and silently break R1).

### 4.5 `icodex.sh` (edit)

- Add `plugin/superpowers` to the module source list.
- In the default branch only, call `ensure_superpowers_wiring` between `setup_codex_home` and
  the proxy/launch steps.

---

## 5. Data flow

```
git clone icodex
  └─ brings: skills/**, plugins/cache/.../6.0.3/**, config.toml.example   (installed plugin)

./icodex.sh --install
  └─ fetch codex binary ONLY, through ICODEX_PROXY            (no plugin work)

./icodex.sh           (launch)
  ├─ setup_codex_home (export CODEX_HOME=.codex-isolated)
  ├─ ensure_superpowers_wiring:
  │     config.toml ← config.toml.example (if missing)
  │     rewrite [marketplaces.*].source → $ICODEX_ROOT/.../6.0.3
  ├─ proxy_apply (unless --no-proxy)
  └─ exec codex
        └─ loads plugin from cache; SessionStart hook injects "You have superpowers"
```

---

## 6. Migration (one-time, in the implementing branch)

```
git rm --cached .codex-isolated/config.toml
mv .codex-isolated/config.toml  →  .codex-isolated/config.toml.example  (content + wiring)
git add .codex-isolated/skills (minus .system) .codex-isolated/plugins/cache/...
edit .gitignore per §3
```

Existing local `.codex-isolated/config.toml` files keep working (now untracked); the launcher
materializes one from the example only when absent.

---

## 7. Error handling

- Vendored cache absent at launch → `log_warn` and continue (codex runs without the plugin,
  rather than hard-failing the wrapper).
- `config.toml.example` absent → `log_error` (broken checkout) and continue without wiring.
- Binary fetch through a bad proxy → existing curl error surfaces; `--no-proxy` is the escape
  hatch (consistent with the current proxy semantics).
- No handling for impossible cases (simplicity principle).

---

## 8. Testing

`tests/test_plugin.sh` (new), following the existing bash harness:

- `ensure_superpowers_wiring` rewrites a sentinel `source` to `$ICODEX_ROOT/...`.
- Idempotent: a second call makes no change.
- Stale absolute `source` (simulating a relocated clone) is rewritten to the current root.
- CWD-independence: invoked from an unrelated CWD, the cache glob still resolves and the
  rewrite is correct (the glob is anchored at `$ICODEX_ROOT`).
- The rewrite targets `[marketplaces.$MKT].source` for the derived `$MKT`, leaving any other
  `[marketplaces.*]` section untouched.
- Missing live `config.toml` is materialized from `config.toml.example`.
- Missing cache → warn, no crash, no rewrite.
- Vendored cache hygiene: no nested `.gitignore` under `.codex-isolated/plugins/cache/`, and
  the committed cache path is the canonical `cache/superpowers/superpowers/<ver>/`.
- `binary/install.sh`: with `ICODEX_PROXY` set, the download invokes curl with `--proxy`;
  with `--no-proxy`, it does not.
- `.gitignore` whitelist: `skills/**` and `plugins/**` are tracked, `skills/.system/**` and
  live `config.toml` are ignored.

### Success criteria

On a clean clone, **offline except for the binary**:

1. `./icodex.sh --install` fetches only the binary, through the configured proxy.
2. Launch rewrites `source` to this host's absolute path.
3. `codex plugin list` shows `superpowers` enabled with no `plugin add` step.
4. A codex session prints the "You have superpowers" SessionStart context and can load the
   `brainstorming` skill.
5. Moving the repo to a different absolute path still launches cleanly (source re-fixed).

---

## 9. Open refinements (post-integration)

- Pin a recorded Superpowers version/sha alongside the cache (lockfile-style) for auditability.
- Optionally fold `vendor-superpowers.sh` into `--update` behind an explicit flag.
- Evaluate trusting only the Superpowers hook instead of the global `bypass_hook_trust`.
- Multi-version cache coexistence if more Codex plugins are vendored later.
