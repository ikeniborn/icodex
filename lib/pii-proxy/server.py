#!/usr/bin/env python3
from __future__ import annotations

import argparse
import http.server
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import random
import re
from typing import Any

try:
    import requests
except ImportError:
    requests = None

DEFAULT_MASK_TOKEN = os.environ.get("PII_PROXY_MASK_TOKEN", "REDACTED")
MASKING_LEVEL = os.environ.get("PII_PROXY_MASKING_LEVEL", "standard").strip().lower()
UPSTREAM_URL = os.environ.get("PII_PROXY_UPSTREAM_URL", "https://api.openai.com/v1").rstrip("/")
CONNECT_TIMEOUT = float(os.environ.get("PII_PROXY_CONNECT_TIMEOUT", "10"))
READ_TIMEOUT = float(os.environ.get("PII_PROXY_READ_TIMEOUT", "300"))
LOG_DIR = Path(os.environ.get("PII_PROXY_LOG_DIR", "/tmp/icodex-pii-proxy-logs"))
log = logging.getLogger("icodex-pii-proxy")

STRUCTURAL_KEYS = frozenset({
    "file_path", "path", "notebook_path", "command", "pattern", "glob",
    "tool_call_id", "call_id", "id", "name", "role", "type",
})


def _replacement(mask_token: str) -> str:
    return mask_token.replace("\\", "\\\\")


def _patterns(mask_token: str):
    r = _replacement(mask_token)
    return [
        (re.compile(r"\bsk-(?:proj-|ant-api03-|ant-|or-v1-)?[A-Za-z0-9\-_]{20,}"), r, "API key"),
        (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), r, "AWS access key id"),
        (re.compile(r"(?i)((?:aws[_-]?secret[_-]?(?:access[_-]?)?key|AWS_SECRET_ACCESS_KEY)\s*[=:]\s*)([\"']?)[A-Za-z0-9/+]{40}\2"), rf"\g<1>\g<2>{r}\g<2>", "AWS secret access key"),
        (re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?:-----| BLOCK-----)[\s\S]*?-----END (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?:-----| BLOCK-----)"), r, "private key"),
        (re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{36,}\b"), r, "GitHub token"),
        (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{82,}\b"), r, "GitHub fine-grained PAT"),
        (re.compile(r"\bhf_[A-Za-z0-9_]{36,}\b"), r, "HuggingFace token"),
        (re.compile(r"\bgsk_[A-Za-z0-9\-_]{50,}\b"), r, "Groq key"),
        (re.compile(r"\bAIzaSy[A-Za-z0-9_\-]{32,}\b"), r, "Google AI Studio key"),
        (re.compile(r"([a-zA-Z][a-zA-Z0-9+.-]*://)(?:[^@\s/]+@)+"), rf"\g<1>{r}@", "URL credentials"),
        (re.compile(r"(?i)((?:password|passwd|pwd|db_pass|pgpassword)\s*[=:]\s*)(?:[\"'](?!\$\{)((?:[^\"'\\]|\\.){8,})[\"']|([^\s#\n\"'$]{8,}))"), rf"\g<1>{r}", "password assignment"),
        (re.compile(r"(?i)((?:secret|api[_-]?key|access[_-]?token|auth[_-]?token)\s*[=:]\s*)[\"']?([A-Za-z0-9\-_./+=]{16,})[\"']?"), rf"\g<1>{r}", "secret assignment"),
        (re.compile(r"\beyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]*\b"), r, "JWT"),
        (re.compile(r"\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13})\b"), r, "credit card"),
        (re.compile(r"(?<![:/@\w])[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.I), r, "email"),
        (re.compile(r"(?<!\w)(?:\+?\d[\d\s().-]{8,}\d)(?!\w)"), r, "phone"),
        (re.compile(r"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b"), r, "IBAN"),
        (re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"), r, "IP address"),
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
        role = value.get("role")
        for k, v in value.items():
            if k == "instructions" or (role in ("system", "developer") and k == "content"):
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


def setup_logging(log_dir: Path) -> None:
    log_dir.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(log_dir / "server.log", maxBytes=5 * 1024 * 1024, backupCount=3)
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    if not log.handlers:
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
        headers = {
            k: v for k, v in self.headers.items()
            if k.lower() not in ("host", "content-length", "transfer-encoding")
        }
        if requests is None:
            self._error(500, "PII proxy runtime dependency missing: requests")
            return
        try:
            with requests.request(
                self.command,
                target,
                headers=headers,
                data=body,
                stream=True,
                timeout=(CONNECT_TIMEOUT, READ_TIMEOUT),
            ) as resp:
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
