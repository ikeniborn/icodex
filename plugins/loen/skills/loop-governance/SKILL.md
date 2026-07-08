---
name: loop-governance
description: LoEn skill for scheduled or recurring checks with governance artifacts under docs/loen/<topic>/.
---

# LoEn Loop Governance

Use this skill when a LoEn topic represents a recurring check, scheduled governance pass, dependency audit, CI triage report, eval drift check, or cost/latency comparison.

## Procedure

1. Record recurrence, owner, and review requirement in `docs/loen/<topic>/loop.yaml` under `governance:`.
2. Keep scheduled activity advisory unless the repository owner explicitly enables stricter `LOEN_MODE`.
3. Record every run in `attempts.jsonl` with `automation: true`, `run_type`, status, summary, evidence path, review flags, and timestamp.
4. Require human review before any merge, release, destructive operation, protected-scope edit, or first-run completion within `first_runs_require_human_review`.
5. Keep `auto_merge: false` and `auto_fix: false`; automation must not auto-merge unless a later integration layer adds explicit reviewed support.
6. Run the topic verifier and regenerate `audit.html` after each scheduled attempt.

## Output

Report schedule, owner, latest evidence, whether human review is still required, alert reasons, and next run condition.
