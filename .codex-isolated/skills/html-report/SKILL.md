---
name: html-report
description: "Use when the user asks for a standalone or self-contained HTML report, an offline .html file, a human-readable report that opens by double-click in a browser, expandable/interactive HTML tables, or block / transition / C4 / architectural diagrams rendered in HTML (NOT Mermaid), or a dark/light themed report. Triggers on phrases like 'сделай html-отчёт', 'standalone html report', 'expandable html table', 'C4 diagram as html', 'offline report I can open in browser'. Produces ONE self-contained .html in docs/reports/ with zero external dependencies. NOT for Mermaid diagrams (use mermaid-obsidian) or Mermaid embedded in PRD/architecture docs (use prd-generator / architecture-documentation)."
version: 1.1.0
---

# Standalone HTML Reports

Generate ONE self-contained `.html` file that opens offline by double-click and shows
the requested data as styled tables and CSS diagrams with simple dynamics and a
dark/light theme toggle. Complements `mermaid-obsidian` (machine/context format) by
producing the human-readable artifact.

## Subagent Routing

Agent: `artifact-renderer`

Use a subagent when recipe selection, data-source coverage, chain-tab marker checks, or self-validation would add noisy intermediate HTML analysis to the main context.

Stay in the main context for ambiguous source selection, final file writes, and user-facing output reporting.

Return summary:
- decision: `OK`, `needs_work`, or `uncertain`
- evidence: selected recipe, source paths, requested data coverage, marker checks, and validation checks
- risks: missing data, external resource needs, non-self-contained output, chain-tab corruption, or size warnings
- next_action: the smallest main-context action required

Stop rule: missing source data, an external resource requirement, non-self-contained output, or tab corruption uncertainty stops the write. Main context keeps ambiguous source selection, final file writes, and user-facing output reporting.

## Hard Constraints (NEVER violate)

1. **Zero-dependency.** No `<script src>`, no `<link rel=stylesheet href>`, no `src=`
   / `href=` pointing at `http`/`https`/`//`/any CDN, no external images. Everything
   inline.
2. **Offline.** The file must open from `file://` by double-click — no localhost, no
   fetch.
3. **Single self-contained file.** One `.html`, no sibling assets.
4. **Both themes mandatory.** Every report ships dark AND light palettes plus a
   working toggle (see `references/themes.md`).
5. **Output directory.** Default target is `docs/reports/` in the project where the
   skill runs (the current working directory's project root). If the caller passed an
   EXPLICIT output path, write to that path instead. Create the target directory if it
   does not exist. Never invent an unrequested path. In `mode: chain`, the caller is the `result` stage after the user accepts the optional report offer. See `references/chain-report.md`; once invoked, the skill writes the single caller-supplied `<topic>-results.html`; that path is Full zone, NOT a proposal-first default `docs/reports/` file.

If faithful display would require an external resource, **escalate** — do not
inline-fetch and do not silently drop the element.

## Workflow

1. Parse the request → list the data points, the named diagrams, and the data sources.
2. Read ONLY the sources the user named. If the source choice is ambiguous, **ask
   first** (proposal-first). If a source is unreadable or contradicts the request,
   **halt** — do not fabricate data (trust is the priority).
3. Pick a recipe per item and read the matching reference file:
   - tables / block / transition / C4 / report components (note, badge, lead) → `references/css-diagrams.md`
   - pipeline / loop / state-machine with labeled, looping, or non-adjacent edges → `references/svg-diagrams.md`
   - any dynamic (expand, hover, animation) → `references/dynamics.md`
   - theme palettes + toggle → `references/themes.md` (always)
   - arbitrary node-edge graph / free connector / data plot → `references/svg-fallback.md`
   - chain final result report (IDD→SDD, `mode: chain`) → `references/chain-report.md`

   **Gold-standard reference** — for the full SVG node grammar, animated connectors, C4,
   two-axis tables, badges, and `.note` callouts, study the in-skill `references/`
   files (`svg-diagrams.md`, `svg-fallback.md`, `css-diagrams.md`) before assembling a
   non-trivial architecture report.

### Chain-mode final payload boundary

In `mode: chain`, `html-report` is the optional final report renderer for
`check-chain result` after the user accepts report generation. It does not read intent, spec, plan, or result markdown sources in chain mode. It writes the complete caller-supplied final report payload to the target path; it does not merge stage-owned tabs or preserve older stage panes.

`mode: chain` is the optional final-result HTML path. It is not used for `intent`, `spec`, or `plan` terminal review summaries. Before implementation, `check-chain` prints Russian terminal summaries directly and keeps English markdown artifacts as the source of truth.

`html-report` chain mode accepts a fully enriched final payload from the caller. That
payload may include narrative blocks, tables, `<details>`, inline SVG, CSS diagrams, and
small inline JavaScript. The caller owns all chain semantics.

All chain report user-facing text must remain Russian only. English visible UI copy is not allowed. English is allowed only for technical terms, code identifiers, file paths, stage keys (`intent`, `spec`, `plan`, `result`), hash keys, source section names, and short source fragments that would lose meaning if translated. Markdown source artifacts and implementation docs remain English outside the generated HTML report.

Small inline JavaScript is allowed only as progressive enhancement for filtering,
linked-entity highlighting, expand/collapse controls, or tab-local search. The report
must remain readable when JavaScript is disabled. no CDN, no `<script src>`, no fetch, no
external images, and no sibling assets.

4. Assemble ONE HTML document:
   - `<head>`: a single inline `<style>` (theme custom-props + recipe CSS + dynamics).
   - `<body>`: semantic HTML5 (`<table>` / `<figure>` / `<details>`), the theme-toggle
     control, and EVERY named data point + diagram (drop nothing).
   - Add an SVG / bounded inline `<script>` block ONLY if a node-edge graph needs it,
     and **log** the specific structure CSS could not express.
5. **Self-validate** the assembled string (checklist below) BEFORE writing.
6. Write the file to the target directory — `docs/reports/` by default, or the
   explicit caller-supplied path when one was passed (create the directory if
   missing). If the caller passed the path, overwriting that path is **Full** zone
   (proceed — it is a regenerated artifact). Otherwise, if the target file already
   exists, **ask first** before overwriting (proposal-first).
   In `mode: chain`, render the complete final report described in
   `references/chain-report.md` and overwrite the caller-supplied
   `<topic>-results.html`. Creating or replacing the caller-supplied file is Full zone
   because `check-chain result` already asked the user whether to generate the report.
7. Report to the user: file path, file size, and any guarded-zone logs (inline script
   used / size warning).

## Self-Validation Checklist (run before writing)

Reject and fix the assembled HTML if any fails:

- [ ] No `src=` or `href=` referencing `http`, `https`, `//`, or a CDN host.
- [ ] No `<script src=...>` and no `<link rel="stylesheet" href=...>`.
- [ ] Exactly one `.html`, no references to sibling files.
- [ ] Both theme custom-prop sets present AND the toggle control is wired.
- [ ] Every requested data point and every named diagram is present.
- [ ] Flows with retry/branch/non-adjacent edges use the `svg-diagrams.md` grammar
      (node cards + arrow markers), not a flat flex row that drops the loop/branch.
- [ ] Shared `<defs>` (dropshadow + arrow markers) present if any SVG diagram is used.
- [ ] File size ≤ 5 MB — if larger, **warn** the user (soft limit).
- [ ] Output path is under `docs/reports/` OR equals the explicit caller-supplied path — never an unrequested location.
- [ ] In `mode: chain`, no direct reads of intent/spec/plan/result markdown sources are required by this skill.
- [ ] In `mode: chain`, the complete final report content is accepted from the caller.
- [ ] In `mode: chain`, all visible UI text is Russian; English appears only as a
      technical term, code identifier, file path, stage key, hash key, source section
      name, or short untranslated source fragment.
- [ ] Any inline JavaScript is small, bounded, and progressive; core report content remains visible without it.

**`mode: chain` only** (see `references/chain-report.md`):

- [ ] The report contains intent, spec, plan, result, review, verification, docs, and
      final verdict sections.
- [ ] The report briefly and concretely describes every changed file or artifact in
      Russian, including the specific change, reason, obtained result, and evidence.
- [ ] Process diagrams are included when workflow, approval flow, hook order, command
      flow, or multi-step execution changed; architecture/dependency diagrams are
      included when boundaries changed.
- [ ] Theme toggle present and wired.
- [ ] Replacing an existing caller-supplied report does not require preserving old
      stage-owned panes.

## Autonomy Zones

| Zone | Action |
|------|--------|
| Full — generating HTML, choosing CSS layout, picking the diagram type; writing to an output path EXPLICITLY passed by the calling command, including replacing an existing caller-supplied `mode: chain` final report | proceed, no pause |
| Guarded — using inline `<script>`/`<canvas>`/SVG, or approaching 5 MB | proceed, but **log** the structure CSS can't express / **warn** on size |
| Proposal-first — which data sources to read; overwriting an existing default `docs/reports/` file with no caller path | **ask before acting** |
| No-go — writing/deleting a file outside `docs/reports/` with NO caller-supplied path; fetching any external resource | **refuse** |

> These zones OVERRIDE subagent-driven-development's "don't pause" default. Treat
> proposal-first and no-go points as HUMAN CHECKPOINTS.
