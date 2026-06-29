---
review:
  spec_hash: "dca0402951279942"
  last_run: 2026-06-29
  phases:
    structure:   { status: passed }
    coverage:    { status: passed }
    clarity:     { status: passed }
    consistency: { status: passed }
  findings:
    - id: F-001
      phase: coverage
      severity: WARNING
      section: "### Per-project config generation (gap #2 surface)"
      fragment: "addressing backlog gap #8 minimally (no manual trust edits for new repos)"
      text: >-
        Auto-trust upserts trust_level = "trusted" for the target; the trust-vs-approval
        boundary was not stated.
      fix: >-
        Added a sentence: trust_level governs project trust only and does not alter
        approval_policy = "on-request"; approvals still apply. Scope/idempotency noted.
      verdict: fixed
    - id: F-002
      phase: clarity
      severity: INFO
      section: "## Migration / backward compatibility"
      fragment: "It is left in place (harmless)."
      text: >-
        "harmless" asserted without a criterion for the orphaned .codex-isolated files.
      fix: >-
        Stated the criterion: CODEX_HOME resolves to .codex-homes/<id>/, codex never
        reads the orphaned files; asserted by test.
      verdict: fixed
    - id: F-003
      phase: clarity
      severity: INFO
      section: "### Per-project config generation (gap #2 surface)"
      fragment: "addressing backlog gap #8 minimally"
      text: >-
        "minimally" used without a measurable bound.
      fix: >-
        Dropped "minimally"; bound the requirement to a single [projects."<target>"]
        block asserted idempotent by test.
      verdict: fixed
chain:
  intent: docs/superpowers/intents/2026-06-28-icodex-external-workspace-sandbox-intent.md
---

# icodex Runtime Isolation — Design Spec

Date: 2026-06-29
Status: Approved (design)
Scope: Backlog P0 #1 (runtime filesystem isolation) and P0 #2 (per-project CODEX_HOME).
Source backlog: `docs/superpowers/reports/icodex-runtime-stability-backlog.md`

## Problem

Two coupled P0 gaps make icodex unsafe and leaky when launched from repositories
other than the wrapper repo:

1. **Isolation is not strict by default.** `.codex-isolated/config.toml` ships with
   `sandbox_mode = "danger-full-access"`. The OS-level sandbox is therefore off, and
   filesystem protection relies entirely on the managed permission deny-globs. Any
   launch from any directory grants full filesystem visibility by default.

2. **All projects share one CODEX_HOME.** `CODEX_HOME` is hard-wired to
   `$ICODEX_ROOT/.codex-isolated` regardless of the working directory, so auth,
   sessions, history, sqlite, memories, and logs are shared across every target
   project. Launching from project B exposes project A's session state, memory, and
   login.

These are coupled: a per-project home plus a safe-by-default sandbox together give
real isolation.

## Decisions (locked)

- **Per-project homes, centralized** under `$ICODEX_ROOT/.codex-homes/<id>/`.
  Target repos stay clean.
- **Shared auth.** `auth.json` is shared across all projects (single login). Only
  sessions / history / memory / logs are isolated per project.
- **Sandbox safe by default.** Default `sandbox_mode = "workspace-write"`. Escalation
  to `danger-full-access` is explicit via the `--full-access` flag or the
  `ICODEX_SANDBOX` config key, and prints a stderr warning.
- **Approval policy unchanged** (`on-request`). Escalating the sandbox never
  auto-bypasses approvals.
- **Dependency-light preserved.** Pure bash / awk / ln. No new dependencies.

## Architecture

### Path split: shared store vs per-project home

Today `ICODEX_HOME_DIR` carries two roles — expensive shared assets and per-project
runtime state. The design splits them:

```
$ICODEX_ROOT/.codex-isolated/        <- ICODEX_SHARED_DIR  (committed assets + git-ignored runtime auth)
  bin/codex, bin/uv                  <- shared binary + uv (ICODEX_BIN path unchanged)
  bin/.codex-version                 <- install stamp
  plugins/cache/...                  <- vendored Superpowers cache (shared)
  auth.json                          <- shared login (git-ignored)
  config.toml                        <- TEMPLATE (committed)

$ICODEX_ROOT/.codex-homes/<id>/      <- ICODEX_HOME_DIR  (git-ignored, exported as CODEX_HOME)
  config.toml                        <- copied from template; managed lines upserted each run
  plugins      -> ../../.codex-isolated/plugins      (symlink -> shared)
  auth.json    -> ../../.codex-isolated/auth.json    (symlink -> shared)
  tmp/marketplaces/<mkt>/...         <- superpowers wiring (per-project; plugin link -> shared cache)
  sessions/ history/ log/ *.sqlite   <- real per-project state (codex creates these)
```

### Project identity (`<id>`)

- Target root = `git rev-parse --show-toplevel` of the current working directory;
  fall back to the realpath of the working directory when not inside a git repo.
  Launching from a subdirectory of a repo therefore reuses one home per repo.
- `<id> = <basename>-<short-sha256>` where the sha256 is computed over the absolute
  target root via the existing `_sha256` helper. The short hash disambiguates
  same-named projects in different paths.

### Module changes

- **`lib/core/init.sh`** — introduce `ICODEX_SHARED_DIR` (= `.codex-isolated`) and
  `ICODEX_HOMES_DIR` (= `.codex-homes`). Re-point `ICODEX_BIN` and `ICODEX_STAMP` at
  `ICODEX_SHARED_DIR/bin` (paths are unchanged from today). `ICODEX_HOME_DIR` becomes
  dynamic, resolved per run from the target root.
- **`lib/config/isolated.sh`** — `setup_codex_home` resolves the per-project home,
  creates it, symlinks `plugins` and `auth.json` into the shared store, copies the
  template `config.toml` when absent, and exports `CODEX_HOME` to the per-project home.
- **`lib/binary/install.sh`** — `bin/` paths target `ICODEX_SHARED_DIR`. `install` and
  `update` operate on the shared store only and do not create a per-project home.
- **`lib/plugin/superpowers.sh`** — the cache glob reads from `ICODEX_SHARED_DIR`,
  while the marketplace root / manifest / config rewrite target the per-project
  `ICODEX_HOME_DIR` (resolves through the `plugins` symlink).
- **`lib/config/sandbox.sh`** (new) — resolve the effective sandbox mode and upsert the
  top-level `sandbox_mode` line in the per-project `config.toml`.
- **`lib/command/args.sh`** — add the `--full-access` flag and its help entry.
- **`icodex.sh`** — `install`/`update` use a lightweight shared-dir setup; the run path
  keeps `setup_codex_home` then applies sandbox + trust before launch.

### Sandbox escalation (gap #1)

Effective sandbox precedence, low to high:

```
template default ("workspace-write")  <  ICODEX_SANDBOX (.codex_config)  <  --full-access (flag)
```

- Allowed values: `read-only`, `workspace-write`, `danger-full-access`. An invalid
  `ICODEX_SANDBOX` is a fatal `log_error` + non-zero exit.
- `ICODEX_SANDBOX` already passes `_config_key_allowed` (matches `ICODEX_[A-Z0-9_]*`),
  so `lib/config/env.sh` needs no change.
- `--full-access` forces `danger-full-access` for a single run and overrides the env
  value.
- Whenever the effective mode is `danger-full-access`, print a stderr warning before
  launch:
  `WARN: sandbox = danger-full-access — full filesystem access enabled (project: <id>)`
- The write is an idempotent awk upsert of the top-level `sandbox_mode = "<eff>"` key,
  mirroring `_rewrite_marketplace_source`.

### Per-project config generation (gap #2 surface)

Following the existing idempotent-rewrite philosophy, only **managed lines** are
rewritten each run; user edits inside a per-project `config.toml` are preserved:

1. Home absent → copy the shared template `config.toml` into the home.
2. Each run, idempotently upsert:
   - `sandbox_mode` (effective value, above).
   - marketplace `source` (existing `_rewrite_marketplace_source`).
   - launcher binary read grant (existing `ensure_launcher_binary_permission`,
     pointing at the unchanged shared `ICODEX_BIN`).
   - **trust for the current target**: upsert `[projects."<target-root>"]` with
     `trust_level = "trusted"`. This auto-trusts the launched repo, addressing
     backlog gap #8 (no manual trust edits for new repos). The upsert is scoped to a
     single `[projects."<target-root>"]` block and is asserted idempotent by test.
     `trust_level` governs project trust only; it does not alter
     `approval_policy = "on-request"`, so risky actions still prompt for approval.

## Migration / backward compatibility

- `bin/`, `plugins/`, `auth.json`, and the template `config.toml` remain in
  `.codex-isolated`, so the binary path is unchanged and no reinstall is required.
- The shared login is unaffected: `auth.json` already lives in `.codex-isolated`,
  which is the shared store.
- Pre-existing runtime state in `.codex-isolated` (`sessions/`, `history`, `*.sqlite`)
  becomes orphaned — it was the old shared state. It is left in place. This is safe
  because `CODEX_HOME` now resolves to `.codex-homes/<id>/`, so codex never reads the
  orphaned `.codex-isolated` runtime files; a test asserts the run path does not point
  `CODEX_HOME` at `.codex-isolated`. The wrapper repo's own new per-project home does
  not inherit this history. This is documented behavior, not a bug.
- `.codex-homes/` is added to git ignore (matching the existing allowlist style in
  `.gitignore`).

## Testing (TDD)

| Test | Asserts |
|---|---|
| `tests/test_isolated.sh` (extended) | per-project home id from git-toplevel/cwd; `plugins` and `auth.json` symlinks point at shared; template copy on first run; `CODEX_HOME` export |
| `tests/test_sandbox.sh` (new) | precedence default→env→flag; invalid `ICODEX_SANDBOX` exits non-zero; stderr warning on `danger-full-access`; idempotent `sandbox_mode` upsert |
| `tests/test_install.sh` / `tests/test_update_scope.sh` | install/update target the shared `bin`; no per-project home is created |
| `tests/test_plugin.sh` | superpowers cache glob resolves through the `plugins` symlink; marketplace root lands in the per-project home |
| `tests/test_smoke.sh` | end-to-end run path with the new layout |
| trust test (in `test_isolated.sh` or a new file) | `[projects."<target>"]` upsert is idempotent |

## Out of scope (YAGNI)

- Garbage collection / pruning of stale `.codex-homes/<id>` entries; `--list-homes`.
- An isolated-auth mode (per-project `auth.json`).
- A three-level sandbox UX beyond the documented precedence.
- Other backlog items (P0 #3 doctor/preflight, P1 locking, rollback) are separate.

These are noted as possible future work and intentionally excluded from this spec.

## Verification criteria

- Launch from a non-wrapper repo → `CODEX_HOME` resolves under `.codex-homes/<id>/`,
  distinct per project; sessions written there, not in `.codex-isolated`.
- Two different target repos → distinct homes; no cross-project session/memory bleed.
- Default launch → `sandbox_mode = "workspace-write"` in the active config; no warning.
- `--full-access` (or `ICODEX_SANDBOX=danger-full-access`) → `danger-full-access` in
  config and a stderr warning.
- `install` / `update` write only under `.codex-isolated/bin` and create no home.
- All updated and new tests pass.
