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
