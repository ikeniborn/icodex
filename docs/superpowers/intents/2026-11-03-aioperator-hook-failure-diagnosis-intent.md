---
topic: aioperator-hook-failure-diagnosis
status: approved
workflow:
  route: chain
  continuation: full
review:
  intent_hash: df5953e2a3dcc825
  last_run: '2026-11-03'
  phases:
    structure: {status: passed}
    completeness: {status: passed}
    clarity: {status: passed}
    consistency: {status: passed}
    alignment: {status: passed}
  findings:
    - id: F-001
      phase: completeness
      severity: CRITICAL
      section: Stop Rules
      section_hash: 8a79bf91a34840c9
      fragment: 'Done when:'
      text: The initial draft omitted the required Done when colon marker.
      fix: Use the canonical marker for both observable completion criteria.
      verdict: fixed
      verdict_at: '2026-11-03'
---
# Intent: aioperator-hook-failure-diagnosis

**Date:** 2026-11-03
**Status:** approved

## Objective

Correct the hook refusals confirmed in aioperator session history. Make each refusal attributable to its hook and actual cause. Preserve protection of secret-bearing paths and validation of the applicable chain artifact.

The diagnosis found 16 sensitive-path refusals and five IDD refusals. These counts describe observed refusals, not 21 defects. The latest sensitive-path refusal misclassified literal heredoc prose as a path. Four IDD refusals selected a different task's plan from the root checkout.

## Desired Outcomes

- O1: A literal quoted heredoc appended to an ordinary note passes when its harmless prose contains a slash-prefixed token with the substring `secret`.
- O2: Direct access to protected paths remains blocked. Heredoc handling does not exempt executable expansions or interpreter input from protection.
- O3: When the event working directory or an explicit command working directory identifies the task checkout, IDD evaluates that checkout's applicable artifact. A valid task plan passes despite an unrelated stale plan in another checkout. An applicable stale plan remains blocked.
- O4: A refusal identifies the hook and distinguishes a protected path, ambiguous command analysis, invalid working directory, missing required hash field, and mismatching hash. Diagnostics provide a safe locator or redacted context without reproducing secret values or entire command bodies.
- O5: If command analysis cannot distinguish literal data from executable input confidently, the hook retains the block and explains that uncertainty.

## Health Metrics

- All protected-path and secret-content cases in the existing hook tests retain their required denial results.
- All existing chain validation cases retain their required allow or deny results, except explicitly corrected wrong-checkout selection and diagnostic wording.
- Both hooks retain their configured invocation interface and exit-code convention: 0 permits the action and 2 blocks it.
- Diagnostic fixtures containing synthetic secret markers expose none of those markers in stdout or stderr.
- Focused regressions and the complete repository Bash suite pass for the final implementation state. Record pre-existing failures separately; do not report them as a passing suite.

## Strategic Context

- Interacts with: per-project Codex homes, shared hook sources, shell tool payloads, task worktrees, the IDD ownership ledger, validation frontmatter, and hook tests.
- Priority trade-off: trust first; remove demonstrated false refusals without weakening secret protection or chain validation.
- Existing evidence: `block-secrets.py` applies `shlex.split` to the whole command, including heredoc data. `chain-gate.py` has an existing uncommitted patch supporting `tool_input.workdir`, but a fixture with only event `cwd` still selects a foreign plan.
- Hash compatibility: the gate requires `review.plan_hash`; an observed external plan uses `review.body_sha256`. Missing-field diagnostics must distinguish this incompatibility from an edited body.
- Remaining design decision: define the bounded shell forms that can be classified as literal data safely, including behavior for executable heredoc consumers and expansions.

## Constraints

### Steering

- Limit the change to demonstrated hook failures, their diagnostics, relevant tests, and documentation.
- Prefer bounded parsing rules over a general shell interpreter.
- Use synthetic fixtures to reproduce refusal paths without executing submitted commands.
- Preserve the existing workdir patch as input to the reviewed fix. Record any necessary revision to it.

### Hard

- Do not disable the secret hooks, remove protected-path patterns, or exempt every heredoc from checking.
- Do not execute submitted commands or read real secret files during hook analysis or tests.
- Do not silently accept `body_sha256` as `plan_hash`, change hash semantics, or rewrite aioperator chain artifacts.
- Do not automatically approve an artifact or weaken stale-hash validation to make a transition pass.
- Keep uncertain command analysis blocked with an actionable, secret-safe explanation.
- Keep implementation in the icodex repository. Do not change aioperator production services or deployment state.
- Add no runtime dependency without a separate approved scope change.

## Autonomy Zones

- Full autonomy: inspect relevant code and redacted history; prepare chain artifacts; create synthetic fixtures; run authorized checks.
- Guarded: after the required artifact approvals, change scoped hooks, tests, and documentation; record evidence and preserve existing work.
- Proposal-first: broaden supported shell semantics, change hash compatibility, introduce dependencies, or change the accepted security boundary.
- No autonomy: weaken protection to force a pass, access real secret contents for reproduction, mutate unrelated task artifacts, or alter production state.

## Stop Rules

- Halt if a proposed exemption can permit protected-path access through executable heredoc input or expansions.
- Halt if the existing workdir patch changes concurrently or cannot be reconciled without discarding another actor's work.
- Escalate if safe command classification requires a broader parser, new dependency, or changed security contract.
- Done when: O1 through O5 have recorded allow/deny and diagnostic evidence, all required regressions pass, and documentation matches the resulting behavior.
- Done when: result reconciliation passes, the task ledger contains final evidence, and task-page lint has no new finding.
