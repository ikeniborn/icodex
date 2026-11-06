"""Exercise parent ownership with real child processes and controlled executables."""
import os
import pty
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
PREFIX = '''source lib/core/logging.sh
source lib/proxy/proxy.sh
source lib/proxy/stunnel.sh
source lib/launcher/launch.sh
source lib/profile/profile.sh
sleep 60 >/dev/null 2>&1 &
ICODEX_STUNNEL_PID=$!
owned=$ICODEX_STUNNEL_PID
trap proxy_cleanup EXIT
'''


class Lifecycle(unittest.TestCase):
    def tty_shell(self, code, reply):
        master, slave = pty.openpty()
        try:
            process = subprocess.Popen(["bash", "-c", code], cwd=ROOT, stdin=slave,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            os.write(master, reply.encode())
            out, err = process.communicate(timeout=12)
            return process.returncode, out, err
        finally:
            os.close(master)
            os.close(slave)

    def test_install_offer_accept_refuse_failure_and_once(self):
        for reply, install_ok, expected_calls, expected_ready in [
            ("yes\n", True, 1, True), ("n\n", True, 0, False),
            ("yes\n", False, 1, False), ("\n", True, 0, False),
        ]:
            with self.subTest(reply=reply, install_ok=install_ok), tempfile.TemporaryDirectory() as temp:
                code = """source lib/core/logging.sh
source lib/proxy/proxy.sh
source lib/proxy/stunnel.sh
proxy_stunnel_find() { [[ -f 'DIR/installed' ]]; }
_proxy_stunnel_install() { echo call >> 'DIR/calls'; INSTALL_RESULT; }
proxy_stunnel_require || true
proxy_stunnel_require || true
""".replace("DIR", temp).replace("INSTALL_RESULT", "touch 'DIR/installed'".replace("DIR", temp) if install_ok else "return 1")
                rc, out, err = self.tty_shell(code, reply)
                self.assertEqual(rc, 0, err)
                calls = Path(temp) / "calls"
                self.assertEqual(len(calls.read_text().splitlines()) if calls.exists() else 0, expected_calls)
                self.assertEqual((Path(temp) / "installed").exists(), expected_ready)
                self.assertEqual(err.count("Install stunnel using"), 1)

    def test_direct_fallback_requires_explicit_tty_consent(self):
        code = """source lib/core/logging.sh
source lib/proxy/proxy.sh
ICODEX_PROXY=http://unavailable:9
export HTTP_PROXY=http://inherited:8 ALL_PROXY=http://inherited:8
_proxy_probe() { return 1; }
proxy_ensure
rc=$?
printf 'rc=%s route=%s all=%s\n' "$rc" "${HTTP_PROXY:-}" "${ALL_PROXY:-}"
"""
        for reply, rc in [("yes\n", 0), ("n\n", 1), ("\n", 1), ("\x04", 1)]:
            _, out, err = self.tty_shell(code, reply)
            self.assertIn(f"rc={rc} route= all=", out)
        r = subprocess.run(["bash", "-c", code], cwd=ROOT, stdin=subprocess.DEVNULL,
                           text=True, capture_output=True, timeout=5)
        self.assertIn("rc=1 route= all=", r.stdout)

    def test_main_selects_before_network_and_cleans_on_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            env = dict(os.environ, STATE=temp)
            code = """source lib/core/logging.sh
source lib/command/args.sh
source lib/proxy/proxy.sh
source lib/proxy/stunnel.sh
eval "$(sed -n '/^main() {/,/^}/p' icodex.sh)"
ICODEX_CONFIG=/dev/null
for fn in load_config apply_api_key apply_iwiki_env require_tools ensure_ca_trust setup_shared_dirs; do
  eval "$fn() { :; }"
done
proxy_ensure() {
  sleep 60 >/dev/null 2>&1 &
  ICODEX_STUNNEL_PID=$!
  ICODEX_STUNNEL_DIR=$(mktemp -d)
  printf '%s\n' "$ICODEX_STUNNEL_PID" "$ICODEX_STUNNEL_DIR" > "$STATE/selected"
}
install_ensure() { test -f "$STATE/selected" || exit 55; echo download; return 1; }
main --install
"""
            result = subprocess.run(["bash", "-c", code], cwd=ROOT, env=env, text=True,
                                    capture_output=True, timeout=8)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("download", result.stdout)
            pid, directory = (Path(temp) / "selected").read_text().splitlines()
            self.assertFalse(Path(directory).exists())
            with self.assertRaises(ProcessLookupError): os.kill(int(pid), 0)

    def test_https_retains_parent_and_stdin(self):
        with tempfile.TemporaryDirectory() as temp:
            binary = Path(temp) / "codex"
            binary.write_text('#!/bin/bash\nread -r line\nprintf "input=%s\\n" "$line"\nexit 23\n')
            binary.chmod(0o700)
            env = dict(os.environ, ICODEX_BIN=str(binary), ICODEX_USE_PII_PROXY_RESOLVED="false")
            r = subprocess.run(["bash", "-c", PREFIX + '''launch_codex_with_optional_pii
rc=$?
if kill -0 "$owned" 2>/dev/null; then echo leaked; fi
printf 'exit=%s\\n' "$rc"
'''], cwd=ROOT, env=env, input="hello\n", text=True, capture_output=True, timeout=12)
            self.assertIn("input=hello", r.stdout)
            self.assertIn("exit=23", r.stdout)
            self.assertNotIn("leaked", r.stdout)

    def test_profile_cleanup_composes_tunnel(self):
        r = subprocess.run(["bash", "-c", PREFIX + '''run_profile_task() { read -r line; printf 'input=%s\\n' "$line"; return 17; }
ICODEX_CMD=profile-run-task
run_profile_dispatch
rc=$?
if kill -0 "$owned" 2>/dev/null; then echo leaked; fi
printf 'exit=%s\\n' "$rc"
'''], cwd=ROOT, input="profile\n", text=True, capture_output=True, timeout=12)
        self.assertIn("input=profile", r.stdout)
        self.assertIn("exit=17", r.stdout)
        self.assertNotIn("leaked", r.stdout)

    def test_signal_during_pii_start_does_not_launch_application(self):
        for mode in ("launch_codex_wrapped", "run_profile_dispatch"):
            code = PREFIX + """ICODEX_BIN=/usr/bin/printf
ICODEX_CMD=profile-run-task
ICODEX_USE_PII_PROXY_RESOLVED=true
PII_PROXY_ACTIVE_PORT=12345
start_pii_proxy_server() { kill -TERM $$; return 0; }
stop_pii_proxy_server() { :; }
run_profile_task() { echo UNEXPECTED_LAUNCH; }
MODE UNEXPECTED_LAUNCH
printf 'exit=%s\n' "$?"
""".replace("MODE", mode)
            r = subprocess.run(["bash", "-c", code], cwd=ROOT, text=True, capture_output=True, timeout=5)
            self.assertNotIn("UNEXPECTED_LAUNCH", r.stdout)
            self.assertIn("exit=143", r.stdout)

    def test_profile_signal_owns_actual_python_runner(self):
        with tempfile.TemporaryDirectory() as temp:
            fake, ready = Path(temp) / "python3", Path(temp) / "ready"
            fake.write_text('#!/usr/bin/python3\nimport os,time\nfrom pathlib import Path\nPath(os.environ["READY"]).write_text(str(os.getpid()))\nwhile True: time.sleep(.1)\n')
            fake.chmod(0o700)
            env = dict(os.environ, PATH=temp + ":" + os.environ["PATH"], READY=str(ready))
            code = PREFIX + """ICODEX_ROOT=/unused
ICODEX_PROJECT_ROOT=/unused
CODEX_HOME=/unused
ICODEX_SHARED_DIR=/unused
ICODEX_BIN=/unused
ICODEX_PROFILE_TOPIC=test
ICODEX_PROFILE_TASK=test
ICODEX_CMD=profile-run-task
run_profile_dispatch
exit $?
"""
            process = subprocess.Popen(["bash", "-c", code], cwd=ROOT, env=env,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                for _ in range(100):
                    if ready.exists(): break
                    time.sleep(.03)
                self.assertTrue(ready.exists())
                process.terminate()
                process.communicate(timeout=10)
                self.assertEqual(process.returncode, 143)
                with self.assertRaises(ProcessLookupError): os.kill(int(ready.read_text()), 0)
            finally:
                if ready.exists():
                    try: os.kill(int(ready.read_text()), signal.SIGKILL)
                    except ProcessLookupError: pass
                if process.poll() is None: process.kill()
                process.communicate()

    def test_termination_is_bounded_for_uncooperative_child(self):
        with tempfile.TemporaryDirectory() as temp:
            binary, ready = Path(temp) / "codex", Path(temp) / "ready"
            binary.write_text('#!/usr/bin/python3\nimport os,signal,time\nfrom pathlib import Path\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nPath(os.environ["READY"]).write_text(str(os.getpid()))\nwhile True: time.sleep(.1)\n')
            binary.chmod(0o700)
            env = dict(os.environ, ICODEX_BIN=str(binary), READY=str(ready))
            p = subprocess.Popen(["bash", "-c", PREFIX + 'launch_codex_with_optional_pii; exit $?'], cwd=ROOT, env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                for _ in range(100):
                    if ready.exists(): break
                    time.sleep(.03)
                self.assertTrue(ready.exists())
                p.send_signal(signal.SIGTERM)
                p.communicate(timeout=11)
                self.assertEqual(p.returncode, 143)
                with self.assertRaises(ProcessLookupError): os.kill(int(ready.read_text()), 0)
            finally:
                if ready.exists():
                    try: os.kill(int(ready.read_text()), signal.SIGKILL)
                    except ProcessLookupError: pass
                if p.poll() is None: p.kill()
                p.communicate()


if __name__ == '__main__': unittest.main()
