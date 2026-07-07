---
review:
  intent_hash: c98989f5cc258367
  last_run: 2026-07-08
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
chain:
  intent: null
  spec: null
---
# Intent: icodex PII proxy

**Date:** 2026-07-08
**Status:** approved

## Objective
icodex currently sends Codex CLI traffic directly to OpenAI cloud without a PII or
secret protection layer. Critical personal data and credentials can therefore leave
the local machine. Add an opt-in PII proxy layer for OpenAI API traffic so sensitive
data is masked before it is sent outside the trusted environment.

Langfuse capture is a separate trusted observability use case. It may intentionally
send unmasked prompt logs to the user's own collection server for prompt analysis,
but it is not the default PII-protection path.

OpenAI-compatible provider routing is not a requirement for this feature.

## Desired Outcomes
- When the user launches icodex with PII protection enabled, critical PII and
  secrets in OpenAI API request content are masked before reaching OpenAI.
- When PII protection is requested but the proxy is not installed or cannot start,
  icodex fails securely instead of silently launching without masking.
- Users have clear install and status paths for the PII proxy and can see the
  active masking level.
- Langfuse prompt capture remains a separate trusted mode and does not define the
  default PII-protection behavior.
- Normal icodex launches without PII protection keep their existing behavior.

## Health Metrics
- Standard icodex launch without PII protection must not change.
- Streaming responses must not suffer noticeable latency or buffering regressions.
- Existing `ICODEX_PROXY`, `ICODEX_NO_PROXY`, and CA trust repair behavior must keep
  working.
- Tool calls, file paths, search patterns, and other structural fields must not be
  corrupted by masking.
- Normal proxy logs must not store raw secrets or PII; any mode that stores
  sensitive content, such as trusted Langfuse capture or debug logging, must be
  explicit.

## Strategic Context
- Interacts with: Codex CLI OpenAI API traffic only.
- Existing generic HTTP proxy support remains a transport layer, not the feature
  target.
- iwiki, statusline, router, and Langfuse are outside the initial protection scope
  unless needed for installation or status visibility.
- Priority trade-off: trust over speed and cost.

## Constraints
### Steering (behavioral guidance)
- Prefer precision-first masking. Mask only critical personal information and
  secrets that should not leave the machine.
- Avoid masking information that changes task meaning or degrades result quality.
- Default detection should favor reliable secrets and pattern-based PII such as
  credentials, tokens, passwords, email addresses, phone numbers, payment cards,
  IBANs, IP addresses, and URL credentials.
- Avoid aggressive NER classes such as person, location, organization, and date by
  default because they can distort legitimate task context.

### Hard (architectural enforcement)
- Do not change the normal launch path when PII protection is not enabled.
- If PII protection is enabled and the proxy cannot start, fail secure.
- Do not write raw PII or secrets to normal logs.
- Do not mask system or developer instructions.
- Do not mask structural tool fields such as file paths, command/search pointers,
  or glob patterns when masking would break tool execution.
- Keep OpenAI API traffic as the first supported scope; do not require
  OpenAI-compatible provider routing.

## Autonomy Zones
- Full autonomy (reversible, low risk): adapt the known iclaude PII proxy structure
  to icodex module names, choose focused test filenames, draft docs, and exclude
  Langfuse from the first protection implementation.
- Guarded (log + confidence threshold): choose exact environment variable names,
  CLI flag names, status output wording, and installation layout when they follow
  existing icodex conventions.
- Proposal-first (needs approval): change default masking classes, add Langfuse
  capture behavior, or alter the normal non-PII launch path.
- No autonomy (human only): enable unmasked prompt capture by default, weaken
  fail-secure behavior for requested PII protection, or send sensitive logs to any
  non-user-controlled service.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules
- Halt if: the Codex API traffic path cannot be identified well enough to place the
  proxy without bypass risk.
- Halt if: reliable masking would require broad context-damaging entity classes by
  default.
- Escalate if: OpenAI API request/response shapes differ enough from the iclaude
  Anthropic implementation that a direct adaptation would be unsafe.
- Escalate if: protecting OpenAI traffic requires changing unrelated provider,
  proxy, or launch semantics.
- Done when: a focused verification shows a request containing critical PII or a
  secret reaches a local upstream with those sensitive spans masked, and the
  existing non-PII icodex test suite still passes.
