"""Exercise proxy diagnostics with a local authenticated CONNECT server."""
import base64
import os
from pathlib import Path
import socket
import socketserver
import ssl
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROXY_VARS = ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.connection.settimeout(3)
        try:
            request = self.rfile.readline()
            headers = {}
            while line := self.rfile.readline():
                if line == b"\r\n":
                    break
                key, value = line.split(b":", 1)
                headers[key.lower()] = value.strip()
            if not request:
                return
            self.server.requests.append((request, headers))
            expected = b"Basic " + base64.b64encode(b"test:secret")
            if headers.get(b"proxy-authorization") != expected:
                self.wfile.write(b"HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\n\r\n")
                return
            self.wfile.write(b"HTTP/1.1 200 Connection established\r\n\r\n")
            self.wfile.flush()
            with self.server.tls.wrap_socket(self.connection, server_side=True) as conn:
                data = b""
                while b"\r\n\r\n" not in data:
                    chunk = conn.recv(4096)
                    if not chunk:
                        return
                    data += chunk
                self.server.target_requests.append(data)
                status = self.server.target_status
                conn.sendall(f"HTTP/1.1 {status} Response\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".encode())
        except (OSError, ssl.SSLError):
            pass


class ProxyDiagnostics(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.cert = Path(cls.tmp.name) / "ca.pem"
        key = Path(cls.tmp.name) / "key.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                        "-keyout", str(key), "-out", str(cls.cert), "-days", "1",
                        "-subj", "/CN=chatgpt.com", "-addext", "subjectAltName=DNS:chatgpt.com"],
                       check=True, capture_output=True)
        cls.server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler)
        cls.server.daemon_threads = True
        cls.server.tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        cls.server.tls.load_cert_chain(cls.cert, key)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.tmp.cleanup()

    def setUp(self):
        self.server.requests = []
        self.server.target_requests = []
        self.server.target_status = 401

    def shell(self, code, url=None, extra=None):
        env = {"PATH": os.environ["PATH"]}
        env.update(CURL_CA_BUNDLE=str(self.cert), NO_PROXY="*", no_proxy="*")
        env["ICODEX_PROXY"] = url or f"http://test:secret@127.0.0.1:{self.server.server_address[1]}"
        env.update(extra or {})
        prefix = 'source lib/core/logging.sh; source lib/config/env.sh; source lib/proxy/proxy.sh; '
        return subprocess.run(["bash", "-c", prefix + code], cwd=ROOT, env=env,
                              text=True, capture_output=True, timeout=15)

    def test_authenticated_tunnel_ignores_bypass_and_sends_no_account_token(self):
        r = self.shell('proxy_ensure </dev/null; [[ "${HTTPS_PROXY:-}" == "$ICODEX_PROXY" ]]')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(self.server.target_requests, "TCP alone does not prove a tunnel works")
        self.assertIn(b"/backend-api/wham/accounts/check", self.server.target_requests[0])
        self.assertNotIn(b"\r\nauthorization:", self.server.target_requests[0].lower())

    def test_bad_password_is_diagnosed_and_not_exported(self):
        url = f"http://test:wrong-secret@127.0.0.1:{self.server.server_address[1]}"
        r = self.shell('proxy_ensure </dev/null; [[ -z "${HTTPS_PROXY:-}" ]]', url)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("407", r.stderr)
        self.assertNotIn("wrong-secret", r.stderr)
        self.assertNotIn("test:", r.stderr)

    def test_target_rejection_is_distinct_from_proxy_authentication(self):
        self.server.target_status = 403
        r = self.shell('proxy_ensure </dev/null')
        self.assertIn("target", r.stderr)
        self.assertIn("403", r.stderr)

    def test_closed_port_clears_inherited_proxy_without_leaking_url(self):
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        r = self.shell('proxy_ensure </dev/null; printf "%s\\n" "${HTTP_PROXY:-}" "${HTTPS_PROXY:-}" "${ALL_PROXY:-}" "${http_proxy:-}" "${https_proxy:-}" "${all_proxy:-}"', f"http://test:private-secret@127.0.0.1:{port}",
                       {k: "http://stale.invalid:9" for k in PROXY_VARS})
        self.assertIn("TCP", r.stderr)
        self.assertNotIn("private-secret", r.stderr)
        self.assertNotIn("stale.invalid", r.stdout)

    def test_invalid_scheme_cannot_replace_saved_proxy(self):
        cfg = Path(self.tmp.name) / "config"
        cfg.write_text("ICODEX_PROXY=http://old.invalid:9\n")
        r = self.shell('proxy_save "$TEST_CONFIG" "$ICODEX_PROXY"',
                       'socks5s://test:private-secret@localhost:1080', {"TEST_CONFIG": str(cfg)})
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(cfg.read_text(), "ICODEX_PROXY=http://old.invalid:9\n")
        self.assertNotIn("private-secret", r.stderr)

    def test_no_proxy_clears_environment_before_wrapper_network_work(self):
        # Run the real main up to the first tool prerequisite, before downloads or writes.
        code = '''source lib/command/args.sh
eval "$(sed -n '/^main() {/,/^}/p' icodex.sh)"
ICODEX_CONFIG=/dev/null
load_config() { :; }
require_tools() { printf 'PATH=present\\n%s\\n' "${HTTP_PROXY:-}" "${HTTPS_PROXY:-}" "${ALL_PROXY:-}" "${http_proxy:-}" "${https_proxy:-}" "${all_proxy:-}"; return 1; }
main --no-proxy'''
        r = self.shell(code, extra={k: "http://stale.invalid:9" for k in PROXY_VARS})
        self.assertNotIn("stale.invalid", r.stdout)
        self.assertIn("PATH=", r.stdout)

    def test_malformed_authority_preserves_saved_proxy(self):
        cfg = Path(self.tmp.name) / "config"
        cfg.write_text("ICODEX_PROXY=http://old.invalid:9\n")
        r = self.shell('proxy_save "$TEST_CONFIG" "$ICODEX_PROXY"',
                       'http://host:80:90', {"TEST_CONFIG": str(cfg)})
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(cfg.read_text(), "ICODEX_PROXY=http://old.invalid:9\n")

    def test_bracketed_ipv6_default_and_explicit_ports(self):
        for url, expected in [("http://[::1]", "::1 80"),
                              ("https://[::1]:8118", "::1 8118")]:
            r = self.shell('proxy_validate "$ICODEX_PROXY" && _proxy_host_port "$ICODEX_PROXY"', url)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(r.stdout.strip(), expected)


if __name__ == "__main__":
    unittest.main()
