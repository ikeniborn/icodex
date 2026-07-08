# Plan

Topic: `smoke-delivery-pass`

## Approved Runner Contract

- Mode: `delivery`
- Subtype: `null`
- Verifier: `test -s docs/loen/smoke-delivery-pass/evidence/delivery-output.txt`
- Human approval: smoke approval by Codex run on 2026-07-08

## Steps

1. Prepare topic-scoped smoke input and evidence.
2. Run the verifier command exactly as recorded in `loop.yaml`.
3. Reflect to `7_result.md` on pass, or `handoff.md` on policy failure.

## Checks

```bash
test -s docs/loen/smoke-delivery-pass/evidence/delivery-output.txt
```
