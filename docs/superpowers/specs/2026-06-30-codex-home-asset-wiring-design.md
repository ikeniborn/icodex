---
review:
  spec_hash: 3934a4596bfccf78
  last_run: 2026-06-30
  phases:
    structure:   { status: passed }
    coverage:    { status: passed }
    clarity:     { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: null
---
# CODEX_HOME asset wiring: skills, rules, AGENTS.md base region

- Date: 2026-06-30
- Status: approved (design)
- Scope: `lib/config/isolated.sh` (`setup_codex_home`), `tests/test_isolated.sh`, wiki docs

## Problem

`setup_codex_home` (`lib/config/isolated.sh`) builds the per-project home
(`.codex-homes/<id>/`) by symlinking a fixed set of shared-store assets from
`.codex-isolated/` — `plugins`, `hooks`, `hooks.json`, `auth.json` — and copying
`config.toml`. Three committed, git-tracked assets never reach the home, so they
are dead at runtime even though `README.md` ("What lives in git") advertises them
as a ready-to-use template:

| Asset in `.codex-isolated/` | git-tracked | reaches home today | gap |
| --- | --- | --- | --- |
| `skills/*` (context-awareness, git-workflow, html-report, intent, mermaid-obsidian) | yes (`.gitignore` "user skills travel in git") | no | user skills invisible to Codex; home `skills/` only holds codex-managed `.system` |
| `AGENTS.md` (global guidelines, ~5.5 KB) | yes | base content lost | home `AGENTS.md` carries only the caveman region; the base block never lands |
| `rules/default.rules` (Codex execution policy, `prefix_rule(...)`) | yes | no | home has no `rules/`; the command allowlist never applies |

### Caveman is not broken (clarification, no change)

Two user questions resolve to "works as designed", verified against the live home
and `docs/wiki/caveman.md`:

- `.codex-isolated/caveman/` is a **template**, not a runtime asset.
  `_caveman_render_block` reads `caveman/agents-block.md` at launch, substitutes the
  mode, and writes the result into a delimited region of the home `AGENTS.md`. No
  symlink is needed or made — intentional.
- Caveman is absent from the shared `.codex-isolated/hooks.json` **by design**
  (unset/off = ship default). When `ICODEX_CAVEMAN_MODE` is set,
  `_caveman_enable_hooks_json` merges the `UserPromptSubmit` entry into the
  per-project home `hooks.json` (replacing the symlink with a real file). The hook
  command `python3 "$CODEX_HOME/hooks/caveman-hook.py"` resolves through the `hooks`
  symlink to `.codex-isolated/hooks/caveman-hook.py`. The live home confirms the
  entry is present and the path resolves. Working.

No caveman code changes in this work.

## Goals

- Make the committed `skills/` and `rules/` assets active in the per-project home.
- Make the global `AGENTS.md` base content present in the home **and kept current**:
  edits to `.codex-isolated/AGENTS.md` must propagate to existing homes on the next
  launch, without clobbering the caveman region or any hand-added free text.

## Non-goals

- No change to caveman wiring.
- No change to the `config.toml` copy-once behavior (out of scope; not requested).
- No fix for the cosmetic `hooks.json` churn (symlink → overwrite each run).
- No handling of `AGENTS.override.md` (file absent).
- No adjacent refactor.

## Design

All changes land in `setup_codex_home` plus one new helper in
`lib/config/isolated.sh`.

### 1. skills — whole-dir symlink (variant A)

Add `_link_shared skills`. The existing `_link_shared` helper removes the current
home `skills/` (a real dir holding codex-managed `.system`) and symlinks
`$CODEX_HOME/skills` → `.codex-isolated/skills`. Codex regenerates `.system` under
the shared dir on next run; `.gitignore` already ignores
`.codex-isolated/skills/.system/`. The five user skills become discoverable at
runtime. Idempotent: `_link_shared` returns early when the target is already the
symlink.

Rationale for variant A over per-skill symlinks: one line, matches the existing
`_link_shared` pattern, `.gitignore` is already prepared for a shared `.system`,
and codex-managed `.system` content is identical across projects, so sharing it is
harmless.

### 2. rules — whole-dir symlink

Add `_link_shared rules`. `$CODEX_HOME/rules` → `.codex-isolated/rules`. The rules
file is a read-only execution-policy template Codex never writes to. Verify during
implementation (by launching `icodex`) that Codex actually consumes
`$CODEX_HOME/rules/default.rules`; `README.md` lists it as a committed runtime
template, so the intent is clear, but no `lib/` code references the path today.

### 3. AGENTS.md — delimited base region, re-synced each launch

`AGENTS.md` cannot be a symlink: caveman mutates the file, and a symlink would
write into the git-tracked source. Copy-once would go stale. Instead, manage the
base content as a delimited region that is re-synced on every launch — mirroring
the caveman region mechanism.

Markers:

```
<!-- icodex:base:start -->
…contents of .codex-isolated/AGENTS.md…
<!-- icodex:base:end -->
```

New helper `_sync_agents_base_region <file>`, a sibling of
`_caveman_write_agents_region`:

1. If `.codex-isolated/AGENTS.md` is missing → return (skip).
2. awk-strip any existing `icodex:base` region from `<file>`.
3. Append a fresh region built from the current `.codex-isolated/AGENTS.md`.
4. Write back only when the result differs (`cmp -s`).

Called from `setup_codex_home` after the home dir exists. The home `AGENTS.md` then
carries two independently-managed regions:

```
<!-- icodex:base:start -->   … base …   <!-- icodex:base:end -->
<!-- icodex:caveman:start --> … caveman … <!-- icodex:caveman:end -->
```

Ordering in `main()` is already correct: `setup_codex_home` (base) runs before
`ensure_caveman_wiring` (caveman). Both helpers strip+append only their own region,
so they are independently idempotent; any hand-added text outside both regions
survives. The two strip-and-append passes may transiently reorder the regions
within a run, but the file is content-stable after both run. This reorder costs at
most one extra tiny write per launch — acceptable.

### Resulting `setup_codex_home` additions

```sh
_link_shared skills          # user skills → runtime (variant A)
_link_shared rules           # execution-policy → runtime
_sync_agents_base_region "$ICODEX_HOME_DIR/AGENTS.md"   # base region, re-synced each launch
# config.toml copy-once — unchanged
```

## Test plan

Extend `tests/test_isolated.sh` (already exercises `setup_codex_home`):

- Shared-store fixture grows a `skills/` dir (with a sample user skill and a
  `.system/` dir), a `rules/default.rules`, and an `AGENTS.md` base file.
- After `setup_codex_home`:
  - `$CODEX_HOME/skills` is a symlink to `.codex-isolated/skills`.
  - `$CODEX_HOME/rules` is a symlink to `.codex-isolated/rules`.
  - `$CODEX_HOME/AGENTS.md` exists and contains the base content inside the
    `icodex:base` region.
- Re-sync: change `.codex-isolated/AGENTS.md`, re-run, assert the home `AGENTS.md`
  base region reflects the new content.
- Coexistence: with a caveman region already present, a base re-sync leaves the
  caveman region intact.
- Idempotency: running `setup_codex_home` twice yields a content-stable
  `AGENTS.md` and unchanged symlinks.

Run the full `tests/` suite. Then a real `icodex` launch in a scratch project:
confirm Codex lists the user skills and that `rules/default.rules` is honored.

## Files

- `lib/config/isolated.sh` — `_link_shared skills`, `_link_shared rules`, new
  `_sync_agents_base_region` + call.
- `tests/test_isolated.sh` — assertions above.
- `docs/wiki/architecture.md` — document the expanded home-build step; re-ingest
  via iwiki.

## Risks

- **rules consumption unverified** — mitigated by the launch check in the test
  plan; if Codex does not read `$CODEX_HOME/rules/`, drop step 2 (the symlink is
  inert, not harmful).
- **shared `.system`** — codex-managed `.system` moves under `.codex-isolated/`
  (gitignored). Identical content across projects; low risk.
- **AGENTS.md base staleness elsewhere** — only the delimited base region is
  synced; `config.toml` staleness is unchanged and out of scope.
