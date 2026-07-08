# LoEn Smoke Quality Report

## Summary

- Cases: 5
- Analyzer failures: 0
- Coverage: delivery success, governance report-only success, governance auto-fix success, governance merge-release dry-run success, governance merge-release incomplete-policy handoff.

## Assessment

- `loop-start` contract shape is usable: every positive case has approval, plan hash, mode, subtype, verifier, scope, budget, and rollback/recovery policy.
- `loop-run` preflight is strict enough to stop an incomplete `merge-release` policy before action.
- Evidence model is consistent: positive cases have verifier output, `5_check.md` PASS, `7_result.md` Done, and audit verdict Done.
- Governance attempts are visible in `attempts.jsonl` and audit output.
- Current smoke does not prove real external merge/release. It intentionally uses dry-run evidence to avoid unsafe repository operations.

## Case Details

### `smoke-delivery-pass`

- Mode/subtype: `delivery` / `null`
- Terminal: `result`; expected `result`
- Preflight: `approved run contract`
- Verifier: `PASS`
- Evidence files: `evidence/delivery-output.txt`, `evidence/latest-test.json`, `evidence/latest-test.log`
- Attempts: 0

### `smoke-governance-report-only`

- Mode/subtype: `governance` / `report-only`
- Terminal: `result`; expected `result`
- Preflight: `approved run contract`
- Verifier: `PASS`
- Evidence files: `evidence/governance-report.txt`, `evidence/latest-test.json`, `evidence/latest-test.log`
- Attempts: 1

### `smoke-governance-auto-fix`

- Mode/subtype: `governance` / `auto-fix`
- Terminal: `result`; expected `result`
- Preflight: `approved run contract`
- Verifier: `PASS`
- Evidence files: `evidence/auto-fix.txt`, `evidence/latest-test.json`, `evidence/latest-test.log`
- Attempts: 1

### `smoke-governance-merge-release`

- Mode/subtype: `governance` / `merge-release`
- Terminal: `result`; expected `result`
- Preflight: `approved run contract`
- Verifier: `PASS`
- Evidence files: `evidence/latest-test.json`, `evidence/latest-test.log`, `evidence/release-dry-run.txt`
- Attempts: 1

### `smoke-governance-negative-policy`

- Mode/subtype: `governance` / `merge-release`
- Terminal: `handoff`; expected `handoff`
- Preflight: `merge-release policy incomplete`
- Verifier: `merge-release policy incomplete`
- Evidence files: none
- Attempts: 1
