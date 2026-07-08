---
review:
  spec_hash: b811b7bceabff63b
  last_run: 2026-07-08
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-07-icodex-telemetry-intent.md
---
# Design: icodex hybrid telemetry

**Date:** 2026-07-08
**Status:** approved
**Topic:** icodex-telemetry

## Objective

Add opt-in hybrid telemetry to icodex with two separate observability paths:

- metadata-only operational telemetry for Grafana through Codex OpenTelemetry and a local collector;
- full-fidelity LLM tracing for a self-hosted local trusted Langfuse instance through a local capture layer.

The design keeps telemetry disabled by default, keeps Grafana free of prompt and response bodies, and treats full Langfuse capture as a local trusted analysis mode.

## Acceptance (from intent)

### Desired Outcomes

- Grafana shows an icodex session dashboard with launch count, session duration, exit status, wrapper version, Codex version, and project attribution.
- A self-hosted local trusted Langfuse instance receives full-fidelity Codex LLM traces for later analysis, including prompt and response content when capture mode is explicitly enabled, with project and session tags.
- Telemetry remains disabled by default and can be enabled explicitly through `.codex_config`.

### Health Metrics

- Launch behavior without telemetry enabled has no new required runtime services or heavy dependencies.
- No secrets or API keys are written to Grafana metrics, logs, tracked docs, wiki pages, or git history.
- Full prompt and response capture is restricted to an explicitly enabled local trusted Langfuse target and remains out of Grafana metrics.
- Existing proxy and `NO_PROXY` behavior remains compatible with configured proxy routing and telemetry endpoints.
- Codex passthrough arguments and Codex exit code remain preserved by the wrapper.
- The full Bash test suite remains green.

### Done When

- The checked intent report is approved, the checked design report is approved, and the implementation plan can start from a clear opt-in telemetry design.

## External Facts

- Codex exposes OpenTelemetry configuration keys for log, metric, and trace exporters, including endpoint and static header settings. It also exposes `otel.log_user_prompt`, which is an explicit opt-in for exporting raw user prompts with OpenTelemetry logs.
- Codex project-local config cannot override telemetry routing keys; telemetry config must be written into the per-project Codex home config or passed through a non-project profile/config layer.
- Codex supports custom model provider definitions with `model_providers.<id>.base_url`, auth settings, and stream retry settings. Built-in provider IDs are reserved and cannot be overridden.
- Langfuse can receive OTLP traces at `/api/public/otel`; local deployments use URLs such as `http://localhost:3000/api/public/otel`. Langfuse uses Basic Auth from the public and secret keys for OTLP ingestion and recommends propagating session/tags/metadata to all spans for reliable filtering.

These facts constrain the design:

- The Grafana path should use Codex OTel without `otel.log_user_prompt`.
- The Langfuse full-capture path cannot rely on metadata-only OTel alone; it needs either a local capture provider/proxy or an equivalent local instrumentation layer.
- Capture implementation must start with a feasibility probe against the installed Codex version and current auth mode before treating full capture as complete.

## Non-Goals

- Do not enable telemetry by default.
- Do not send prompt or response bodies to Grafana, Prometheus, or generic OTel metrics.
- Do not send prompt, response, or secret data to a non-local or untrusted Langfuse endpoint.
- Do not add more mode-switching variables beyond `ICODEX_TELEMETRY`.
- Do not require Docker, Prometheus, Grafana, OTel Collector, or Langfuse to be running for normal `off` launches.
- Do not change Codex authentication behavior unless the full-capture feasibility probe proves the selected capture provider can preserve it.
- Do not make network-dependent tests mandatory.

## Configuration Contract

The public configuration surface for v1 is deliberately small:

```text
ICODEX_TELEMETRY=off|otel|langfuse|both
ICODEX_OTEL_ENDPOINT=http://127.0.0.1:4318
ICODEX_OTEL_CREDENTIALS=user:password
ICODEX_LANGFUSE_BASE_URL=http://127.0.0.1:3000
ICODEX_LANGFUSE_PUBLIC_KEY=pk-lf-...
ICODEX_LANGFUSE_SECRET_KEY=sk-lf-...
```

Rules:

- `ICODEX_TELEMETRY` is the only enable/mode switch.
- Default mode is `off`.
- `off` means no telemetry setup, no capture process, and the launch path stays as close as possible to the current direct `exec`.
- `otel` enables only the Grafana/OTel path.
- `langfuse` enables only the full-fidelity Langfuse capture path.
- `both` enables both paths.
- OTel credentials are optional. When set, icodex converts `ICODEX_OTEL_CREDENTIALS` to the static Authorization header required by Codex OTel config.
- `ICODEX_OTEL_ENDPOINT` defaults to `http://127.0.0.1:4318`.
- Langfuse URL and keys are required only for `langfuse` and `both`.
- Project attribution is derived automatically from the target project root: git toplevel basename, falling back to `basename "$ICODEX_PROJECT_ROOT"` or `basename "$PWD"`. There is no `ICODEX_LANGFUSE_PROJECT` variable.

## Architecture

Hybrid telemetry has three layers.

### 1. Mode And Session Orchestration

`lib/telemetry/telemetry.sh` owns mode parsing and launch-level session context.

Responsibilities:

- validate `ICODEX_TELEMETRY`;
- derive `ICODEX_TELEMETRY_PROJECT`;
- create `ICODEX_TELEMETRY_SESSION_ID`;
- dispatch `otel`, `langfuse`, or `both` setup;
- decide whether `launch_codex` can remain a direct `exec` or must run Codex as a child to preserve exit-code accounting and cleanup;
- expose a cleanup function for EXIT, INT, and TERM.

The existing `off` path should remain direct:

```text
icodex.sh -> launch_codex exec "$ICODEX_BIN" "$@"
```

Telemetry-enabled paths may wrap:

```text
icodex.sh -> telemetry_setup -> run codex child -> capture exit code -> cleanup -> exit same code
```

### 2. Metadata-Only OTel Path For Grafana

`lib/telemetry/otel.sh` owns Codex OpenTelemetry config wiring.

Responsibilities:

- write or resync a delimited telemetry region in `$ICODEX_HOME_DIR/config.toml`;
- set Codex OTel exporters to the local OTel endpoint for logs, metrics, and traces where supported;
- keep `otel.log_user_prompt = false`;
- include resource metadata such as service name, wrapper version, Codex version, project, session id, and telemetry mode;
- generate an Authorization header from `ICODEX_OTEL_CREDENTIALS` when present;
- add the OTel endpoint host to `NO_PROXY` when needed.

The OTel path is metadata-only by contract. It may include session, API, tool, model, timing, token, status, and version metadata if Codex emits it, but it must not enable raw prompt export.

Data flow:

```text
Codex OTel -> local OTel Collector -> Prometheus/Grafana
```

### 3. Full-Fidelity Langfuse Capture Path

`lib/telemetry/langfuse.sh` owns local trusted capture setup.

Responsibilities:

- validate that `ICODEX_LANGFUSE_BASE_URL` is local/trusted;
- require public and secret keys for `langfuse|both`;
- start the local capture layer before Codex starts;
- configure Codex traffic to reach the local capture layer;
- ensure captured traces carry project and session tags;
- send prompt, response, model, usage, latency, and status data to Langfuse;
- stop the capture layer after Codex exits.

The preferred capture mechanism is a local reverse proxy/model-provider shim:

```text
Codex -> local capture provider/proxy -> OpenAI provider
                              \-> local trusted Langfuse
```

The implementation plan must include a feasibility probe before building the full layer:

1. Start a minimal local capture server with fake upstream behavior.
2. Configure Codex to use a custom provider pointing at that local server.
3. Verify that Codex sends a representative request to the local server without breaking passthrough args, auth expectations, streaming/SSE behavior, or exit-code preservation.
4. If the installed Codex version or current auth mode cannot support this safely, stop and report the blocker instead of shipping a partial capture implementation.

The capture layer is allowed to handle prompt and response content only because the target is an explicitly configured local trusted Langfuse endpoint. It must not send full content to Grafana or generic OTel metrics.

## Data Flow By Mode

| Mode | Setup | Runtime Flow | Required Config |
|---|---|---|---|
| `off` | none | `icodex -> codex` | none |
| `otel` | OTel config region | `codex -> OTel Collector -> Prometheus/Grafana` | optional `ICODEX_OTEL_ENDPOINT`, optional `ICODEX_OTEL_CREDENTIALS` |
| `langfuse` | local capture layer | `codex -> capture -> OpenAI + local Langfuse` | `ICODEX_LANGFUSE_BASE_URL`, `ICODEX_LANGFUSE_PUBLIC_KEY`, `ICODEX_LANGFUSE_SECRET_KEY` |
| `both` | OTel config + local capture | both flows in parallel | OTel config plus required Langfuse config |

## Error Handling

- Invalid `ICODEX_TELEMETRY` value fails before launch and lists `off|otel|langfuse|both`.
- Bad `ICODEX_OTEL_ENDPOINT` fails before launch in `otel|both`.
- Missing `ICODEX_OTEL_ENDPOINT` in `otel|both` uses `http://127.0.0.1:4318`.
- Missing Langfuse URL or keys fails before launch in `langfuse|both`.
- Non-local or untrusted Langfuse URL fails before launch in `langfuse|both`.
- Missing capture dependency or binary fails only in `langfuse|both`; `off` and `otel` are unaffected.
- Capture process startup failure fails before Codex starts.
- Capture process death during a session preserves the Codex exit code, emits a warning, and marks the session metric as `capture_failed`.
- Cleanup runs on normal exit and on INT/TERM.
- If the full-capture feasibility probe fails, implementation stops at a human checkpoint.

## Local/Trusted URL Policy

Langfuse full capture is allowed only for local trusted targets.

Accepted by default:

- `http://localhost:<port>`
- `http://127.0.0.1:<port>`
- `http://[::1]:<port>`
- private RFC1918 host/IP ranges when explicitly allowed by a small internal predicate

Rejected by default:

- public HTTPS hosts;
- missing scheme;
- opaque shell fragments;
- URLs containing credentials in the URL string.

The design keeps allowlisting inside code rather than adding another user-facing mode variable. If a future non-local trusted deployment is needed, that is a separate proposal-first expansion.

## Security Boundaries

- `.codex_config` remains parsed, not sourced.
- Only `ICODEX_*` keys are honored.
- Raw `LANGFUSE_*` and `OTEL_*` keys in `.codex_config` are not required for v1.
- Generated docs and tests use fake keys only.
- No secret values are written to `config.toml`; generated config may contain headers derived at runtime only in git-ignored per-project homes, not tracked templates.
- Grafana metrics never receive prompts, request bodies, or response bodies.
- Langfuse receives full content only in `langfuse|both` and only after local trusted URL validation passes.
- `NO_PROXY` is patched for local telemetry endpoints to avoid routing local observability through an external proxy.

## Component Impact

### `icodex.sh`

- Source telemetry modules.
- Call config/env mapping after `load_config`.
- Call telemetry setup after per-home setup and before `launch_codex`.
- Use wrapped launch only when telemetry requires cleanup or exit-code accounting.

### `lib/config/env.sh`

- Allow and export telemetry config keys already covered by the `ICODEX_*` allowlist.
- Add mapping helpers only for runtime env names required by Codex or capture processes.
- Do not source `.codex_config`.

### `lib/launcher/launch.sh`

- Keep direct `exec` for `off`.
- Add a child-process launch helper for telemetry-enabled modes.
- Preserve passthrough arguments and final exit code.

### `lib/telemetry/telemetry.sh`

- New orchestration module.
- Mode parsing, project/session derivation, config validation, setup dispatch, cleanup dispatch.

### `lib/telemetry/otel.sh`

- New OTel module.
- Config region writer for Codex OTel keys.
- Basic auth header generation from `ICODEX_OTEL_CREDENTIALS`.
- `NO_PROXY` patching.

### `lib/telemetry/langfuse.sh`

- New Langfuse module.
- Local trusted URL validation.
- Capture layer lifecycle.
- Langfuse auth and trace metadata setup.

### `.codex_config.example`

- Document only the six public telemetry variables.
- Explain `off|otel|langfuse|both`.
- Warn that `langfuse|both` captures prompts and responses to local trusted Langfuse.

### Tests

- Add focused Bash tests under `tests/test_telemetry_*.sh`.
- Use fake capture binaries/servers and local temp directories.
- Avoid network access.

## Testing Plan

### Config Tests

- Default `ICODEX_TELEMETRY` is `off`.
- Valid modes pass: `off`, `otel`, `langfuse`, `both`.
- Invalid mode fails with allowed values.
- Endpoint/key variables parse from `.codex_config`.

### OTel Tests

- `otel` writes expected Codex OTel config into a temp home.
- `ICODEX_OTEL_CREDENTIALS` becomes a Basic Auth header in generated runtime config.
- OTel endpoint host is added to `NO_PROXY`.
- `otel.log_user_prompt` remains false.

### Langfuse Tests

- Missing URL/key fails only for `langfuse|both`.
- Non-local URL is rejected.
- Local URL is accepted.
- Project tag is derived from git/project root.
- Fake capture layer receives prompt/response fixture in unit or local E2E tests without external network.
- Capture layer lifecycle start/stop is idempotent.

### Launch Tests

- `off` still uses the direct exec-like path.
- Wrapped path preserves passthrough args.
- Wrapped path preserves Codex exit code.
- Cleanup trap stops capture on normal exit and signal path.

### Documentation Tests

- `.codex_config.example` documents the mode and endpoint/key variables.
- Repository docs and iwiki are updated after implementation.

### Full Suite

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

## Success Criteria

- `ICODEX_TELEMETRY=off` does not start telemetry services and preserves existing launch behavior.
- `ICODEX_TELEMETRY=otel` produces Codex OTel metadata suitable for Grafana without prompt/response bodies.
- `ICODEX_TELEMETRY=langfuse` sends full-fidelity LLM traces to a local trusted Langfuse target.
- `ICODEX_TELEMETRY=both` runs both channels without sending full content to Grafana.
- Langfuse capture refuses non-local/untrusted targets.
- Codex passthrough args and exit codes are preserved in every mode.
- Tests pass without network access.

## Open Risks For The Implementation Plan

- Codex custom provider configuration may not preserve the user's current ChatGPT-auth flow through a local capture proxy. This must be probed before full capture work proceeds.
- Streaming/SSE capture can be fragile; the first implementation should test a representative streaming fixture before claiming full-fidelity support.
- Langfuse full traces may contain sensitive project content by design. The feature is acceptable only because the target is local trusted and opt-in.
- OTel event fields emitted by Codex are version-dependent. Grafana dashboards should be designed around stable wrapper-added labels plus whatever Codex emits, not brittle assumptions about every internal event.
