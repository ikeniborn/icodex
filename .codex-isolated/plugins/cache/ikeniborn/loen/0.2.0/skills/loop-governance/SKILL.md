---
name: loop-governance
description: LoEn skill for scheduled or recurring checks with governance artifacts under docs/loen/<topic>/.
---

# LoEn Loop Governance

Use this skill when a LoEn topic represents a recurring check, scheduled governance pass, dependency audit, CI triage report, eval drift check, or cost/latency comparison.

## Governance Subtypes

- `report-only`: inspect, verify, write findings and evidence, and avoid product-file edits.
- `auto-fix`: apply bounded fixes only inside mutable scope when `governance.auto_fix: true`; never merge or release.
- `merge-release`: proceed only when `governance.auto_merge: true` and `release_policy:` records target branch, merge strategy, verifier requirement, evidence requirement, `scope_limit`, and recovery policy.

## Procedure

1. Record recurrence, owner, and review requirement in `docs/loen/<topic>/loop.yaml` under `governance:`.
2. Record subtype policy for `report-only`, `auto-fix`, or `merge-release`.
3. Keep scheduled activity advisory unless the repository owner explicitly enables stricter `LOEN_MODE`.
4. Record every run in `attempts.jsonl` with `automation: true`, `run_type`, status, summary, evidence path, review flags, and timestamp.
5. Treat approved `merge-release` start-time approval plus complete `release_policy:` as the LoEn approval for merge/release; still respect external branch rules, host approval prompts, repository safety gates, destructive-operation review, protected-scope review, and first-run review recorded in `first_runs_require_human_review`.
6. Keep `auto_merge: false` and `auto_fix: false` unless the approved subtype explicitly enables `auto-fix` or `merge-release` policy.
7. Run the topic verifier and regenerate `audit.html` after each scheduled attempt.

## Output

Report schedule, owner, latest evidence, whether human review is still required, alert reasons, and next run condition.
