---
review:
  spec_hash: c4ad1c32cd57e7b9
  last_run: 2026-07-08
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-08-icodex-pii-proxy-intent.md
  spec: null
---
# icodex PII Proxy Design

**Date:** 2026-07-08
**Status:** approved (brainstorming)
**Intent:** `docs/superpowers/intents/2026-07-08-icodex-pii-proxy-intent.md`

## Acceptance (from intent)

Desired Outcomes:

- When the user launches icodex with PII protection enabled, critical PII and
  secrets in OpenAI API request content are masked before reaching OpenAI.
- When PII protection is requested but the proxy is not installed or cannot start,
  icodex fails securely instead of silently launching without masking.
- Users have clear install and status paths for the PII proxy and can see the
  active masking level.
- Langfuse prompt capture remains a separate trusted mode and does not define the
  default PII-protection behavior.
- Normal icodex launches without PII protection keep their existing behavior.

Done when:

- A focused verification shows a request containing critical PII or a secret
  reaches a local upstream with those sensitive spans masked, and the existing
  non-PII icodex test suite still passes.

## Goal

Add an opt-in local PII proxy for Codex OpenAI API traffic. When enabled, icodex
starts a localhost proxy, routes Codex to it for the current run with Codex's
built-in `openai_base_url` override, masks critical PII and secrets in request
content, forwards the sanitized request to OpenAI, and relays responses unchanged.

The selected routing mechanism is:

```text
codex -c openai_base_url='"http://127.0.0.1:<port>/v1"'
```

The proxy forwards to `https://api.openai.com/v1` by default. This design does not
add a user-facing OpenAI-compatible provider. It uses the built-in OpenAI provider
and a one-run base URL override.

## Non-Goals

- No default-on PII proxy behavior.
- No persistent mutation of `config.toml` for routing.
- No HTTP CONNECT or TLS MITM proxy implementation.
- No Langfuse capture in the first protection implementation.
- No broad NER masking of person, location, organization, or date entities by
  default.
- No router or non-OpenAI provider support in this first scope.

## User-Facing Configuration

Enablement:

```bash
./icodex.sh --pii-proxy
```

or persistent `.codex_config`:

```bash
ICODEX_USE_PII_PROXY=true
```

PII settings in `.codex_config`:

```bash
# rules = regex + validators; nlp = Presidio/spaCy-capable mode
ICODEX_PII_ENGINE=rules

# Masking level: off | secrets | standard
ICODEX_PII_MASKING_LEVEL=standard

# Replacement token. Empty value means deletion mode.
ICODEX_PII_MASK_TOKEN=REDACTED

# Log level: info | debug
ICODEX_PII_LOG_LEVEL=info

# Port selection. 0 means dynamic.
ICODEX_PII_PROXY_PORT=0
ICODEX_PII_PROXY_PORT_MIN=20000
ICODEX_PII_PROXY_PORT_MAX=40000

# Upstream OpenAI API base.
ICODEX_PII_UPSTREAM_URL=https://api.openai.com/v1

# Upstream timeouts, seconds.
ICODEX_PII_CONNECT_TIMEOUT=10
ICODEX_PII_READ_TIMEOUT=300

# Preferred NLP models when ICODEX_PII_ENGINE=nlp.
ICODEX_PII_SPACY_EN_MODEL=en_core_web_lg
ICODEX_PII_SPACY_RU_MODEL=ru_core_news_lg
```

CLI flags have priority over `.codex_config`. The config file remains parsed, not
sourced. Runtime env for the Python proxy is derived from `ICODEX_PII_*` values and
passed to the child process.

## Commands

`--install-pii-proxy` installs the PII proxy runtime.

- `ICODEX_PII_ENGINE=rules`: install the Python venv, `requests`, and the server
  script. No NLP models are downloaded.
- `ICODEX_PII_ENGINE=nlp`: install Presidio, spaCy, and the English and Russian
  spaCy models. Prefer large models from config; fall back to small models with a
  warning if large downloads fail.

`--check-pii-proxy` prints:

- Python and venv status.
- Server script path.
- Installed engine mode.
- EN/RU model status when NLP is installed.
- Running proxy PID/port if active.
- Masking level and log level.
- Last startup error when available.

`--update` keeps its existing Codex update behavior and also updates PII NLP models
when NLP mode is installed or configured. Rules mode has no large model update step.

## Architecture

New modules:

- `lib/pii-proxy/server.py`: local OpenAI-aware HTTP proxy.
- `lib/pii-proxy/install.sh`: venv/dependency/model installer.
- `lib/pii-proxy/detect.sh`: installation readiness checks.
- `lib/pii-proxy/status.sh`: human-readable status output.

Changed modules:

- `lib/core/init.sh`: derives PII runtime paths and default settings.
- `lib/config/env.sh`: allows `ICODEX_PII_*` keys and maps them to proxy runtime env.
- `lib/command/args.sh`: parses PII commands and flags.
- `lib/launcher/launch.sh`: starts/stops the proxy and appends the one-run
  `openai_base_url` override when PII is active.
- `icodex.sh`: sources PII modules and dispatches install/status commands.
- `.codex_config.example`: documents enablement and settings.

The proxy binds only to `127.0.0.1`. Port `0` means dynamic selection from the
configured range. PID, port, and logs live under the ignored isolated runtime area.

## Launch Flow

1. Load `.codex_config`, apply existing API key, iwiki, mode, home, plugin, proxy,
   and binary setup as today.
2. Resolve PII enablement from config and `--pii-proxy`.
3. If PII is not enabled, launch Codex exactly as today.
4. If PII is enabled, validate PII config before launching Codex.
5. Check that the PII proxy is installed. If not installed, print the install command
   and exit non-zero.
6. Start the local proxy and poll `/api/health` until ready.
7. Append the Codex one-run override:

   ```bash
   -c openai_base_url='"http://127.0.0.1:<port>/v1"'
   ```

8. Run Codex as a child process, not `exec`, so the EXIT trap can stop the proxy.
9. On exit, stop the proxy, remove PID/port files, and delete normal session logs
   unless debug mode explicitly preserves them.

## Data Flow

```text
Codex built-in OpenAI provider
  -> http://127.0.0.1:<port>/v1/*
  -> PII proxy request masker
  -> https://api.openai.com/v1/*
  -> streaming/non-streaming response relay
  -> Codex UI
```

Request bodies are masked before upstream forwarding. Response bodies are relayed
unchanged because they came from OpenAI and masking them would alter the user
experience.

## Masking Policy

The default engine is `rules`. It means deterministic regex plus validators and
context rules, not user-provided pattern files.

Masked in `rules` mode:

- API keys and vendor tokens, including OpenAI/Anthropic-like keys, GitHub tokens,
  HuggingFace tokens, Groq keys, Google AI Studio keys, and similar high-confidence
  formats.
- AWS access key IDs and secret access keys.
- JWTs.
- PEM/private key blocks.
- Password, token, secret, and API key assignments in env/config-like text.
- Credentials embedded in URLs.
- Credit card numbers with validation where possible.
- Email addresses.
- Conservative phone-number matches.
- IBANs with validation where possible.
- IP addresses.

Not masked by default:

- Person, location, organization, and date entities.
- System and developer instructions.
- Structural tool fields such as file paths, command pointers, grep patterns, globs,
  tool IDs, and other routing identifiers.
- Assistant prose/output.
- Plain URLs without embedded credentials.

`nlp` mode installs Presidio/spaCy EN/RU support but still follows a precision-first
entity allowlist. It does not enable broad `PERSON`, `LOCATION`, `ORGANIZATION`, or
`DATE_TIME` masking by default.

## OpenAI Request Traversal

The proxy supports the OpenAI paths Codex uses under `/v1/*`.

Traversal rules:

- Responses API: mask user-controlled `input` content. Treat `instructions` as
  system/developer guidance and do not mask it by default.
- Chat Completions: mask `messages[].content` for user content and tool results.
  Preserve system/developer content by default.
- Tool/function arguments: mask values that contain user-authored content, while
  preserving structural keys and route identifiers.
- Unknown JSON shapes: traverse conservatively using a skip-list for structural
  paths instead of masking every string blindly.

Malformed JSON is forwarded only when masking level is `off`; otherwise the request
fails closed because safe masking cannot be proven.

## Error Handling

- Invalid PII config exits before Codex launch.
- Unsupported upstream URLs are rejected. Allowed upstreams are `https://...` and
  loopback `http://...` for local tests.
- Requested PII with missing install exits before Codex launch.
- Startup health-check timeout exits before Codex launch.
- Masking failure returns a proxy error instead of forwarding raw sensitive data.
- Upstream connection errors return clean `502` JSON before response headers are
  sent.
- Mid-stream upstream errors end the stream without emitting a second status line.
- Normal logs record counts and operational events only. Debug mode may include
  sensitive metadata and must be explicit.

## Installation And Update

The installer creates a Python venv under the ignored isolated runtime area and
symlinks or copies the server script into that runtime.

Rules engine install:

- Requires Python 3.8+.
- Installs `requests`.
- Writes an engine marker such as `pii_proxy_engine=rules`.

NLP engine install:

- Requires Python 3.8+.
- Installs Presidio, Presidio anonymizer, and spaCy.
- Downloads or updates configured English and Russian models.
- Uses large models by default and falls back to small models with a warning.
- Writes model marker files so status and runtime can load exact installed models.

`--update` reuses current Codex update behavior and, when NLP mode is installed or
configured, runs the model update flow for both EN and RU models.

## Testing

Bash tests:

- `tests/test_args.sh`: PII flags and commands.
- `tests/test_env.sh`: `ICODEX_PII_*` parsing, validation, and env mapping.
- `tests/test_pii_proxy_launch.sh`: launch helper appends `openai_base_url` only when
  PII is active, and no-PII launch remains unchanged.
- `tests/test_pii_proxy_install.sh`: rules vs NLP install decisions, EN/RU model update
  branches, missing Python handling.
- `tests/test_pii_proxy_status.sh`: status output for missing, rules, NLP, and running
  proxy states.

Python tests:

- `tests/test_pii_proxy_masking.py`: rules engine masking and non-masking cases.
- `tests/test_pii_proxy_openai_shapes.py`: Responses and Chat Completions traversal.
- `tests/test_pii_proxy_server.py`: health/meta, upstream forwarding, streaming relay,
  error handling, and timeout behavior.

Integration test:

- Start a fake local upstream.
- Start the PII proxy with upstream set to the fake server.
- Send a request containing an email and a token.
- Assert the fake upstream receives masked spans.
- Assert the response stream reaches the client unchanged.

Full validation remains:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

## Documentation

Update `.codex_config.example` for enablement and settings. After implementation,
update the iwiki `icodex` domain through MCP tools with the new PII proxy behavior,
configuration, install/status commands, masking policy, and fail-secure guarantees.

## Risks And Mitigations

| Risk | Mitigation |
| --- | --- |
| Codex does not honor `openai_base_url` in the required path | Add an early integration test; stop rather than silently using unprotected traffic |
| Over-masking harms answer quality | Default to `rules`, skip broad NER entities, and preserve instructions/structural fields |
| Proxy startup failure bypasses protection | Fail secure before Codex launch |
| Streaming response buffering regresses UX | Relay SSE chunks as they arrive; test no double-status behavior |
| Logs leak sensitive content | Info logs contain counts only; debug is explicit and warned |
| NLP install is heavy or flaky | Make `rules` default; NLP mode optional with model fallback and clear status |
