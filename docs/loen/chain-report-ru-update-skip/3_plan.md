# Plan

Topic: `chain-report-ru-update-skip`

## Steps

1. Audit current chain HTML report language -> verify: run a focused grep over `docs/superpowers/reports/check-chain-report-quality-results.html` and record all known visible English report labels by tab.
2. Add a focused report-language regression test -> verify: `bash tests/test_chain_report_quality.sh` fails before report/instruction cleanup when banned visible English labels remain.
3. Tighten `check-chain` / `html-report` chain-mode instructions and translate the existing `check-chain-report-quality-results.html` visible labels -> verify: `bash tests/test_chain_report_quality.sh` passes and the report has no banned canonical English diagram titles or review-flow labels.
4. Add unchanged-version update idempotency coverage in `tests/test_install.sh` -> verify: the new case proves `_resolve_latest` is called once, `_download` is not called, the old lockfile SHA is preserved, and a user-facing skip log is emitted.
5. Implement the `install_ensure --update` short path in `lib/binary/install.sh` -> verify: `bash tests/test_install.sh` passes, including existing changed-version update cases.
6. Update docs/wiki for changed `--update` behavior and record LoEn evidence -> verify: `wiki_lint(domain="icodex")` has no new contradictions for the touched pages and evidence files summarize command results.

## Checks

```bash
bash tests/test_chain_report_quality.sh
bash tests/test_install.sh
bash tests/test_update_scope.sh
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

## Report-Language Audit Command

```bash
grep -nE '>(Step DAG|Artifact Impact Map|Verification Map|Human Checkpoint Flow|Diff Reconciliation Graph|Outcome Evidence Map|Excess/Gap Map|Outcome Chain|Constraint Matrix|Autonomy Map|Context Map|Requirement Coverage Map|Component Graph|Data Flow|Risk/Mitigation Map|Code Review Findings Map|Documentation Evidence Map|Decision Propagation Map|Markdown source of truth|review surface|Executive overview|Approval lens|Source anchors|Findings|Summary)<' docs/superpowers/reports/check-chain-report-quality-results.html
```

Expected after implementation: no matches, except technical identifiers inside `<code>` if a test explicitly allows them.
