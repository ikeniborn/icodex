# Context

Topic: `chain-report-ru-update-skip`

## Facts

- Project language is Bash; full verification is `for t in tests/test_*.sh; do bash "$t" || exit 1; done`.
- Current branch is `dev-chain-report-update-skip`, created from up-to-date `master`.
- `docs/TODO.md` marks `check-chain-report-quality` as done, but the actual generated report still has visible English strings such as `Step DAG`, `Artifact Impact Map`, `Verification Map`, `Human Checkpoint Flow`, `Diff Reconciliation Graph`, `Outcome Evidence Map`, `Excess/Gap Map`, `Markdown source of truth`, and `review surface`.
- Current `tests/test_chain_report_quality.sh` checks skill contract text, but does not fail on visible English in the generated HTML report.
- `.codex-isolated/skills/check-chain/SKILL.md` already says all chain report user-facing text must be Russian and visible diagram titles must be Russian.
- `.codex-isolated/skills/html-report/SKILL.md` already says English visible UI copy is not allowed in chain mode.
- `lib/binary/install.sh` currently resolves latest on `install_ensure --update`, then always builds the release URL, downloads the archive, verifies SHA, extracts, and rewrites the lockfile.
- `tests/test_install.sh` already covers normal install idempotency and changed-version update, but lacks the unchanged-latest update skip path.
- iwiki domain `icodex` is bound. `wiki_lint` reports a stale page for `.codex-isolated/skills/check-chain/SKILL.md` plus unrelated missing-source/advisory findings.

## Constraints

- Keep markdown artifacts and documentation in English unless the artifact is generated user-facing HTML.
- Keep generated chain report visible text Russian-only, with exceptions only for technical identifiers, code paths, stage keys, hash keys, and source fragments that would lose meaning if translated.
- Do not change `chain-gate.py`, the frontmatter contract, `docs/TODO.md` schema, or chain verdict semantics.
- Do not make `html-report` read chain source markdown directly in chain mode.
- Do not use network in tests; mock `_resolve_latest` and `_download` seams.
- Preserve `--update` behavior when the latest tag differs, the binary is missing, or the stamp does not match.
- Update repository docs/wiki after implementation because `--update` behavior changes.
