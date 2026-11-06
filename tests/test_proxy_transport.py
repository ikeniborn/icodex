"""Real CONNECT and TLS transport acceptance; no public service is contacted."""
import base64
import http.server
import os
from pathlib import Path
import shutil
import socket
import socketserver
import ssl
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Target(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.requests.append(self.path)
        body = b"proxy-transport-ok"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class Connect(socketserver.StreamRequestHandler):
    def handle(self):
        self.connection.settimeout(4)
        try:
            line = self.rfile.readline()
            if not line:
                return
            headers = {}
            while line := self.rfile.readline():
                if line == b"\r\n":
                    break
                k, v = line.split(b":", 1)
                headers[k.lower()] = v.strip()
            self.server.attempts += 1
            if headers.get(b"proxy-authorization") != b"Basic " + base64.b64encode(b"test:secret"):
                self.wfile.write(b"HTTP/1.1 407 Denied\r\nContent-Length: 0\r\n\r\n")
                return
            with socket.create_connection(self.server.target, timeout=4) as remote:
                self.wfile.write(b"HTTP/1.1 200 Connection established\r\n\r\n")
                self.wfile.flush()

                def copy(src, dst):
                    try:
                        while data := src.recv(65536):
                            dst.sendall(data)
                    except OSError:
                        pass
                    try:
                        dst.shutdown(socket.SHUT_WR)
                    except OSError:
                        pass

                thread = threading.Thread(target=copy, args=(remote, self.connection), daemon=True)
                thread.start()
                copy(self.connection, remote)
                thread.join(5)
        except (OSError, ValueError):
            pass


class Proxy(socketserver.ThreadingTCPServer):
    daemon_threads = True

    def get_request(self):
        sock, addr = super().get_request()
        sock.settimeout(4)
        if self.tls:
            try:
                sock = self.tls.wrap_socket(sock, server_side=True)
                self.tls_connections += 1
            except OSError:
                sock.close()
                raise
        return sock, addr


@unittest.skipUnless(shutil.which("stunnel") or shutil.which("stunnel4"), "real stunnel unavailable")
class Transport(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.tmp = Path(cls.temp.name)
        cls.servers = []
        cls.threads = []
        for name, identity in [("valid", "localhost"), ("wrong", "wrong.invalid")]:
            subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                            "-keyout", str(cls.tmp / f"{name}.key"), "-out", str(cls.tmp / f"{name}.pem"),
                            "-days", "1", "-subj", f"/CN={identity}", "-addext", f"subjectAltName=DNS:{identity}"],
                           check=True, capture_output=True)
        subprocess.run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
                        "-keyout", str(cls.tmp / "expired.key"), "-out", str(cls.tmp / "expired.csr"),
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost"],
                       check=True, capture_output=True)
        subprocess.run(["openssl", "x509", "-req", "-in", str(cls.tmp / "expired.csr"),
                        "-signkey", str(cls.tmp / "expired.key"), "-out", str(cls.tmp / "expired.pem"),
                        "-days", "-1", "-copy_extensions", "copy"], check=True, capture_output=True)
        cls.ca = cls.tmp / "ca.pem"
        cls.ca.write_bytes((cls.tmp / "valid.pem").read_bytes() + (cls.tmp / "wrong.pem").read_bytes() + (cls.tmp / "expired.pem").read_bytes())
        cls.target = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Target)
        cls.target.socket = cls.context("valid").wrap_socket(cls.target.socket, server_side=True)
        cls.target.requests = []
        cls.start(cls.target)

    @classmethod
    def context(cls, name):
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cls.tmp / f"{name}.pem", cls.tmp / f"{name}.key")
        return ctx

    @classmethod
    def start(cls, server):
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        cls.servers.append(server)
        cls.threads.append(thread)
        return server

    @classmethod
    def tearDownClass(cls):
        for server in cls.servers:
            server.shutdown()
            server.server_close()
        for thread in cls.threads:
            thread.join(5)
        cls.temp.cleanup()

    def proxy(self, tls="valid"):
        server = Proxy(("127.0.0.1", 0), Connect)
        server.tls = self.context(tls) if tls else None
        server.target = self.target.server_address
        server.attempts = server.tls_connections = 0
        return self.start(server)

    def url(self, server):
        return f"{'https' if server.tls else 'http'}://test:secret@localhost:{server.server_address[1]}"

    def run_shell(self, urls, tail="", ca=None, setup=""):
        env = {"PATH": os.environ["PATH"], "ICODEX_PROXY": urls,
               "CURL_CA_BUNDLE": str(ca or self.ca), "SSL_CERT_FILE": str(ca or self.ca)}
        code = '''set -euo pipefail
source lib/core/logging.sh
source lib/config/ca_trust.sh
source lib/proxy/proxy.sh
source lib/proxy/stunnel.sh
trap proxy_cleanup EXIT
_proxy_probe_target() { printf '%s\\n' "https://localhost:TARGET_PORT/probe"; }
TEST_SETUP
proxy_ensure </dev/null
printf 'selected=%s\\n' "${ICODEX_PROXY_ACTIVE%%://*}"
curl -q --noproxy '' --silent --fail --max-time 5 "https://localhost:TARGET_PORT/model"
'''.replace("TARGET_PORT", str(self.target.server_port)).replace("TEST_SETUP", setup) + tail
        return subprocess.run(["bash", "-c", code], cwd=ROOT, env=env, text=True, capture_output=True, timeout=25)

    def test_real_https_stunnel(self):
        server = self.proxy()
        result = self.run_shell(self.url(server))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("proxy-transport-ok", result.stdout)
        self.assertGreaterEqual(server.tls_connections, 2)
        self.assertGreaterEqual(server.attempts, 2)

    def test_two_candidates_first_closed_second_https(self):
        server = self.proxy()
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            closed = sock.getsockname()[1]
        result = self.run_shell(f"http://localhost:{closed}," + self.url(server))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("selected proxy candidate 2", result.stderr)
        self.assertIn("proxy-transport-ok", result.stdout)

    def test_wrong_identity_rejected_then_http_selected(self):
        wrong, good = self.proxy("wrong"), self.proxy(None)
        result = self.run_shell(self.url(wrong) + "," + self.url(good))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(wrong.attempts, 0)
        self.assertIn("selected proxy candidate 2", result.stderr)
        self.assertIn("proxy-transport-ok", result.stdout)

    def test_first_success_does_not_probe_second(self):
        first, second = self.proxy(None), self.proxy()
        result = self.run_shell(self.url(first) + "," + self.url(second))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(second.attempts, 0)
        self.assertEqual(second.tls_connections, 0)

    def test_expired_certificate_rejected(self):
        server = self.proxy("expired")
        result = self.run_shell(self.url(server))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(server.attempts, 0)

    def test_bad_authentication_tries_next_without_leaking(self):
        first, second = self.proxy(), self.proxy()
        result = self.run_shell(self.url(first).replace(":secret@", ":wrong-secret@") + "," + self.url(second))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertGreaterEqual(first.attempts, 1)
        self.assertGreaterEqual(second.attempts, 2)
        self.assertNotIn("secret", result.stdout + result.stderr)

    def test_occupied_port_never_receives_credentials(self):
        server = self.proxy()
        with socket.socket() as occupied:
            for seed in range(30):
                port = int(subprocess.check_output(["bash", "-c", f"RANDOM={seed}; echo $((20000 + RANDOM))"]))
                try:
                    occupied.bind(("127.0.0.1", port))
                    break
                except OSError:
                    continue
            else:
                self.fail("No controlled collision port available")
            occupied.listen()
            occupied.settimeout(.1)
            result = self.run_shell(self.url(server), setup=f"RANDOM={seed}")
            self.assertEqual(result.returncode, 0, result.stderr)
            with self.assertRaises(socket.timeout): occupied.accept()

    def test_missing_stunnel_noninteractive_continues_to_http(self):
        server = self.proxy(None)
        result = self.run_shell("https://localhost:1,https://localhost:2," + self.url(server),
                                setup="proxy_stunnel_find() { return 1; }")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("selected proxy candidate 3", result.stderr)
        self.assertNotIn("Install stunnel using", result.stderr)
        self.assertIn("proxy-transport-ok", result.stdout)

    def test_concurrent_tunnels_and_cleanup(self):
        server = self.proxy()
        processes = []
        states = []
        try:
            for index in range(2):
                state = self.tmp / f"state-{index}"
                states.append(state)
                env = dict(os.environ, ICODEX_PROXY=self.url(server), SSL_CERT_FILE=str(self.ca),
                           CURL_CA_BUNDLE=str(self.ca), STATE=str(state))
                code = """set -euo pipefail
source lib/core/logging.sh
source lib/config/ca_trust.sh
source lib/proxy/proxy.sh
source lib/proxy/stunnel.sh
trap proxy_cleanup EXIT
trap 'exit 143' TERM
_proxy_probe_target() { echo https://localhost:TARGET_PORT/probe; }
proxy_ensure
printf '%s\n' "$ICODEX_STUNNEL_PID" "$ICODEX_STUNNEL_DIR" "$ICODEX_PROXY_ACTIVE" > "$STATE"
while :; do sleep .1; done
""".replace("TARGET_PORT", str(self.target.server_port))
                processes.append(subprocess.Popen(["bash", "-c", code], cwd=ROOT, env=env,
                                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE))
            import time
            for _ in range(150):
                if all(p.exists() for p in states): break
                time.sleep(.03)
            self.assertTrue(all(p.exists() for p in states))
            first, second = [p.read_text().splitlines() for p in states]
            self.assertNotEqual(first[2], second[2])
            self.assertEqual(Path(first[1]).stat().st_mode & 0o777, 0o700)
            self.assertEqual((Path(first[1]) / "client.conf").stat().st_mode & 0o777, 0o600)
            processes[0].terminate()
            processes[0].communicate(timeout=5)
            self.assertFalse(Path(first[1]).exists())
            with self.assertRaises(ProcessLookupError): os.kill(int(first[0]), 0)
            result = subprocess.run(["curl", "-q", "--config", "-", "--noproxy", "", "--silent", "--fail",
                                     "--max-time", "5", "--cacert", str(self.ca),
                                     f"https://localhost:{self.target.server_port}/still-alive"],
                                    input=f'proxy = "{second[2]}"\n', capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "proxy-transport-ok")
        finally:
            for process in processes:
                if process.poll() is None: process.terminate()
                process.communicate(timeout=5)
            for state in states:
                if state.exists():
                    self.assertFalse(Path(state.read_text().splitlines()[1]).exists())

    def test_untrusted_certificate_stops_without_plaintext_fallback(self):
        server = self.proxy()
        result = self.run_shell(self.url(server), ca=self.tmp / "wrong.pem")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(server.attempts, 0)
        self.assertNotIn("secret", result.stderr)
        self.assertNotIn("proxy-transport-ok", result.stdout)


if __name__ == "__main__":
    unittest.main()
