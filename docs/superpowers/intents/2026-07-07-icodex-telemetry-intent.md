---
review:
  intent_hash: df3ee3f37250cee6
  last_run: 2026-07-08
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
---
# Intent: icodex telemetry

**Date:** 2026-07-07
**Status:** approved

## Objective

Add opt-in telemetry to icodex so operators can see both operational session metrics in Grafana and LLM tracing in Langfuse. The change is needed because iclaude already has telemetry paths for Grafana and Langfuse, while icodex currently launches Codex without an equivalent observability surface.

## Desired Outcomes

- Grafana shows an icodex session dashboard with launch count, session duration, exit status, wrapper version, Codex version, and project attribution.
- Langfuse receives traces for Codex LLM requests with project and session tags.
- Telemetry remains disabled by default and can be enabled explicitly through `.codex_config`.

## Health Metrics

- Launch behavior without telemetry enabled has no new required runtime services or heavy dependencies.
- No secrets, API keys, prompts, request bodies, or response bodies are written to Grafana metrics, logs, tracked docs, wiki pages, or git history.
- Existing proxy and `NO_PROXY` behavior remains compatible with configured proxy routing and telemetry endpoints.
- Codex passthrough arguments and Codex exit code remain preserved by the wrapper.
- The full Bash test suite remains green.

## Strategic Context

- Interacts with: `icodex.sh` launch orchestration, `.codex_config` parsing and environment mapping, proxy and `NO_PROXY` handling, per-project `CODEX_HOME`, local Grafana/Prometheus/OpenTelemetry collector stack, Langfuse endpoint configuration, tests, repository docs, and the icodex iwiki domain.
- Priority trade-off: trust first, then low overhead, then completeness. Opt-in behavior, secret safety, and reliable Codex launch are more important than capturing every possible telemetry event.

## Constraints

### Steering (behavioral guidance)

- Reuse iclaude telemetry ideas where they fit Codex, but adapt them to the Codex wrapper instead of copying Claude-specific assumptions.
- Keep telemetry optional and configuration-driven.
- Prefer standard OpenTelemetry, Prometheus, and Langfuse contracts over custom protocols.
- Keep the implementation Bash-first and dependency-light.

### Hard (architectural enforcement)

- Telemetry must not run unless it is explicitly enabled.
- Grafana metrics must not include prompts, request bodies, or response bodies.
- Secrets must not be committed to tracked files, generated reports, iwiki pages, dashboard fixtures, or tests.
- Tests must not require network access.
- No telemetry background service may be started by default.
- The wrapper must preserve the Codex process exit code.

## Autonomy Zones

- Full autonomy (reversible, low risk): read iclaude telemetry reference files, inspect icodex docs and source, design Bash modules, tests, and documentation.
- Guarded (log + confidence threshold): choose a minimal telemetry architecture when it is opt-in, preserves launch behavior, and does not start services by default.
- Proposal-first (needs approval): add a proxy or capture layer, add a Docker Compose monitoring stack, add new Python or Node dependencies, or add dashboard assets.
- No autonomy (human only): send real prompts or secrets to external systems, change the Codex authentication flow, or enable telemetry by default.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if Codex CLI does not expose enough telemetry or interception surface to support LLM traces without a risky proxy or capture layer.
- Escalate if Langfuse tracing requires prompt, request-body, response-body, or secret capture beyond safe metadata.
- Done when: the checked intent report is approved, the checked design report is approved, and the implementation plan can start from a clear opt-in telemetry design.
