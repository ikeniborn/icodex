# LoEn Smoke Case Matrix

This matrix creates analysis conditions for delivery and governance runner usage on the current master snapshot.

| Topic | Mode | Subtype | Expected | Terminal | Preflight | Verifier | Artifact Dir |
|---|---|---|---|---|---|---|---|
| `smoke-delivery-pass` | `delivery` | `null` | `result` | `result` | `approved run contract` | `PASS` | `docs/loen/smoke-delivery-pass` |
| `smoke-governance-report-only` | `governance` | `report-only` | `result` | `result` | `approved run contract` | `PASS` | `docs/loen/smoke-governance-report-only` |
| `smoke-governance-auto-fix` | `governance` | `auto-fix` | `result` | `result` | `approved run contract` | `PASS` | `docs/loen/smoke-governance-auto-fix` |
| `smoke-governance-merge-release` | `governance` | `merge-release` | `result` | `result` | `approved run contract` | `PASS` | `docs/loen/smoke-governance-merge-release` |
| `smoke-governance-negative-policy` | `governance` | `merge-release` | `handoff` | `handoff` | `merge-release policy incomplete` | `merge-release policy incomplete` | `docs/loen/smoke-governance-negative-policy` |

## Quality Notes

- Delivery smoke proves approved plan hash, mutable scope, verifier execution, evidence capture, result, and audit rendering.
- Governance report-only proves evidence/report completion without product-file edits.
- Governance auto-fix proves bounded mutation inside usable mutable scope and verifier confirmation.
- Governance merge-release is dry-run only: it proves policy completeness and evidence flow, not external branch protection or real release mechanics.
- Negative governance case proves incomplete merge-release policy stops before action and writes handoff.
