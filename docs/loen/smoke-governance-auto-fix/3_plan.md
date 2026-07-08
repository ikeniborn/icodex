# Plan

Topic: `smoke-governance-auto-fix`

## Approved Runner Contract

- Mode: `governance`
- Subtype: `auto-fix`
- Verifier: `grep -q FIXED docs/loen/smoke-governance-auto-fix/scratch/needs-fix.txt`
- Human approval: smoke approval by Codex run on 2026-07-08

## Steps

1. Prepare topic-scoped smoke input and evidence.
2. Run the verifier command exactly as recorded in `loop.yaml`.
3. Reflect to `7_result.md` on pass, or `handoff.md` on policy failure.

## Checks

```bash
grep -q FIXED docs/loen/smoke-governance-auto-fix/scratch/needs-fix.txt
```
