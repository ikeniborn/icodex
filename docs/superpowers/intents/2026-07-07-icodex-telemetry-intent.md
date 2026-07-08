---
review:
  intent_hash: be601daccfd4f18c
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
- A self-hosted local trusted Langfuse instance receives full-fidelity Codex LLM traces for later analysis, including prompt and response content when capture mode is explicitly enabled, with project and session tags.
- Telemetry remains disabled by default and can be enabled explicitly through `.codex_config`.

## Health Metrics

- Launch behavior without telemetry enabled has no new required runtime services or heavy dependencies.
- No secrets or API keys are written to Grafana metrics, logs, tracked docs, wiki pages, or git history.
- Full prompt and response capture is restricted to an explicitly enabled local trusted Langfuse target and remains out of Grafana metrics.
- Existing proxy and `NO_PROXY` behavior remains compatible with configured proxy routing and telemetry endpoints.
- Codex passthrough arguments and Codex exit code remain preserved by the wrapper.
- The full Bash test suite remains green.

## Strategic Context

- Interacts with: `icodex.sh` launch orchestration, `.codex_config` parsing and environment mapping, proxy and `NO_PROXY` handling, per-project `CODEX_HOME`, local Grafana/Prometheus/OpenTelemetry collector stack, Langfuse endpoint configuration, tests, repository docs, and the icodex iwiki domain.
- Priority trade-off: trust first, then Langfuse completeness for local trusted analysis, then low overhead. Opt-in behavior, secret safety, local-only full capture, and reliable Codex launch are more important than broad external export.

## Constraints

### Steering (behavioral guidance)

- Reuse iclaude telemetry ideas where they fit Codex, but adapt them to the Codex wrapper instead of copying Claude-specific assumptions.
- Keep telemetry optional and configuration-driven.
- Prefer standard OpenTelemetry, Prometheus, and Langfuse contracts over custom protocols.
- Keep the implementation Bash-first and dependency-light.
- Treat full-fidelity Langfuse capture as a local trusted analysis mode, distinct from metadata-only Grafana metrics.

### Hard (architectural enforcement)

- Telemetry must not run unless it is explicitly enabled.
- Grafana metrics must not include prompts, request bodies, or response bodies.
- Full prompt and response capture must target only a configured local trusted Langfuse instance.
- Secrets must not be committed to tracked files, generated reports, iwiki pages, dashboard fixtures, or tests.
- Tests must not require network access.
- No telemetry background service may be started by default.
- The wrapper must preserve the Codex process exit code.

## Autonomy Zones

- Full autonomy (reversible, low risk): read iclaude telemetry reference files, inspect icodex docs and source, design Bash modules, tests, and documentation.
- Guarded (log + confidence threshold): choose a minimal telemetry architecture when it is opt-in, preserves launch behavior, and does not start services by default.
- Proposal-first (needs approval): add a proxy or capture layer, add a Docker Compose monitoring stack, add new Python or Node dependencies, add dashboard assets, or choose the full-fidelity capture mechanism.
- No autonomy (human only): send real prompts, responses, or secrets to external systems, change the Codex authentication flow, or enable telemetry by default.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if Codex CLI does not expose enough telemetry or interception surface to support local trusted full-fidelity LLM traces without breaking launch behavior or exit-code preservation.
- Escalate if Langfuse tracing would send prompt, request-body, response-body, or secret capture to a non-local or untrusted endpoint.
- Done when: the checked intent report is approved, the checked design report is approved, and the implementation plan can start from a clear opt-in telemetry design.
