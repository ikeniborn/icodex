#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

tmp="$(mktemp -d)"
up_log="$tmp/upstream.json"
up_path_log="$tmp/upstream.path"
up_port_file="$tmp/upstream.port"
proxy_log="$tmp/proxy"
mkdir -p "$proxy_log"

python3 - "$up_log" "$up_path_log" "$up_port_file" <<'PY' &
import http.server, sys
from pathlib import Path
log = Path(sys.argv[1])
path_log = Path(sys.argv[2])
port_file = Path(sys.argv[3])

class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        log.write_bytes(body)
        path_log.write_text(self.path)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def log_message(self, *a):
        pass

s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
port_file.write_text(str(s.server_address[1]))
s.serve_forever()
PY
up_pid=$!
proxy_pid=""
trap 'kill "$up_pid" ${proxy_pid:+"$proxy_pid"} 2>/dev/null || true; rm -rf "$tmp"' EXIT

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
assert_eq "upstream path not double-v1" "/v1/responses" "$(cat "$up_path_log")"
if grep -q 'alice@example.com\|github_pat_' "$up_log"; then
  echo "FAIL [raw sensitive data reached upstream]"
  exit 1
else
  echo "PASS [raw sensitive data did not reach upstream]"
fi

finish
