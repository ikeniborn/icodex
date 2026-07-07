# Goal

Topic: `chain-report-ru-update-skip`

## User Request

Check the quality of the `check-chain` skill around HTML report generation for every chain stage. The generated report must use Russian only for all user-facing visible text. Also improve `icodex --update` so it does not download the Codex archive when the latest release version is unchanged from the installed pinned version.

## Success Criteria

- `check-chain` report instructions and generated report artifacts no longer expose English diagram titles, UI labels, fallback text, or review-flow labels in visible HTML, except for allowed technical identifiers such as file paths, code names, hashes, and short source fragments.
- A focused test detects known English visible strings in `docs/superpowers/reports/check-chain-report-quality-results.html` and protects all four chain tabs.
- `install_ensure --update` resolves the latest release but skips `_download`, SHA verification, extraction, and lockfile rewrite when the installed stamp and lockfile version already match the latest tag.
- Focused Bash tests cover the unchanged-version `--update` path and still cover the changed-version update path.
- Verification commands pass and evidence is recorded under `docs/loen/chain-report-ru-update-skip/evidence/`.
