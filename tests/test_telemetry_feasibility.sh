#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/core/init.sh"
source "$ROOT/lib/telemetry/telemetry.sh"
source "$ROOT/lib/telemetry/langfuse.sh"

tmp="$(mktemp -d)"
trap '[[ -n "${server_pid:-}" ]] && kill "$server_pid" 2>/dev/null || true; rm -rf "$tmp"' EXIT

cfg="$tmp/config.toml"
telemetry_langfuse_write_provider_config "$cfg" "http://127.0.0.1:18766/v1"
out="$(cat "$cfg")"
assert_contains "provider model selected" "$out" 'model_provider = "icodex_capture"'
assert_contains "provider table written" "$out" "[model_providers.icodex_capture]"
assert_contains "provider name written" "$out" 'name = "icodex Langfuse Capture"'
assert_contains "provider base url written" "$out" 'base_url = "http://127.0.0.1:18766/v1"'
assert_contains "provider wire api responses" "$out" 'wire_api = "responses"'

bad_cfg="$tmp/bad-config.toml"
if telemetry_langfuse_write_provider_config "$bad_cfg" "https://example.com/v1" >/dev/null 2>&1; then
  echo "FAIL [public provider url rejected]"
  FAIL=$((FAIL+1))
else
  echo "PASS [public provider url rejected]"
  PASS=$((PASS+1))
fi

if [[ "${ICODEX_RUN_CODEX_FEASIBILITY:-0}" != "1" ]]; then
  echo "PASS [codex provider feasibility probe skipped]"
  PASS=$((PASS+1))
  finish
  exit $?
fi

if [[ ! -x "$ROOT/.codex-isolated/bin/codex" ]]; then
  echo "PASS [codex provider feasibility probe skipped: codex binary missing]"
  PASS=$((PASS+1))
  finish
  exit $?
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "PASS [codex provider feasibility probe skipped: python3 missing]"
  PASS=$((PASS+1))
  finish
  exit $?
fi

server="$tmp/fake-capture.py"
cat > "$server" <<'PY'
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length)
        with open(os.environ["ICODEX_PROBE_PATH_FILE"], "w", encoding="utf-8") as f:
            f.write(self.path)
        with open(os.environ["ICODEX_PROBE_HEADERS_FILE"], "w", encoding="utf-8") as f:
            for key, value in self.headers.items():
                f.write(f"{key}: {value}\n")
        with open(os.environ["ICODEX_PROBE_BODY_FILE"], "wb") as f:
            f.write(body)
        self.send_response(401)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"probe server")

    def log_message(self, fmt, *args):
        return

server = HTTPServer(("127.0.0.1", 0), Handler)
with open(os.environ["ICODEX_PROBE_PORT_FILE"], "w", encoding="utf-8") as f:
    f.write(str(server.server_port))
server.handle_request()
PY

port_file="$tmp/port"
path_file="$tmp/path"
headers_file="$tmp/headers"
body_file="$tmp/body.json"
err_file="$tmp/codex.err"
out_file="$tmp/codex.out"
ICODEX_PROBE_PORT_FILE="$port_file" \
ICODEX_PROBE_PATH_FILE="$path_file" \
ICODEX_PROBE_HEADERS_FILE="$headers_file" \
ICODEX_PROBE_BODY_FILE="$body_file" \
  python3 "$server" &
server_pid="$!"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -s "$port_file" ]] && break
  sleep 0.1
done

if [[ ! -s "$port_file" ]]; then
  echo "FAIL [fake capture server started]"
  FAIL=$((FAIL+1))
  finish
fi
echo "PASS [fake capture server started]"
PASS=$((PASS+1))

home="$tmp/codex-home"
work="$tmp/work"
mkdir -p "$home" "$work"
port="$(cat "$port_file")"
telemetry_langfuse_write_provider_config "$home/config.toml" "http://127.0.0.1:${port}/v1"
ICODEX_BIN="$ROOT/.codex-isolated/bin/codex"
export ICODEX_BIN
sentinel="ICX_FULL_BODY_456"
CODEX_HOME="$home" telemetry_langfuse_probe_command "$work" "Return exactly ${sentinel}." >"$out_file" 2>"$err_file" &
probe_pid="$!"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
  kill -0 "$probe_pid" 2>/dev/null || break
  sleep 1
done
if kill -0 "$probe_pid" 2>/dev/null; then
  kill "$probe_pid" 2>/dev/null || true
  wait "$probe_pid" 2>/dev/null || true
  code=124
else
  wait "$probe_pid"
  code="$?"
fi
case "$code" in
  0|1|124) echo "PASS [codex probe completed or reached fake provider]" ; PASS=$((PASS+1)) ;;
  *) echo "FAIL [codex probe completed or reached fake provider]: exit $code" ; FAIL=$((FAIL+1)) ;;
esac

if [[ -s "$body_file" ]]; then
  echo "PASS [fake provider received request]"
  PASS=$((PASS+1))
else
  echo "FAIL [fake provider received request]"
  FAIL=$((FAIL+1))
fi

assert_eq "provider request path" "/v1/responses" "$(cat "$path_file" 2>/dev/null || true)"
if grep -qi '^accept: text/event-stream' "$headers_file" 2>/dev/null; then
  echo "PASS [provider accepts sse]"
  PASS=$((PASS+1))
else
  echo "FAIL [provider accepts sse]"
  FAIL=$((FAIL+1))
fi
assert_contains "provider body contains sentinel" "$(cat "$body_file" 2>/dev/null || true)" "$sentinel"
if grep -Eq '"stream"[[:space:]]*:[[:space:]]*true' "$body_file" 2>/dev/null; then
  echo "PASS [provider body streams]"
  PASS=$((PASS+1))
else
  echo "FAIL [provider body streams]"
  FAIL=$((FAIL+1))
fi
if grep -Eq '"store"[[:space:]]*:[[:space:]]*false' "$body_file" 2>/dev/null; then
  echo "PASS [provider body avoids persistence]"
  PASS=$((PASS+1))
else
  echo "FAIL [provider body avoids persistence]"
  FAIL=$((FAIL+1))
fi

if grep -qF "api.openai.com" "$err_file"; then
  echo "FAIL [probe stderr stays on local provider]"
  FAIL=$((FAIL+1))
else
  echo "PASS [probe stderr stays on local provider]"
  PASS=$((PASS+1))
fi

finish
