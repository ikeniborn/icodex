# Repository Guidelines

## Project Structure & Module Organization

`icodex.sh` is the main Bash entrypoint. Runtime modules live under `lib/`, grouped by responsibility: `core/`, `command/`, `binary/`, `config/`, `proxy/`, `plugin/`, `launcher/`, and `symlink/`. Maintenance scripts live in `scripts/`. Tests are standalone Bash files in `tests/`, with shared assertions in `tests/helpers.sh`. Project documentation and design notes are under `docs/superpowers/`. The isolated Codex home template is tracked selectively in `.codex-isolated/`; do not add secrets or runtime state there.

## Build, Test, and Development Commands

- `./icodex.sh --help` prints supported wrapper commands and options.
- `./icodex.sh --install` fetches the pinned Codex binary and creates the local symlink.
- `./icodex.sh --version` prints the wrapper version and installed Codex version, if present.
- `bash tests/test_smoke.sh` runs the smoke test.
- `for t in tests/test_*.sh; do bash "$t" || exit 1; done` runs the full Bash test suite.

There is no package manager or Makefile in this repository; keep new commands dependency-free unless the project explicitly adopts a tool.

## Coding Style & Naming Conventions

Use Bash with `#!/usr/bin/env bash`. Prefer `set -euo pipefail` for executable paths and `set -uo pipefail` in tests that intentionally inspect failures. Use two-space indentation inside functions and conditionals, matching existing files. Keep module functions focused and name them with lowercase words separated by underscores, for example `install_ensure` or `ensure_iwiki_wiring`. Environment variables should use the `ICODEX_` prefix for wrapper configuration.

## Testing Guidelines

Add or update a focused `tests/test_*.sh` file for behavior changes. Source `tests/helpers.sh` and use `assert_eq`, `assert_exit`, and `assert_contains` for readable checks. Tests should avoid network access where possible and use temporary directories for filesystem side effects.

## Commit & Pull Request Guidelines

Git history mostly follows Conventional Commits, such as `feat(plugin): ...`, `fix(vendor): ...`, `docs(spec): ...`, and `chore: ...`. Keep commits scoped to one change. For pull requests, include a short summary, test commands run, and any user-visible behavior or configuration changes. Link related design docs or issues when applicable.

## Security & Configuration Tips

Keep secrets in `.codex_config` or Codex auth files, never in tracked docs or scripts. Do not commit downloaded binaries, SQLite runtime state, logs, tokens, or local credentials. When editing `.codex-isolated/`, respect the existing whitelist-style tracking model.

<!-- iwiki-mcp:tool-surface:start — copied from iwiki-mcp templates/AGENTS.md.snippet; refresh from there rather than editing in place -->

## iwiki (shared wiki via MCP)

This project is bound to a shared wiki base (see `.iwiki.toml`: `read` = domains to
search, `write` = domain to author into). Use the `iwiki` MCP tools:

- **Before starting a task:** call `wiki_search` with the topic to recall existing
  knowledge (scope `project` for the read-set, `all` for the whole base).
- **Binding changes are manual setup:** do not create domains, call `wiki_bind`, or
  index source areas during ordinary project startup. If the project is not bound
  or the write domain is missing, report that setup is required and ask the user
  before changing `.iwiki.toml` or creating a domain.
- **After changing functionality:** use `wiki_write_page` for a new page,
  `wiki_update_page` for one existing `##` section, and `wiki_delete_page` only
  when the documented source was removed. `new_heading` renames that section. Run
  `wiki_lint` after the write.
- **Links and cache:** use relative `<type>/<slug>.md#heading` links inside one domain;
  use `iwiki://<domain>/<page-id>#<anchor>` only across domains. Do not link to root
  `index.md` / `log.md`: they are generated, not graph pages. `.iwiki/graph.sqlite3`
  is a local rebuildable cache excluded from Git; keep domain `index.jsonl` and
  `log.jsonl` portable and let the server rebuild the graph after clone or pull.
- **Periodically / at end of session:** call `wiki_sync` to pull/push the base.
- Editing an existing page is section-scoped through `wiki_update_page`;
  `wiki_write_page` still refuses to overwrite a page.
- Cross-domain page moves and heading renames rewrite exact links automatically only
  when all visible referrers are writable; a read-only visible referrer blocks before
  the mutation. Hidden domains are not inspected or rewritten.
- **GWT maintenance:** before editing an existing `type: specification` scenario, call
  `wiki_spec_context`. After code or test changes, call `wiki_spec_resolve` when a ready
  code graph exists. If the graph is unavailable, preserve declared selectors, record
  that evidence, and continue with repository search and executable tests. Record the
  test command, exit status, and repository revision in the task ledger; review the
  scenario, implementation bindings, executable test, and evidence as one unit.
- **More reads:** `wiki_status` confirms resolved scope, storage, and specification mode
  before relying on anything below. `wiki_read_page(domain, slug, heading=…)` reads one
  page, or with `heading` just one `##` section. `wiki_list_pages(domain)` and
  `wiki_list_domains` enumerate slugs and visible domains. `wiki_related(domain,
  section_id)` returns vector+graph neighbours of one section, domain-local only.
- **More page mutations:** `wiki_insert_section` / `wiki_delete_section` /
  `wiki_move_section` add, remove, or reorder one `##` section without rewriting the rest
  of the page. `wiki_index(domain)` rebuilds one domain's index — only after out-of-band
  Markdown edits, never as a routine step after a tool write.
- **Code graph** (only when `[code_graph] enabled = true` and the touched language is
  configured): `wiki_code_index` builds/rebuilds from the local checkout — `source_unavailable`
  on a PostgreSQL-only binding with no checkout. `wiki_code_status(job_id=…)` polls a
  build or reports the graph's current state. `wiki_code_search` finds typed entities
  (file/module/class/function/method) to use as seeds. `wiki_code_context(seeds=…)`
  traverses from exact `py:`/`ts:`/`js:`/`sh:` ids returned by `wiki_code_search`, never a
  qualified name. `wiki_code_publish_begin` / `wiki_code_publish_batch` /
  `wiki_code_publish_finalize` / `wiki_code_publish_abort` move a
  locally built snapshot to a hosted server under `publish_mode = "mcp"` — never
  hand-assemble a batch, rebuild with `wiki_code_index` and let `iwiki-mcp code publish`
  stream it. `wiki_code_refresh_links(domain)` re-derives one domain's wiki links after a
  snapshot republish, without reparsing source.
- **More specifications:** `wiki_spec_search` finds projected Given-When-Then scenarios
  across the read scope before designing a new one.
- **Governance (not routine writing):** `wiki_migrate_okf` / `wiki_apply_okf` /
  `wiki_export_okf` / `wiki_remediation_plan` operate the OKF layout and lint remediation —
  Git storage only, `unsupported_storage` on PostgreSQL. `wiki_create_domain` provisions an
  empty domain; on PostgreSQL only from a hosted authenticated session, else
  `unsupported_storage`. `wiki_list_domain_grants` / `wiki_set_domain_grant` /
  `wiki_revoke_domain_grant` administer another token's domain access — hosted PostgreSQL
  only, never used to widen the caller's own scope.

<!-- iwiki-mcp:tool-surface:end -->
