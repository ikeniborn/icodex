---
topic: secret-access-hook-diagnostics
review:
  intent_hash: 998266a20ac9e618
  last_run: 2026-11-04
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
workflow:
  route: chain
  continuation: full
---
# Intent: secret-access-hook-diagnostics

**Date:** 2026-11-04
**Status:** approved

## Objective

Allow diagnostic commands without treating executable heredoc syntax itself as evidence of secret access.
Preserve protection against secret access in Python and Bash heredocs.
The current blanket rejection interrupted proxy diagnostics with `ambiguous_heredoc`.

## Desired Outcomes

- Safe Python and Bash diagnostic heredocs pass the hook when their relevant accesses can be determined as safe.
- Commands that access known protected secret paths remain blocked, including accesses inside heredoc bodies.
- Commands with indeterminate relevant accesses remain blocked instead of receiving an unsafe exemption.
- Refusals distinguish protected secret access from indeterminate analysis and explain the next action without revealing secret values.

## Health Metrics

- All existing protected-path denial cases remain denied unless an approved contract change explicitly supersedes a syntax-only denial.
- Safe diagnostic examples for both Python and Bash receive exit 0; protected-path and indeterminate-access examples receive exit 2.
- Hook diagnostics expose no secret values or raw command bodies in the focused test fixtures.
- Existing literal-data writes and the independent secret-content hook retain their documented protection.

## Strategic Context

- Interacts with: `.codex-isolated/hooks/block-secrets.py`, the independent `redact-secrets.py` hook, hook registration, diagnostic tool requests, hook tests, repository documentation, and iwiki specifications.
- Priority trade-off: Preserve trust in secret-access protection while reducing false refusals during diagnostics.
- Existing documentation explicitly denies interpreter heredocs. This task deliberately revises that observable contract for safely analyzable Python and Bash diagnostics.

## Constraints

### Steering (behavioral guidance)

- Keep the change scoped to the observed heredoc diagnostic failures and their protection requirements.
- Use clear refusal categories that explain whether access is protected or analysis is indeterminate.
- Prefer the smallest supported diagnostic forms that satisfy the approved outcomes.

### Hard (architectural enforcement)

- Support safe diagnostic heredocs for both Python and Bash.
- Block indeterminate relevant accesses, including dynamically constructed paths that cannot be established as safe.
- Preserve the configured protected-path policy; do not remove protected paths to make diagnostics pass.
- Do not execute submitted commands or read secret contents while classifying a tool request.
- Do not disable hooks or bypass independent secret-content scanning.
- Keep the existing permission and refusal exit codes, 0 and 2.
- Treat this hook as a request guard under its existing documented trust assumptions, not a complete execution sandbox.

## Autonomy Zones

- Full autonomy (reversible, low risk): Inspect source and documentation; prepare local fixtures and draft artifacts.
- Guarded (verification required): Implement the approved behavior, update its documentation, and run focused protection regressions plus the final full suite.
- Proposal-first (needs approval): Change the protected-path policy, expand language scope beyond Python and Bash, or revise the agreed indeterminate-access rule.
- No autonomy (human only): Approve chain artifacts, authorize a changed security boundary, or authorize destructive external actions.

## Stop Rules

- Halt if: A protected secret access becomes allowed or classification would require executing submitted code.
- Escalate if: A supported diagnostic form cannot satisfy both safe-command acceptance and indeterminate-access refusal under the current trust assumptions.
- Done when: Real hook invocations allow the agreed safe Python and Bash diagnostic fixtures and deny protected-path and indeterminate-access fixtures with exit 2.
- Done when: Focused security regressions and the required final full suite pass, and repository documentation and iwiki describe the verified behavior.
