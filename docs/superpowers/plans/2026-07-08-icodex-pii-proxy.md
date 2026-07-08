---
review:
  plan_hash: d9fcbdf0637553ab
  last_run: 2026-07-08
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-08-icodex-pii-proxy-intent.md
  spec: docs/superpowers/specs/2026-07-08-icodex-pii-proxy-design.md
---
# icodex PII Proxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an opt-in local PII proxy for Codex OpenAI API traffic, routed with a one-run `openai_base_url` override and fail-secure behavior.

**Architecture:** icodex reads `ICODEX_PII_*` config, starts a localhost Python proxy when PII is enabled, and launches Codex as a child with `-c openai_base_url='"http://127.0.0.1:<port>/v1"'`. The proxy masks request content using a precision-first `rules` engine by default, optionally installs NLP support with EN/RU spaCy models, forwards sanitized requests to OpenAI, and relays streaming responses unchanged.

**Tech Stack:** Bash modules and tests, Python 3.8+ stdlib HTTP server, `requests`, optional Presidio/spaCy NLP packages, existing `tests/helpers.sh`, existing icodex `.codex_config` parser and launch flow.

---

## File Structure

- Create `lib/pii-proxy/server.py`: OpenAI-aware local HTTP proxy, masking rules, health/meta endpoints, upstream relay.
- Create `lib/pii-proxy/install.sh`: venv setup, `rules` dependency install, optional NLP dependency and EN/RU model install/update.
- Create `lib/pii-proxy/detect.sh`: installed runtime checks and proxy Python path resolution.
- Create `lib/pii-proxy/status.sh`: status output for runtime, engine, models, and active processes.
- Modify `lib/core/init.sh`: PII runtime paths and defaults.
- Modify `lib/config/env.sh`: PII env validation and mapping helpers.
- Modify `lib/command/args.sh`: PII commands/flags/help.
- Modify `lib/launcher/launch.sh`: PII proxy start/stop and `openai_base_url` injection.
- Modify `icodex.sh`: source PII modules, dispatch install/status/update hooks, call PII launch path.
- Modify `.codex_config.example`: document user-facing settings.
- Add `tests/test_pii_proxy_config.sh`: config validation and env mapping.
- Add `tests/test_pii_proxy_cli.sh`: CLI parsing/help/dispatch contracts.
- Add `tests/test_pii_proxy_launch.sh`: launch helper behavior and fail-secure checks.
- Add `tests/test_pii_proxy_install.sh`: install/update branch behavior.
- Add `tests/test_pii_proxy_status.sh`: status branch behavior.
- Add `tests/test_pii_proxy_masking.py`: masking rules.
- Add `tests/test_pii_proxy_openai_shapes.py`: OpenAI JSON traversal.
- Add `tests/test_pii_proxy_server.py`: HTTP proxy health, relay, and error behavior.
- Add `tests/test_pii_proxy_integration.sh`: local fake-upstream masking verification.

## Task 1: Config Defaults And Validation

**Files:**
- Modify: `lib/core/init.sh`
- Modify: `lib/config/env.sh`
- Test: `tests/test_pii_proxy_config.sh`

- [ ] **Step 1: Add the failing config test**

Create `tests/test_pii_proxy_config.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/core/init.sh"
source "$ROOT/lib/config/env.sh"

tmp="$(mktemp -d)"
cfg="$tmp/.codex_config"
export ICODEX_ROOT="$tmp/repo"
source "$ROOT/lib/core/init.sh"

assert_eq "pii venv path" "$tmp/repo/.codex-isolated/pii-proxy-venv" "$ICODEX_PII_PROXY_VENV"
assert_eq "pii script path" "$tmp/repo/.codex-isolated/pii-proxy-server.py" "$ICODEX_PII_PROXY_SERVER_SCRIPT"
assert_eq "pii log dir" "$tmp/repo/.codex-isolated/pii-proxy-logs" "$ICODEX_PII_PROXY_LOG_DIR"
assert_eq "default engine" "rules" "$ICODEX_PII_ENGINE"
assert_eq "default masking level" "standard" "$ICODEX_PII_MASKING_LEVEL"
assert_eq "default upstream" "https://api.openai.com/v1" "$ICODEX_PII_UPSTREAM_URL"

cat > "$cfg" <<'EOF'
ICODEX_USE_PII_PROXY=true
ICODEX_PII_ENGINE=nlp
ICODEX_PII_MASKING_LEVEL=secrets
ICODEX_PII_MASK_TOKEN=[MASKED]
ICODEX_PII_LOG_LEVEL=debug
ICODEX_PII_PROXY_PORT=0
ICODEX_PII_PROXY_PORT_MIN=21000
ICODEX_PII_PROXY_PORT_MAX=22000
ICODEX_PII_UPSTREAM_URL=https://api.openai.com/v1
ICODEX_PII_CONNECT_TIMEOUT=3
ICODEX_PII_READ_TIMEOUT=30
ICODEX_PII_SPACY_EN_MODEL=en_core_web_sm
ICODEX_PII_SPACY_RU_MODEL=ru_core_news_sm
EOF

load_config "$cfg"
assert_exit "valid pii config" 0 validate_pii_config
map_pii_env
assert_eq "engine mapped" "nlp" "$PII_PROXY_ENGINE"
assert_eq "masking mapped" "secrets" "$PII_PROXY_MASKING_LEVEL"
assert_eq "mask token mapped" "[MASKED]" "$PII_PROXY_MASK_TOKEN"
assert_eq "log mapped" "debug" "$PII_PROXY_LOG_LEVEL"
assert_eq "port min mapped" "21000" "$PII_PROXY_PORT_MIN"
assert_eq "upstream mapped" "https://api.openai.com/v1" "$PII_PROXY_UPSTREAM_URL"
assert_eq "en model mapped" "en_core_web_sm" "$PII_PROXY_SPACY_EN_MODEL"
assert_eq "ru model mapped" "ru_core_news_sm" "$PII_PROXY_SPACY_RU_MODEL"

ICODEX_PII_ENGINE=bad
assert_exit "invalid engine" 1 validate_pii_config
ICODEX_PII_ENGINE=rules
ICODEX_PII_MASKING_LEVEL=bad
assert_exit "invalid masking level" 1 validate_pii_config
ICODEX_PII_MASKING_LEVEL=standard
ICODEX_PII_LOG_LEVEL=trace
assert_exit "invalid log level" 1 validate_pii_config
ICODEX_PII_LOG_LEVEL=info
ICODEX_PII_UPSTREAM_URL=file:///tmp/x
assert_exit "invalid upstream" 1 validate_pii_config
ICODEX_PII_UPSTREAM_URL=http://example.com/v1
assert_exit "non-loopback http upstream" 1 validate_pii_config
ICODEX_PII_UPSTREAM_URL=http://127.0.0.1:9999/v1
assert_exit "loopback http upstream" 0 validate_pii_config

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/test_pii_proxy_config.sh
```

Expected: fails because `ICODEX_PII_PROXY_VENV`, `validate_pii_config`, and `map_pii_env` do not exist.

- [ ] **Step 3: Add defaults to `lib/core/init.sh`**

Append after existing path constants:

```bash
ICODEX_PII_PROXY_VENV="$ICODEX_SHARED_DIR/pii-proxy-venv"
ICODEX_PII_PROXY_SERVER_SCRIPT="$ICODEX_SHARED_DIR/pii-proxy-server.py"
ICODEX_PII_PROXY_LOG_DIR="$ICODEX_SHARED_DIR/pii-proxy-logs"
ICODEX_PII_PROXY_PID_DIR="$ICODEX_SHARED_DIR/pii-proxy-pid"
ICODEX_PII_PROXY_PID_FILE="$ICODEX_PII_PROXY_PID_DIR/session.pid"
ICODEX_USE_PII_PROXY="${ICODEX_USE_PII_PROXY:-false}"
ICODEX_PII_ENGINE="${ICODEX_PII_ENGINE:-rules}"
ICODEX_PII_MASKING_LEVEL="${ICODEX_PII_MASKING_LEVEL:-standard}"
ICODEX_PII_MASK_TOKEN="${ICODEX_PII_MASK_TOKEN:-REDACTED}"
ICODEX_PII_LOG_LEVEL="${ICODEX_PII_LOG_LEVEL:-info}"
ICODEX_PII_PROXY_PORT="${ICODEX_PII_PROXY_PORT:-0}"
ICODEX_PII_PROXY_PORT_MIN="${ICODEX_PII_PROXY_PORT_MIN:-20000}"
ICODEX_PII_PROXY_PORT_MAX="${ICODEX_PII_PROXY_PORT_MAX:-40000}"
ICODEX_PII_UPSTREAM_URL="${ICODEX_PII_UPSTREAM_URL:-https://api.openai.com/v1}"
ICODEX_PII_CONNECT_TIMEOUT="${ICODEX_PII_CONNECT_TIMEOUT:-10}"
ICODEX_PII_READ_TIMEOUT="${ICODEX_PII_READ_TIMEOUT:-300}"
ICODEX_PII_SPACY_EN_MODEL="${ICODEX_PII_SPACY_EN_MODEL:-en_core_web_lg}"
ICODEX_PII_SPACY_RU_MODEL="${ICODEX_PII_SPACY_RU_MODEL:-ru_core_news_lg}"
```

- [ ] **Step 4: Add validation and mapping to `lib/config/env.sh`**

Add:

```bash
_pii_is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

_pii_valid_upstream() {
  local url="${1:-}" rest host
  case "$url" in
    https://*) return 0 ;;
    http://127.0.0.1:*|http://127.0.0.1/*|http://localhost:*|http://localhost/*) return 0 ;;
    http://[[]::1[]]:*|http://[[]::1[]]/*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_pii_config() {
  case "${ICODEX_PII_ENGINE:-rules}" in rules|nlp) ;; *) log_error "invalid ICODEX_PII_ENGINE: $ICODEX_PII_ENGINE"; return 1 ;; esac
  case "${ICODEX_PII_MASKING_LEVEL:-standard}" in off|secrets|standard) ;; *) log_error "invalid ICODEX_PII_MASKING_LEVEL: $ICODEX_PII_MASKING_LEVEL"; return 1 ;; esac
  case "${ICODEX_PII_LOG_LEVEL:-info}" in info|debug) ;; *) log_error "invalid ICODEX_PII_LOG_LEVEL: $ICODEX_PII_LOG_LEVEL"; return 1 ;; esac
  _pii_is_uint "${ICODEX_PII_PROXY_PORT:-0}" || { log_error "invalid ICODEX_PII_PROXY_PORT"; return 1; }
  _pii_is_uint "${ICODEX_PII_PROXY_PORT_MIN:-20000}" || { log_error "invalid ICODEX_PII_PROXY_PORT_MIN"; return 1; }
  _pii_is_uint "${ICODEX_PII_PROXY_PORT_MAX:-40000}" || { log_error "invalid ICODEX_PII_PROXY_PORT_MAX"; return 1; }
  (( ICODEX_PII_PROXY_PORT_MIN >= 1024 && ICODEX_PII_PROXY_PORT_MIN < ICODEX_PII_PROXY_PORT_MAX && ICODEX_PII_PROXY_PORT_MAX <= 65535 )) || {
    log_error "invalid PII proxy port range"
    return 1
  }
  _pii_is_uint "${ICODEX_PII_CONNECT_TIMEOUT:-10}" || { log_error "invalid ICODEX_PII_CONNECT_TIMEOUT"; return 1; }
  _pii_is_uint "${ICODEX_PII_READ_TIMEOUT:-300}" || { log_error "invalid ICODEX_PII_READ_TIMEOUT"; return 1; }
  _pii_valid_upstream "${ICODEX_PII_UPSTREAM_URL:-https://api.openai.com/v1}" || {
    log_error "invalid ICODEX_PII_UPSTREAM_URL: ${ICODEX_PII_UPSTREAM_URL:-}"
    return 1
  }
}

map_pii_env() {
  export PII_PROXY_ENGINE="${ICODEX_PII_ENGINE:-rules}"
  export PII_PROXY_MASKING_LEVEL="${ICODEX_PII_MASKING_LEVEL:-standard}"
  export PII_PROXY_MASK_TOKEN="${ICODEX_PII_MASK_TOKEN:-REDACTED}"
  export PII_PROXY_LOG_LEVEL="${ICODEX_PII_LOG_LEVEL:-info}"
  export PII_PROXY_PORT="${ICODEX_PII_PROXY_PORT:-0}"
  export PII_PROXY_PORT_MIN="${ICODEX_PII_PROXY_PORT_MIN:-20000}"
  export PII_PROXY_PORT_MAX="${ICODEX_PII_PROXY_PORT_MAX:-40000}"
  export PII_PROXY_UPSTREAM_URL="${ICODEX_PII_UPSTREAM_URL:-https://api.openai.com/v1}"
  export PII_PROXY_CONNECT_TIMEOUT="${ICODEX_PII_CONNECT_TIMEOUT:-10}"
  export PII_PROXY_READ_TIMEOUT="${ICODEX_PII_READ_TIMEOUT:-300}"
  export PII_PROXY_SPACY_EN_MODEL="${ICODEX_PII_SPACY_EN_MODEL:-en_core_web_lg}"
  export PII_PROXY_SPACY_RU_MODEL="${ICODEX_PII_SPACY_RU_MODEL:-ru_core_news_lg}"
}
```

- [ ] **Step 5: Run config test**

Run:

```bash
bash tests/test_pii_proxy_config.sh
```

Expected: `PASS=25 FAIL=0` or higher if more assertions were added.

- [ ] **Step 6: Commit Task 1**

```bash
git add lib/core/init.sh lib/config/env.sh tests/test_pii_proxy_config.sh
git commit -m "feat(pii): add proxy config defaults and validation"
```

## Task 2: CLI Commands And Help

**Files:**
- Modify: `lib/command/args.sh`
- Modify: `icodex.sh`
- Test: `tests/test_pii_proxy_cli.sh`

- [ ] **Step 1: Add failing CLI test**

Create `tests/test_pii_proxy_cli.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/command/args.sh"

reset() {
  ICODEX_CMD="run"
  ICODEX_DISABLE_PROXY=0
  ICODEX_SET_PROXY=""
  ICODEX_PASSTHROUGH=()
  ICODEX_FULL_ACCESS=0
  ICODEX_USE_PII_PROXY_FLAG=0
}

reset; parse_args --pii-proxy
assert_eq "pii flag set" "1" "$ICODEX_USE_PII_PROXY_FLAG"
assert_eq "pii flag keeps run" "run" "$ICODEX_CMD"

reset; parse_args --install-pii-proxy
assert_eq "install pii command" "install-pii-proxy" "$ICODEX_CMD"

reset; parse_args --check-pii-proxy
assert_eq "check pii command" "check-pii-proxy" "$ICODEX_CMD"

reset; parse_args --pii-proxy -- model prompt
assert_eq "pii passthrough" "model prompt" "${ICODEX_PASSTHROUGH[*]}"

help="$(print_help)"
assert_contains "help documents --pii-proxy" "$help" "--pii-proxy"
assert_contains "help documents install pii" "$help" "--install-pii-proxy"
assert_contains "help documents check pii" "$help" "--check-pii-proxy"
assert_contains "help documents config toggle" "$help" "ICODEX_USE_PII_PROXY"

finish
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/test_pii_proxy_cli.sh
```

Expected: fails because PII flags are not parsed.

- [ ] **Step 3: Update `lib/command/args.sh`**

Add global:

```bash
ICODEX_USE_PII_PROXY_FLAG=0
```

Add cases:

```bash
      --pii-proxy) ICODEX_USE_PII_PROXY_FLAG=1; shift ;;
      --install-pii-proxy) ICODEX_CMD="install-pii-proxy"; shift ;;
      --check-pii-proxy) ICODEX_CMD="check-pii-proxy"; shift ;;
```

Add help rows:

```text
  --pii-proxy           Enable local PII/secrets masking proxy for this run
  --install-pii-proxy   Install/update PII proxy runtime and optional NLP models
  --check-pii-proxy     Show PII proxy installation and runtime status
```

Add config help text:

```text
  ICODEX_USE_PII_PROXY=true enables PII proxy by default.
  ICODEX_PII_ENGINE selects rules | nlp.
```

- [ ] **Step 4: Run CLI test**

```bash
bash tests/test_pii_proxy_cli.sh
```

Expected: `PASS=8 FAIL=0`.

- [ ] **Step 5: Commit Task 2**

```bash
git add lib/command/args.sh tests/test_pii_proxy_cli.sh
git commit -m "feat(pii): add proxy CLI flags"
```

## Task 3: Rules Masking Engine And OpenAI Shape Traversal

**Files:**
- Create: `lib/pii-proxy/server.py`
- Test: `tests/test_pii_proxy_masking.py`
- Test: `tests/test_pii_proxy_openai_shapes.py`

- [ ] **Step 1: Add failing masking tests**

Create `tests/test_pii_proxy_masking.py`:

```python
import importlib.util
from pathlib import Path

SERVER = Path(__file__).resolve().parents[1] / "lib" / "pii-proxy" / "server.py"
spec = importlib.util.spec_from_file_location("icodex_pii_proxy", SERVER)
pii = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pii)


def test_rules_mask_secrets_and_pii():
    text = (
        "email alice@example.com token github_pat_" + "A" * 90 +
        " password=supersecret1234 card 4111111111111111"
    )
    masked, found = pii.rules_mask(text, mask_token="REDACTED")
    assert "alice@example.com" not in masked
    assert "github_pat_" not in masked
    assert "supersecret1234" not in masked
    assert "4111111111111111" not in masked
    assert "REDACTED" in masked
    assert found


def test_rules_preserve_plain_urls_and_placeholders():
    text = "Visit https://example.com/docs and keep password=${DB_PASSWORD}"
    masked, found = pii.rules_mask(text, mask_token="REDACTED")
    assert "https://example.com/docs" in masked
    assert "${DB_PASSWORD}" in masked
    assert found == []


def test_credentials_in_url_masked():
    masked, found = pii.rules_mask("https://user:secret@example.com/path", mask_token="REDACTED")
    assert "secret" not in masked
    assert "https://REDACTED@example.com/path" == masked
    assert found


if __name__ == "__main__":
    test_rules_mask_secrets_and_pii()
    test_rules_preserve_plain_urls_and_placeholders()
    test_credentials_in_url_masked()
```

- [ ] **Step 2: Add failing OpenAI shape tests**

Create `tests/test_pii_proxy_openai_shapes.py`:

```python
import importlib.util
from pathlib import Path

SERVER = Path(__file__).resolve().parents[1] / "lib" / "pii-proxy" / "server.py"
spec = importlib.util.spec_from_file_location("icodex_pii_proxy", SERVER)
pii = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pii)


def test_responses_input_masked_instructions_preserved():
    body = {
        "model": "gpt-5.5",
        "instructions": "Use project path /home/user/repo and do not alter system rules.",
        "input": "Contact alice@example.com with token sk-proj-" + "A" * 40,
    }
    masked, found = pii.mask_openai_body(body)
    assert masked["instructions"] == body["instructions"]
    assert "alice@example.com" not in masked["input"]
    assert "sk-proj-" not in masked["input"]
    assert found


def test_chat_user_masked_system_preserved():
    body = {
        "messages": [
            {"role": "system", "content": "Do not mask /tmp/project paths."},
            {"role": "user", "content": "My email is bob@example.com"},
        ]
    }
    masked, found = pii.mask_openai_body(body)
    assert masked["messages"][0]["content"] == "Do not mask /tmp/project paths."
    assert "bob@example.com" not in masked["messages"][1]["content"]
    assert found


def test_tool_structural_fields_preserved():
    block = {
        "tool": {
            "file_path": "/home/alice/project/secret.txt",
            "pattern": "alice@example.com",
            "content": "real secret alice@example.com",
        }
    }
    masked, found = pii.mask_openai_body(block)
    assert masked["tool"]["file_path"] == "/home/alice/project/secret.txt"
    assert masked["tool"]["pattern"] == "alice@example.com"
    assert "alice@example.com" not in masked["tool"]["content"]


if __name__ == "__main__":
    test_responses_input_masked_instructions_preserved()
    test_chat_user_masked_system_preserved()
    test_tool_structural_fields_preserved()
```

- [ ] **Step 3: Run Python tests to verify they fail**

```bash
python3 tests/test_pii_proxy_masking.py
python3 tests/test_pii_proxy_openai_shapes.py
```

Expected: import failure or missing functions.

- [ ] **Step 4: Implement `lib/pii-proxy/server.py` masking core**

Create the file with executable header and these functions:

```python
#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
from typing import Any

DEFAULT_MASK_TOKEN = os.environ.get("PII_PROXY_MASK_TOKEN", "REDACTED")
MASKING_LEVEL = os.environ.get("PII_PROXY_MASKING_LEVEL", "standard").strip().lower()

STRUCTURAL_KEYS = frozenset({
    "file_path", "path", "notebook_path", "command", "pattern", "glob",
    "tool_call_id", "call_id", "id", "name", "role", "type",
})


def _replacement(mask_token: str) -> str:
    return mask_token.replace("\\", "\\\\")


def _patterns(mask_token: str):
    r = _replacement(mask_token)
    return [
        (re.compile(r"\\bsk-(?:proj-|ant-api03-|ant-|or-v1-)?[A-Za-z0-9\\-_]{20,}"), r, "API key"),
        (re.compile(r"\\bAKIA[0-9A-Z]{16}\\b"), r, "AWS access key id"),
        (re.compile(r"(?i)((?:aws[_-]?secret[_-]?(?:access[_-]?)?key|AWS_SECRET_ACCESS_KEY)\\s*[=:]\\s*)([\"']?)[A-Za-z0-9/+]{40}\\2"), rf"\\g<1>\\g<2>{r}\\g<2>", "AWS secret access key"),
        (re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?:-----| BLOCK-----)[\\s\\S]*?-----END (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?:-----| BLOCK-----)"), r, "private key"),
        (re.compile(r"\\bgh[pousr]_[A-Za-z0-9_]{36,}\\b"), r, "GitHub token"),
        (re.compile(r"\\bgithub_pat_[A-Za-z0-9_]{82,}\\b"), r, "GitHub fine-grained PAT"),
        (re.compile(r"\\bhf_[A-Za-z0-9_]{36,}\\b"), r, "HuggingFace token"),
        (re.compile(r"\\bgsk_[A-Za-z0-9\\-_]{50,}\\b"), r, "Groq key"),
        (re.compile(r"\\bAIzaSy[A-Za-z0-9_\\-]{32,}\\b"), r, "Google AI Studio key"),
        (re.compile(r"([a-zA-Z][a-zA-Z0-9+.-]*://)(?:[^@\\s/]+@)+"), rf"\\g<1>{r}@", "URL credentials"),
        (re.compile(r"(?i)((?:password|passwd|pwd|db_pass|pgpassword)\\s*[=:]\\s*)(?:[\"'](?!\\$\\{)((?:[^\"'\\\\]|\\\\.){8,})[\"']|([^\\s#\\n\"'$]{8,}))"), rf"\\g<1>{r}", "password assignment"),
        (re.compile(r"(?i)((?:secret|api[_-]?key|access[_-]?token|auth[_-]?token)\\s*[=:]\\s*)[\"']?([A-Za-z0-9\\-_./+=]{16,})[\"']?"), rf"\\g<1>{r}", "secret assignment"),
        (re.compile(r"\\beyJ[A-Za-z0-9\\-_]+\\.[A-Za-z0-9\\-_]+\\.[A-Za-z0-9\\-_]*\\b"), r, "JWT"),
        (re.compile(r"\\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13})\\b"), r, "credit card"),
        (re.compile(r"\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b", re.I), r, "email"),
        (re.compile(r"(?<!\\w)(?:\\+?\\d[\\d\\s().-]{8,}\\d)(?!\\w)"), r, "phone"),
        (re.compile(r"\\b[A-Z]{2}\\d{2}[A-Z0-9]{11,30}\\b"), r, "IBAN"),
        (re.compile(r"\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b"), r, "IP address"),
    ]


def rules_mask(text: str, mask_token: str = DEFAULT_MASK_TOKEN) -> tuple[str, list[str]]:
    found: list[str] = []
    for pattern, replacement, description in _patterns(mask_token):
        new_text = pattern.sub(replacement, text)
        if new_text != text:
            found.append(description)
            text = new_text
    return text, found


def mask_string(value: str) -> tuple[str, list[str]]:
    if MASKING_LEVEL == "off":
        return value, []
    return rules_mask(value)


def _mask_value(value: Any, key: str | None = None, depth: int = 0) -> tuple[Any, list[str]]:
    if depth > 50:
        return value, []
    if isinstance(value, str):
        if key in STRUCTURAL_KEYS:
            return value, []
        return mask_string(value)
    if isinstance(value, list):
        out = []
        found: list[str] = []
        for item in value:
            masked, item_found = _mask_value(item, key, depth + 1)
            out.append(masked)
            found.extend(item_found)
        return out, found
    if isinstance(value, dict):
        out: dict[str, Any] = {}
        found: list[str] = []
        for k, v in value.items():
            if k == "instructions":
                out[k] = v
                continue
            masked, item_found = _mask_value(v, k, depth + 1)
            out[k] = masked
            found.extend(item_found)
        return out, found
    return value, []


def mask_openai_body(body: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    masked, found = _mask_value(body)
    assert isinstance(masked, dict)
    return masked, found
```

- [ ] **Step 5: Run Python masking tests**

```bash
python3 tests/test_pii_proxy_masking.py
python3 tests/test_pii_proxy_openai_shapes.py
```

Expected: all tests pass.

- [ ] **Step 6: Commit Task 3**

```bash
git add lib/pii-proxy/server.py tests/test_pii_proxy_masking.py tests/test_pii_proxy_openai_shapes.py
git commit -m "feat(pii): add rules masking for OpenAI requests"
```

## Task 4: Proxy HTTP Server, Streaming Relay, And Health

**Files:**
- Modify: `lib/pii-proxy/server.py`
- Test: `tests/test_pii_proxy_server.py`

- [ ] **Step 1: Add failing server tests**

Create `tests/test_pii_proxy_server.py` with handler-level tests:

```python
import importlib.util
import io
import json
from pathlib import Path

SERVER = Path(__file__).resolve().parents[1] / "lib" / "pii-proxy" / "server.py"
spec = importlib.util.spec_from_file_location("icodex_pii_proxy", SERVER)
pii = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pii)


def _handler(path="/v1/responses", command="POST", body=b"{}"):
    h = pii.PIIProxyHandler.__new__(pii.PIIProxyHandler)
    h.path = path
    h.command = command
    h.headers = {"Content-Length": str(len(body))}
    h.rfile = io.BytesIO(body)
    h.wfile = io.BytesIO()
    h._codes = []
    h._headers = []
    h.send_response = lambda code, msg=None: h._codes.append(code)
    h.send_header = lambda k, v: h._headers.append((k, v))
    h.end_headers = lambda: None
    return h


def test_health_endpoint():
    h = _handler(path="/api/health", command="GET")
    h._health()
    assert h._codes == [200]
    data = json.loads(h.wfile.getvalue())
    assert data["status"] == "ready"
    assert data["masking_level"] in ("off", "secrets", "standard")


def test_proxy_messages_masks_before_forward(monkeypatch):
    raw = json.dumps({"input": "email alice@example.com"}).encode()
    h = _handler(body=raw)
    captured = {}
    h._forward = lambda body: captured.setdefault("body", body)
    h._proxy_messages()
    assert b"alice@example.com" not in captured["body"]
    assert b"REDACTED" in captured["body"]


def test_invalid_json_fails_closed():
    h = _handler(body=b"{bad json")
    h._proxy_messages()
    assert h._codes == [400]


if __name__ == "__main__":
    test_health_endpoint()
    test_proxy_messages_masks_before_forward(None)
    test_invalid_json_fails_closed()
```

- [ ] **Step 2: Run server tests to verify they fail**

```bash
python3 tests/test_pii_proxy_server.py
```

Expected: missing `PIIProxyHandler`.

- [ ] **Step 3: Extend `server.py` with HTTP proxy**

Add imports and handler:

```python
import argparse
import http.server
import logging
from logging.handlers import RotatingFileHandler
import random
import sys
import time
from pathlib import Path
try:
    import requests
except ImportError:
    requests = None

UPSTREAM_URL = os.environ.get("PII_PROXY_UPSTREAM_URL", "https://api.openai.com/v1").rstrip("/")
CONNECT_TIMEOUT = float(os.environ.get("PII_PROXY_CONNECT_TIMEOUT", "10"))
READ_TIMEOUT = float(os.environ.get("PII_PROXY_READ_TIMEOUT", "300"))
LOG_DIR = Path(os.environ.get("PII_PROXY_LOG_DIR", "/tmp/icodex-pii-proxy-logs"))
log = logging.getLogger("icodex-pii-proxy")


def setup_logging(log_dir: Path) -> None:
    log_dir.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(log_dir / "server.log", maxBytes=5 * 1024 * 1024, backupCount=3)
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(handler)
    log.setLevel(logging.INFO)


class PIIProxyHandler(http.server.BaseHTTPRequestHandler):
    _MAX_BODY_BYTES = 100_000_000

    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        if self.path == "/api/health":
            self._health()
        else:
            self._proxy_passthrough()

    def do_POST(self):
        if self.path.startswith("/v1/"):
            self._proxy_messages()
        else:
            self._proxy_passthrough()

    def _health(self):
        body = json.dumps({"status": "ready", "masking_level": MASKING_LEVEL}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        raw = self.headers.get("Content-Length", "0")
        try:
            length = int(raw)
        except ValueError:
            self._error(400, "Invalid Content-Length header")
            return None
        if length < 0 or length > self._MAX_BODY_BYTES:
            self._error(400, "Content-Length out of allowed range")
            return None
        return self.rfile.read(length) if length else b""

    def _error(self, code: int, message: str):
        body = json.dumps({"type": "error", "error": {"message": message}}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _proxy_messages(self):
        raw_body = self._read_body()
        if raw_body is None:
            return
        if MASKING_LEVEL == "off":
            self._forward(raw_body)
            return
        try:
            body = json.loads(raw_body)
        except json.JSONDecodeError:
            self._error(400, "PII proxy cannot safely mask malformed JSON")
            return
        masked, found = mask_openai_body(body)
        if found:
            log.info("Masked request: %d sensitive item(s)", len(found))
        self._forward(json.dumps(masked).encode())

    def _proxy_passthrough(self):
        body = self._read_body()
        if body is None:
            return
        self._forward(body)

    def _forward(self, body: bytes):
        target = UPSTREAM_URL + self.path
        headers = {k: v for k, v in self.headers.items() if k.lower() not in ("host", "content-length", "transfer-encoding")}
        if requests is None:
            self._error(500, "PII proxy runtime dependency missing: requests")
            return
        try:
            with requests.request(self.command, target, headers=headers, data=body, stream=True, timeout=(CONNECT_TIMEOUT, READ_TIMEOUT)) as resp:
                skip = {"transfer-encoding", "connection", "content-encoding", "content-length"}
                self.send_response(resp.status_code)
                for key, val in resp.headers.items():
                    if key.lower() not in skip:
                        self.send_header(key, val)
                self.end_headers()
                for chunk in resp.iter_content(chunk_size=4096):
                    if chunk:
                        self.wfile.write(chunk)
                        self.wfile.flush()
        except requests.RequestException as exc:
            log.error("upstream error: %s", exc)
            self._error(502, "PII proxy upstream unavailable")
```

Add server bind:

```python
def build_server(port: int):
    if port:
        return http.server.ThreadingHTTPServer(("127.0.0.1", port), PIIProxyHandler)
    lo = int(os.environ.get("PII_PROXY_PORT_MIN", "20000"))
    hi = int(os.environ.get("PII_PROXY_PORT_MAX", "40000"))
    for p in random.sample(range(lo, hi + 1), min(30, hi - lo + 1)):
        try:
            return http.server.ThreadingHTTPServer(("127.0.0.1", p), PIIProxyHandler)
        except OSError:
            continue
    return http.server.ThreadingHTTPServer(("127.0.0.1", 0), PIIProxyHandler)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=int(os.environ.get("PII_PROXY_PORT", "0")))
    parser.add_argument("--log-dir", default=str(LOG_DIR))
    args = parser.parse_args()
    setup_logging(Path(args.log_dir))
    server = build_server(args.port)
    port = server.server_address[1]
    Path(args.log_dir).mkdir(parents=True, exist_ok=True)
    (Path(args.log_dir) / "server.port").write_text(str(port))
    server.serve_forever()


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run server tests**

```bash
python3 tests/test_pii_proxy_server.py
```

Expected: all tests pass.

- [ ] **Step 5: Commit Task 4**

```bash
git add lib/pii-proxy/server.py tests/test_pii_proxy_server.py
git commit -m "feat(pii): add local OpenAI proxy server"
```

## Task 5: Install, Detect, Status, And NLP Model Update

**Files:**
- Create: `lib/pii-proxy/install.sh`
- Create: `lib/pii-proxy/detect.sh`
- Create: `lib/pii-proxy/status.sh`
- Modify: `icodex.sh`
- Test: `tests/test_pii_proxy_install.sh`
- Test: `tests/test_pii_proxy_status.sh`

- [ ] **Step 1: Add install/status tests**

Create `tests/test_pii_proxy_install.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/core/init.sh"
source "$ROOT/lib/pii-proxy/install.sh"

tmp="$(mktemp -d)"
export ICODEX_SHARED_DIR="$tmp/shared"
export ICODEX_PII_PROXY_VENV="$tmp/shared/pii-proxy-venv"
export ICODEX_PII_PROXY_SERVER_SCRIPT="$tmp/shared/pii-proxy-server.py"
export ICODEX_PII_PROXY_LOG_DIR="$tmp/shared/pii-proxy-logs"
mkdir -p "$ICODEX_SHARED_DIR"

calls="$tmp/calls.log"
_pii_python_ok() { return 0; }
_pii_venv_create() { mkdir -p "$ICODEX_PII_PROXY_VENV/bin"; touch "$ICODEX_PII_PROXY_VENV/bin/python3"; chmod +x "$ICODEX_PII_PROXY_VENV/bin/python3"; }
_pii_pip_install() { echo "pip:$*" >> "$calls"; }
_pii_spacy_download() { echo "spacy:$*" >> "$calls"; }

ICODEX_PII_ENGINE=rules
install_isolated_pii_proxy
assert_contains "rules installs requests" "$(cat "$calls")" "pip:requests"
assert_eq "rules marker" "rules" "$(cat "$ICODEX_PII_PROXY_VENV/pii_proxy_engine")"

: > "$calls"
ICODEX_PII_ENGINE=nlp
ICODEX_PII_SPACY_EN_MODEL=en_core_web_lg
ICODEX_PII_SPACY_RU_MODEL=ru_core_news_lg
install_isolated_pii_proxy
out="$(cat "$calls")"
assert_contains "nlp installs presidio" "$out" "presidio-analyzer"
assert_contains "nlp downloads en" "$out" "spacy:en en_core_web_lg en_core_web_sm"
assert_contains "nlp downloads ru" "$out" "spacy:ru ru_core_news_lg ru_core_news_sm"
assert_eq "nlp marker" "nlp" "$(cat "$ICODEX_PII_PROXY_VENV/pii_proxy_engine")"

: > "$calls"
update_pii_nlp_models
out="$(cat "$calls")"
assert_contains "update refreshes en model" "$out" "spacy:en en_core_web_lg en_core_web_sm"
assert_contains "update refreshes ru model" "$out" "spacy:ru ru_core_news_lg ru_core_news_sm"

rm -rf "$tmp"
finish
```

Create `tests/test_pii_proxy_status.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/pii-proxy/status.sh"

tmp="$(mktemp -d)"
export ICODEX_PII_PROXY_VENV="$tmp/venv"
export ICODEX_PII_PROXY_SERVER_SCRIPT="$tmp/server.py"
export ICODEX_PII_PROXY_LOG_DIR="$tmp/logs"
export ICODEX_PII_PROXY_PID_DIR="$tmp/pid"

out="$(check_pii_proxy_status)"
assert_contains "missing status says not installed" "$out" "not installed"

mkdir -p "$ICODEX_PII_PROXY_VENV/bin" "$ICODEX_PII_PROXY_LOG_DIR" "$ICODEX_PII_PROXY_PID_DIR"
touch "$ICODEX_PII_PROXY_VENV/bin/python3" "$ICODEX_PII_PROXY_SERVER_SCRIPT"
chmod +x "$ICODEX_PII_PROXY_VENV/bin/python3"
echo "rules" > "$ICODEX_PII_PROXY_VENV/pii_proxy_engine"
echo "32123" > "$ICODEX_PII_PROXY_LOG_DIR/server.port"
out="$(check_pii_proxy_status)"
assert_contains "status engine" "$out" "engine: rules"
assert_contains "status port" "$out" "port: 32123"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash tests/test_pii_proxy_install.sh
bash tests/test_pii_proxy_status.sh
```

Expected: source files missing.

- [ ] **Step 3: Implement `detect.sh`**

```bash
#!/usr/bin/env bash

detect_pii_proxy() {
  [[ -f "${ICODEX_PII_PROXY_SERVER_SCRIPT:-}" ]] || return 1
  [[ -d "${ICODEX_PII_PROXY_VENV:-}" ]] || return 1
  [[ -x "${ICODEX_PII_PROXY_VENV:-}/bin/python3" ]] || return 1
}

get_pii_proxy_python() {
  local py="${ICODEX_PII_PROXY_VENV:-}/bin/python3"
  [[ -x "$py" ]] || return 1
  printf '%s\n' "$py"
}
```

- [ ] **Step 4: Implement `install.sh` with overrideable helper functions**

```bash
#!/usr/bin/env bash

_pii_python_ok() { python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; }
_pii_venv_create() { python3 -m venv "$ICODEX_PII_PROXY_VENV"; }
_pii_pip_install() { "$ICODEX_PII_PROXY_VENV/bin/python3" -m pip install "$@"; }
_pii_spacy_download() {
  local lang="$1" primary="$2" fallback="$3"
  "$ICODEX_PII_PROXY_VENV/bin/python3" -m spacy download "$primary" --upgrade \
    || "$ICODEX_PII_PROXY_VENV/bin/python3" -m spacy download "$fallback"
}

install_isolated_pii_proxy() {
  _pii_python_ok || { log_error "Python 3.8+ required for PII proxy"; return 1; }
  mkdir -p "$(dirname "$ICODEX_PII_PROXY_VENV")"
  [[ -d "$ICODEX_PII_PROXY_VENV" ]] || _pii_venv_create || return 1
  _pii_pip_install --upgrade pip >/dev/null 2>&1 || true
  _pii_pip_install requests || return 1
  if [[ "${ICODEX_PII_ENGINE:-rules}" == "nlp" ]]; then
    _pii_pip_install presidio-analyzer presidio-anonymizer spacy --prefer-binary || return 1
    _pii_spacy_download en "${ICODEX_PII_SPACY_EN_MODEL:-en_core_web_lg}" en_core_web_sm || return 1
    _pii_spacy_download ru "${ICODEX_PII_SPACY_RU_MODEL:-ru_core_news_lg}" ru_core_news_sm || return 1
    printf '%s\n' "${ICODEX_PII_SPACY_EN_MODEL:-en_core_web_lg}" > "$ICODEX_PII_PROXY_VENV/spacy_model_en"
    printf '%s\n' "${ICODEX_PII_SPACY_RU_MODEL:-ru_core_news_lg}" > "$ICODEX_PII_PROXY_VENV/spacy_model_ru"
  fi
  printf '%s\n' "${ICODEX_PII_ENGINE:-rules}" > "$ICODEX_PII_PROXY_VENV/pii_proxy_engine"
  mkdir -p "$(dirname "$ICODEX_PII_PROXY_SERVER_SCRIPT")" "$ICODEX_PII_PROXY_LOG_DIR"
  ln -sf "$ICODEX_ROOT/lib/pii-proxy/server.py" "$ICODEX_PII_PROXY_SERVER_SCRIPT"
  chmod 700 "$ICODEX_ROOT/lib/pii-proxy/server.py"
}

update_pii_nlp_models() {
  local engine
  engine="$(cat "$ICODEX_PII_PROXY_VENV/pii_proxy_engine" 2>/dev/null || printf '%s\n' "${ICODEX_PII_ENGINE:-rules}")"
  [[ "$engine" == "nlp" || "${ICODEX_PII_ENGINE:-rules}" == "nlp" ]] || return 0
  [[ -d "$ICODEX_PII_PROXY_VENV" ]] || return 0
  _pii_pip_install --upgrade presidio-analyzer presidio-anonymizer spacy --prefer-binary || return 1
  _pii_spacy_download en "${ICODEX_PII_SPACY_EN_MODEL:-en_core_web_lg}" en_core_web_sm || return 1
  _pii_spacy_download ru "${ICODEX_PII_SPACY_RU_MODEL:-ru_core_news_lg}" ru_core_news_sm || return 1
  printf '%s\n' "${ICODEX_PII_SPACY_EN_MODEL:-en_core_web_lg}" > "$ICODEX_PII_PROXY_VENV/spacy_model_en"
  printf '%s\n' "${ICODEX_PII_SPACY_RU_MODEL:-ru_core_news_lg}" > "$ICODEX_PII_PROXY_VENV/spacy_model_ru"
}
```

- [ ] **Step 5: Implement `status.sh`**

```bash
#!/usr/bin/env bash

check_pii_proxy_status() {
  echo "PII proxy status"
  if [[ ! -f "${ICODEX_PII_PROXY_SERVER_SCRIPT:-}" || ! -d "${ICODEX_PII_PROXY_VENV:-}" ]]; then
    echo "not installed"
    return 0
  fi
  echo "server: $ICODEX_PII_PROXY_SERVER_SCRIPT"
  echo "venv: $ICODEX_PII_PROXY_VENV"
  local engine
  engine="$(cat "$ICODEX_PII_PROXY_VENV/pii_proxy_engine" 2>/dev/null || echo unknown)"
  echo "engine: $engine"
  if [[ "$engine" == "nlp" ]]; then
    echo "spacy en: $(cat "$ICODEX_PII_PROXY_VENV/spacy_model_en" 2>/dev/null || echo missing)"
    echo "spacy ru: $(cat "$ICODEX_PII_PROXY_VENV/spacy_model_ru" 2>/dev/null || echo missing)"
  fi
  if [[ -f "$ICODEX_PII_PROXY_LOG_DIR/server.port" ]]; then
    echo "port: $(cat "$ICODEX_PII_PROXY_LOG_DIR/server.port")"
  else
    echo "not running"
  fi
}
```

- [ ] **Step 6: Source modules and dispatch commands in `icodex.sh`**

Add `pii-proxy/detect pii-proxy/install pii-proxy/status` before `launcher/launch` in the source list.

Add command dispatch from Task 2:

```bash
    install-pii-proxy)
      require_tools || exit 1
      setup_shared_dirs
      validate_pii_config || exit 1
      install_isolated_pii_proxy || exit 1
      exit 0 ;;
    check-pii-proxy)
      check_pii_proxy_status
      exit 0 ;;
```

Extend the existing `update)` branch so NLP models refresh with normal icodex updates:

```bash
    update)
      setup_shared_dirs
      install_ensure --update || exit 1
      ensure_uv_dependency || exit 1
      ensure_cli_tools || exit 1
      update_pii_nlp_models || exit 1
      install_symlink
      ensure_path_entry
      exit 0 ;;
```

- [ ] **Step 7: Run install/status tests**

```bash
bash tests/test_pii_proxy_install.sh
bash tests/test_pii_proxy_status.sh
```

Expected: both pass.

- [ ] **Step 8: Commit Task 5**

```bash
git add lib/pii-proxy/install.sh lib/pii-proxy/detect.sh lib/pii-proxy/status.sh icodex.sh tests/test_pii_proxy_install.sh tests/test_pii_proxy_status.sh
git commit -m "feat(pii): add proxy install and status commands"
```

## Task 6: Launch Lifecycle And `openai_base_url` Override

**Files:**
- Modify: `lib/launcher/launch.sh`
- Modify: `icodex.sh`
- Test: `tests/test_pii_proxy_launch.sh`

- [ ] **Step 1: Add failing launch tests**

Create `tests/test_pii_proxy_launch.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/launcher/launch.sh"

tmp="$(mktemp -d)"
export ICODEX_BIN="$tmp/codex"
cat > "$ICODEX_BIN" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ICODEX_BIN.args"
SH
chmod +x "$ICODEX_BIN"

out_args() { cat "$ICODEX_BIN.args" 2>/dev/null || true; }

launch_codex --model test
assert_eq "normal launch args" "--model"$'\n'"test" "$(out_args)"

start_pii_proxy_server() { PII_PROXY_ACTIVE_PORT=23456; return 0; }
stop_pii_proxy_server() { :; }
export ICODEX_USE_PII_PROXY_RESOLVED=true
launch_codex_with_optional_pii --model test
args="$(out_args)"
assert_contains "pii adds config flag" "$args" "-c"
assert_contains "pii adds openai_base_url" "$args" "openai_base_url"
assert_contains "pii adds local port" "$args" "http://127.0.0.1:23456/v1"

start_pii_proxy_server() { return 1; }
assert_exit "start failure fail-secure" 1 launch_codex_with_optional_pii

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/test_pii_proxy_launch.sh
```

Expected: missing `launch_codex_with_optional_pii`.

- [ ] **Step 3: Refactor `launch_codex` to allow child execution**

Replace current `launch_codex` body with:

```bash
launch_codex() { # <args...>
  if [[ ! -x "$ICODEX_BIN" ]]; then
    log_error "codex binary missing — run: ./icodex.sh --install"
    return 1
  fi
  if [[ "${ICODEX_LAUNCH_NO_EXEC:-0}" == "1" ]]; then
    "$ICODEX_BIN" "$@"
  else
    exec "$ICODEX_BIN" "$@"
  fi
}
```

Add:

```bash
launch_codex_with_optional_pii() {
  if [[ "${ICODEX_USE_PII_PROXY_RESOLVED:-false}" != "true" ]]; then
    launch_codex "$@"
    return $?
  fi
  start_pii_proxy_server || return 1
  trap 'stop_pii_proxy_server' EXIT INT TERM
  ICODEX_LAUNCH_NO_EXEC=1 launch_codex \
    -c "openai_base_url=\"http://127.0.0.1:${PII_PROXY_ACTIVE_PORT}/v1\"" \
    "$@"
}
```

- [ ] **Step 4: Add start/stop functions to `launch.sh`**

Add below `launch_codex_with_optional_pii`:

```bash
start_pii_proxy_server() {
  local py
  py="$(get_pii_proxy_python)" || { log_error "PII proxy not installed — run: ./icodex.sh --install-pii-proxy"; return 1; }
  mkdir -p "$ICODEX_PII_PROXY_LOG_DIR" "$ICODEX_PII_PROXY_PID_DIR"
  rm -f "$ICODEX_PII_PROXY_LOG_DIR/server.port"
  map_pii_env
  PII_PROXY_LOG_DIR="$ICODEX_PII_PROXY_LOG_DIR" \
  "$py" "$ICODEX_PII_PROXY_SERVER_SCRIPT" --port "$ICODEX_PII_PROXY_PORT" --log-dir "$ICODEX_PII_PROXY_LOG_DIR" \
    >/dev/null 2>&1 &
  PII_PROXY_PID=$!
  echo "$PII_PROXY_PID" > "$ICODEX_PII_PROXY_PID_FILE"
  local ticks=0 port=""
  while (( ticks < 30 )); do
    if ! kill -0 "$PII_PROXY_PID" 2>/dev/null; then
      log_error "PII proxy exited during startup"
      return 1
    fi
    if [[ -f "$ICODEX_PII_PROXY_LOG_DIR/server.port" ]]; then
      port="$(cat "$ICODEX_PII_PROXY_LOG_DIR/server.port" 2>/dev/null || true)"
      if [[ "$port" =~ ^[0-9]+$ ]] && (: >/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
        PII_PROXY_ACTIVE_PORT="$port"
        export PII_PROXY_ACTIVE_PORT
        return 0
      fi
    fi
    sleep 0.5
    ticks=$((ticks + 1))
  done
  log_error "PII proxy did not become ready"
  kill "$PII_PROXY_PID" 2>/dev/null || true
  return 1
}

stop_pii_proxy_server() {
  if [[ -f "${ICODEX_PII_PROXY_PID_FILE:-}" ]]; then
    local pid
    pid="$(cat "$ICODEX_PII_PROXY_PID_FILE" 2>/dev/null || true)"
    rm -f "$ICODEX_PII_PROXY_PID_FILE" "$ICODEX_PII_PROXY_LOG_DIR/server.port"
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  fi
}
```

- [ ] **Step 5: Wire run path in `icodex.sh`**

Before final launch:

```bash
  ICODEX_USE_PII_PROXY_RESOLVED=false
  if [[ "${ICODEX_USE_PII_PROXY:-false}" == "true" || "$ICODEX_USE_PII_PROXY_FLAG" == "1" ]]; then
    ICODEX_USE_PII_PROXY_RESOLVED=true
    validate_pii_config || exit 1
    detect_pii_proxy || { log_error "PII proxy not installed — run: ./icodex.sh --install-pii-proxy"; exit 1; }
  fi
  launch_codex_with_optional_pii ${ICODEX_PASSTHROUGH[@]+"${ICODEX_PASSTHROUGH[@]}"}
```

Replace the old final `launch_codex ...` call with the snippet above.

- [ ] **Step 6: Run launch tests**

```bash
bash tests/test_pii_proxy_launch.sh
```

Expected: pass.

- [ ] **Step 7: Commit Task 6**

```bash
git add lib/launcher/launch.sh icodex.sh tests/test_pii_proxy_launch.sh
git commit -m "feat(pii): route Codex through local proxy"
```

## Task 7: Local Integration Test With Fake Upstream

**Files:**
- Test: `tests/test_pii_proxy_integration.sh`

- [ ] **Step 1: Add integration test**

Create `tests/test_pii_proxy_integration.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

tmp="$(mktemp -d)"
up_log="$tmp/upstream.json"
up_port_file="$tmp/upstream.port"
proxy_log="$tmp/proxy"
mkdir -p "$proxy_log"

python3 - "$up_log" "$up_port_file" <<'PY' &
import http.server, json, sys
from pathlib import Path
log = Path(sys.argv[1])
port_file = Path(sys.argv[2])
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        log.write_bytes(body)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')
    def log_message(self, *a): pass
s=http.server.ThreadingHTTPServer(("127.0.0.1",0),H)
port_file.write_text(str(s.server_address[1]))
s.serve_forever()
PY
up_pid=$!
trap 'kill "$up_pid" "$proxy_pid" 2>/dev/null || true; rm -rf "$tmp"' EXIT

for _ in {1..30}; do [[ -f "$up_port_file" ]] && break; sleep 0.1; done
up_port="$(cat "$up_port_file")"

PII_PROXY_UPSTREAM_URL="http://127.0.0.1:$up_port/v1" \
PII_PROXY_MASKING_LEVEL=standard \
PII_PROXY_LOG_DIR="$proxy_log" \
python3 "$ROOT/lib/pii-proxy/server.py" --port 0 --log-dir "$proxy_log" &
proxy_pid=$!
for _ in {1..30}; do [[ -f "$proxy_log/server.port" ]] && break; sleep 0.2; done
proxy_port="$(cat "$proxy_log/server.port")"

curl -sS -X POST "http://127.0.0.1:$proxy_port/v1/responses" \
  -H 'Content-Type: application/json' \
  -d '{"input":"email alice@example.com token github_pat_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}' \
  >/dev/null

body="$(cat "$up_log")"
assert_contains "upstream got redacted token" "$body" "REDACTED"
if grep -q 'alice@example.com\|github_pat_' "$up_log"; then
  echo "FAIL [raw sensitive data reached upstream]"
  exit 1
else
  echo "PASS [raw sensitive data did not reach upstream]"
fi

finish
```

- [ ] **Step 2: Run integration test**

```bash
bash tests/test_pii_proxy_integration.sh
```

Expected: raw email/token absent from fake upstream log.

- [ ] **Step 3: Commit Task 7**

```bash
git add tests/test_pii_proxy_integration.sh
git commit -m "test(pii): verify local upstream receives masked requests"
```

## Task 8: Documentation And Config Example

**Files:**
- Modify: `.codex_config.example`
- Modify: `docs/superpowers/specs/2026-07-08-icodex-pii-proxy-design.md` only if implementation decisions drift
- iwiki: update `icodex` domain after implementation

- [ ] **Step 1: Update `.codex_config.example`**

Add a PII section after the proxy section:

```bash
# PII proxy for Codex OpenAI API traffic. Unset/off disables (ship default).
# When enabled, icodex starts a local proxy and launches Codex with a one-run
# openai_base_url override pointing to 127.0.0.1.
#ICODEX_USE_PII_PROXY=true

# rules = regex + validators (default, lightweight); nlp = Presidio/spaCy mode.
# NLP mode installs and updates English and Russian spaCy models.
#ICODEX_PII_ENGINE=rules

# off | secrets | standard. Default standard.
#ICODEX_PII_MASKING_LEVEL=standard
#ICODEX_PII_MASK_TOKEN=REDACTED
#ICODEX_PII_LOG_LEVEL=info
#ICODEX_PII_PROXY_PORT=0
#ICODEX_PII_PROXY_PORT_MIN=20000
#ICODEX_PII_PROXY_PORT_MAX=40000
#ICODEX_PII_UPSTREAM_URL=https://api.openai.com/v1
#ICODEX_PII_CONNECT_TIMEOUT=10
#ICODEX_PII_READ_TIMEOUT=300
#ICODEX_PII_SPACY_EN_MODEL=en_core_web_lg
#ICODEX_PII_SPACY_RU_MODEL=ru_core_news_lg
```

- [ ] **Step 2: Update iwiki after implementation**

Use MCP tools:

```text
wiki_update_page(domain="icodex", slug="install-update-and-proxy", heading="PII Proxy", new_body="<summary of config, commands, routing, masking, fail-secure behavior>", source="lib/pii-proxy/server.py")
wiki_lint(domain="icodex")
```

If no suitable page heading exists, use `wiki_write_page(domain="icodex", slug="pii-proxy", markdown=..., source="lib/pii-proxy/server.py")`.

- [ ] **Step 3: Commit Task 8**

```bash
git add .codex_config.example docs/superpowers/specs/2026-07-08-icodex-pii-proxy-design.md
git commit -m "docs(pii): document proxy configuration"
```

## Task 9: Full Validation And Result Preparation

**Files:**
- Modify: docs/wiki through iwiki MCP if not already done
- No implementation files unless fixing validation failures

- [ ] **Step 1: Run focused tests**

```bash
bash tests/test_pii_proxy_config.sh
bash tests/test_pii_proxy_cli.sh
bash tests/test_pii_proxy_install.sh
bash tests/test_pii_proxy_status.sh
bash tests/test_pii_proxy_launch.sh
python3 tests/test_pii_proxy_masking.py
python3 tests/test_pii_proxy_openai_shapes.py
python3 tests/test_pii_proxy_server.py
bash tests/test_pii_proxy_integration.sh
```

Expected: every command exits `0`.

- [ ] **Step 2: Run full Bash suite**

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: exits `0`.

- [ ] **Step 3: Run Python syntax check**

```bash
python3 -m py_compile lib/pii-proxy/server.py
```

Expected: exits `0`.

- [ ] **Step 4: Check git diff scope**

```bash
git diff --stat
```

Expected: diff contains only PII proxy implementation, tests, config docs, chain docs, and required wiki/docs updates.

- [ ] **Step 5: Run result gate**

Run:

```text
/check-chain result docs/superpowers/plans/2026-07-08-icodex-pii-proxy.md
```

Expected: `OK`, with report regenerated at `docs/superpowers/reports/icodex-pii-proxy-results.html`.
