# Chain Report (final IDD→SDD result report)

`mode: chain` produces ONE unified report for a whole IDD→SDD task. The report is generated once at `check-chain result`, after implementation evidence exists. Earlier
`intent`, `spec`, and `plan` validations update frontmatter and `docs/TODO.md` only;
they do not create or refresh HTML.

Default `standalone` mode (no `mode` passed) is unchanged. This file applies only when
the caller passes `mode: chain`.

## Caller Contract

The caller is `check-chain result`. It invokes the skill with:

- `mode: chain` — selects this code path.
- `target: docs/superpowers/reports/<topic>-results.html` — the final report file.
- A complete inline final payload containing current intent, spec, plan, result
  reconciliation, review findings, verification evidence, documentation evidence, TODO
  state, and the final verdict.

The skill never reads chain sources itself; all report content arrives inline. It may
overwrite an existing caller-supplied `target` without asking because the target is an
explicit regenerated artifact.

## Final Report Blocks

The caller owns the chain semantics and passes complete final-report HTML. The report
should contain:

- executive overview;
- source anchors for intent/spec/plan/result evidence;
- full change inventory covering every changed file or artifact, with a brief,
  concrete Russian description of the specific change made within this task, why it
  changed, what result was obtained, and what evidence verifies it;
- intent outcomes and stop rules;
- spec requirements and acceptance coverage;
- plan steps and diff reconciliation;
- code review findings and fix evidence;
- verification commands and observed output;
- repository docs / iwiki evidence, including `wiki_lint` when bound;
- decision propagation or unchanged-with-rationale notes;
- final `OK` / `needs_work` verdict.

All visible report text is Russian only. English is allowed only for technical terms, source
anchors, English markdown section names, paths, code identifiers, stage keys
(`intent`, `spec`, `plan`, `result`), hash keys, and short source fragments.

Canonical diagram names below are internal identifiers; titles in generated HTML must be Russian unless the title is itself a technical term.

Visible Russian title map:

- Outcome Chain -> Цепочка результатов
- Constraint Matrix -> Матрица ограничений
- Autonomy Map -> Карта автономии
- Context Map -> Карта контекста
- Requirement Coverage Map -> Карта покрытия требований
- Component Graph -> Граф компонентов
- Data Flow -> Поток данных
- Risk/Mitigation Map -> Карта рисков и мер
- Step DAG -> Граф шагов
- Artifact Impact Map -> Карта влияния на артефакты
- Verification Map -> Карта проверок
- Human Checkpoint Flow -> Поток человеческих контрольных точек
- Diff Reconciliation Graph -> Граф сверки diff
- Outcome Evidence Map -> Карта свидетельств результатов
- Excess/Gap Map -> Карта лишнего и пропусков
- Code Review Findings Map -> Карта замечаний code review
- Documentation Evidence Map -> Карта документационных свидетельств
- Decision Propagation Map -> Карта распространения решений
- Change Inventory Map -> Карта изменений
- Process Flow Map -> Карта процесса

## Mandatory Rich Visualizations

The final report includes semantic diagrams or compact matrices for the full chain:

- Intent: `Outcome Chain`, `Constraint Matrix`, `Autonomy Map`, `Context Map`.
- Spec: `Requirement Coverage Map`, `Component Graph`, `Data Flow`,
  `Risk/Mitigation Map`.
- Plan: `Step DAG`, `Artifact Impact Map`, `Verification Map`,
  `Human Checkpoint Flow`.
- Result: `Diff Reconciliation Graph`, `Outcome Evidence Map`, `Excess/Gap Map`,
  `Change Inventory Map`, `Code Review Findings Map`, `Documentation Evidence Map`,
  `Decision Propagation Map`, `Process Flow Map` when workflow changed.

Add process diagrams when workflow, approval flow, hook order, command flow, or
multi-step execution changed. Add architecture or dependency diagrams when the diff
changes boundaries between skills, hooks, plugins, scripts, docs, or runtime artifacts.
If no diagram is warranted, record a Russian rationale explaining why a table is clearer
than a diagram.

If a source lacks enough structure for a full diagram, render a compact matrix plus the
explicit Russian fallback note: `В источнике недостаточно структуры для полноценной
схемы; показана компактная матрица.`

## Review Flow

Intent, spec, and plan review happens from checked markdown plus the validation summary,
not from HTML. If the user requests changes before implementation, update the relevant
markdown source first and rerun the relevant `check-chain <stage>` validation. No HTML
is regenerated until `check-chain result`.

At result time, the final report is the user-facing closeout artifact. If the user
requests result-report changes, update the underlying markdown, implementation,
verification evidence, docs, or wiki source first, rerun the affected checks, then
regenerate the final report with `check-chain result`.

Small inline JavaScript may support filtering, highlighting, expand/collapse controls,
or local search, but the report must remain readable without JavaScript. Never add CDN
or external runtime dependencies.

## Document Skeleton

The unified file is one self-contained HTML document. Tabs are optional; sections are
acceptable. The renderer may use this high-level skeleton:

```html
<body>
  <input type="checkbox" id="theme-toggle" hidden>
  <header>
    <label for="theme-toggle" class="theme-btn" title="Переключить тёмную/светлую тему">🌙 / ☀️</label>
    <h1>…topic…</h1>
  </header>
  <main>
    <section id="summary">…</section>
    <section id="intent">…</section>
    <section id="spec">…</section>
    <section id="plan">…</section>
    <section id="result">…</section>
    <section id="verification">…</section>
    <section id="documentation">…</section>
    <section id="verdict">…</section>
  </main>
</body>
```

## Self-Validation

- [ ] One self-contained HTML file; no external assets, CDN, fetch, `<script src>`, or
      stylesheet links.
- [ ] Theme toggle present and wired.
- [ ] Intent, spec, plan, result, review, verification, documentation, decision
      propagation, and final verdict content present.
- [ ] Every changed file or artifact is described briefly and concretely in Russian,
      including the specific change, reason, obtained result, and evidence.
- [ ] All visible UI text is Russian except allowed technical terms and source
      fragments.
- [ ] Every diagram or matrix is anchored in source artifacts or result evidence, and
      process diagrams are included when workflow changed.
- [ ] Existing caller-supplied report may be replaced completely; no stage-owned tab
      preservation is required.

## Autonomy

The unified `target` is caller-supplied ⇒ **Full** zone: create or replace it without a
proposal-first pause. The proposal-first overwrite rule applies only when the skill
chooses the default `docs/reports/` path with no explicit caller path.
