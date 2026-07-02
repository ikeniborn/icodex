---
title: LoEn automation governance design
date: 2026-07-02
status: draft
chain:
  intent: null
---

# LoEn automation governance design

## Purpose

Define the later automation and governance layer for LoEn. This layer is not the
first implementation target. It becomes active only after manual LoEn loops prove
that the skills, artifacts, hooks, and verifier evidence are stable.

## Automation Types

LoEn supports these future automation classes:

| Class | Use case | Default autonomy |
|---|---|---|
| CI triage | Detect failing checks and write a repair report. | Advisory |
| PR babysitting | Watch review comments and propose scoped fixes. | Guarded |
| Dependency audit | Run scheduled dependency checks and report risk. | Advisory |
| Eval governance | Run fixed evals and detect drift. | Guarded |
| Cost or latency governance | Compare metrics and open reports. | Advisory |

Automation must not auto-merge, change protected files, or rewrite eval data.

## Preconditions

Automation is allowed only when:

- the prompt has passed manual trial runs;
- `docs/loen/<topic>/loop.yaml` has explicit scope, tools, budget, stop rules,
  and handoff conditions;
- verifier evidence is deterministic;
- first scheduled outputs are reviewed by a human;
- rollback and handoff behavior is documented.

## Runtime Model

Automated runs use the same topic artifact structure:

```text
docs/loen/<topic>/
```

Each scheduled or background run appends to `attempts.jsonl`, stores evidence,
updates numbered stage files, and regenerates `audit.html`.

## Governance Fields

`loop.yaml` gains optional governance fields:

```yaml
governance:
  schedule: "weekday 09:00"
  first_runs_require_human_review: 3
  auto_fix: false
  auto_merge: false
  report_only_on_no_findings: true
  alert_on:
    - protected_scope_attempt
    - verifier_failure
    - budget_exhausted
    - metric_regression
```

## Tests

This layer should add tests that validate:

- automation config defaults to no auto-merge;
- first-run human review counters are enforced;
- automated attempts still update `audit.html`;
- protected-scope and evidence gates apply to automation;
- no scheduled mode bypasses `LOEN_MODE`.

## Acceptance

- Automation is a later controlled layer, not a default behavior.
- Scheduled and background loops reuse the same artifacts and hooks.
- Governance rules prevent unattended risky changes.
