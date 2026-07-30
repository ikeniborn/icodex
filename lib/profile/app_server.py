#!/usr/bin/env python3
"""Synchronous newline-delimited client for the Codex App Server."""

from __future__ import annotations

import json
import subprocess
import threading
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import TextIO


class AppServerError(Exception):
    pass


class AppServerClient:
    def __init__(self, command: list[str], cwd: Path, env: Mapping[str, str] | None = None):
        self.command = list(command)
        self.cwd = cwd
        self.next_request_id = 1
        try:
            self.process = subprocess.Popen(
                self.command,
                cwd=self.cwd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                bufsize=1,
                env=dict(env) if env is not None else None,
            )
        except OSError as exc:
            raise AppServerError(f"cannot start App Server: {exc}") from exc
        if self.process.stdin is None or self.process.stdout is None or self.process.stderr is None:
            self.close()
            raise AppServerError("App Server pipes are unavailable")
        self.stdin: TextIO = self.process.stdin
        self.stdout: TextIO = self.process.stdout
        self._stderr: list[str] = []
        self._stderr_thread = threading.Thread(target=self._capture_stderr, daemon=True)
        self._stderr_thread.start()

    def _capture_stderr(self) -> None:
        assert self.process.stderr is not None
        for chunk in self.process.stderr:
            self._stderr.append(chunk)

    def _error_detail(self) -> str:
        detail = "".join(self._stderr).strip()
        return f": {detail}" if detail else ""

    def _send(self, message: dict[str, object]) -> None:
        try:
            self.stdin.write(json.dumps(message, sort_keys=True, separators=(",", ":")) + "\n")
            self.stdin.flush()
        except (BrokenPipeError, OSError) as exc:
            raise AppServerError(f"cannot write App Server request{self._error_detail()}") from exc

    def _read_message(self) -> dict[str, object]:
        try:
            line = self.stdout.readline()
        except OSError as exc:
            raise AppServerError(f"cannot read App Server response{self._error_detail()}") from exc
        if not line:
            self._stderr_thread.join(timeout=0.2)
            raise AppServerError(f"App Server exited before a complete response{self._error_detail()}")
        try:
            message = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AppServerError("App Server emitted malformed JSON") from exc
        if not isinstance(message, dict):
            raise AppServerError("App Server message must be an object")
        return message

    @staticmethod
    def _validate_notification(message: dict[str, object]) -> tuple[str, dict[str, object]]:
        if set(message) != {"method", "params"}:
            raise AppServerError("App Server notification has an invalid shape")
        method = message.get("method")
        params = message.get("params")
        if not isinstance(method, str) or not method or not isinstance(params, dict):
            raise AppServerError("App Server notification has invalid method or params")
        return method, params

    def notify(self, method: str, params: dict[str, object]) -> None:
        if not isinstance(method, str) or not method or not isinstance(params, dict):
            raise AppServerError("invalid App Server notification")
        self._send({"method": method, "params": params})

    def request(
        self,
        method: str,
        params: dict[str, object],
        before_send: Callable[[int, dict[str, object]], None] | None = None,
    ) -> dict[str, object]:
        """Allocate an ID, persist correlation, flush one request, and return its result."""
        if not isinstance(method, str) or not method or not isinstance(params, dict):
            raise AppServerError("invalid App Server request")
        request_id = self.next_request_id
        self.next_request_id += 1
        request: dict[str, object] = {"method": method, "id": request_id, "params": params}
        if before_send is not None:
            before_send(request_id, request)
        self._send(request)
        while True:
            message = self._read_message()
            if "id" not in message:
                self._validate_notification(message)
                continue
            if message.get("id") != request_id:
                raise AppServerError("App Server response ID does not match the request")
            if set(message) == {"id", "result"} and isinstance(message.get("result"), dict):
                return message["result"]  # type: ignore[return-value]
            if set(message) == {"id", "error"} and isinstance(message.get("error"), dict):
                error = message["error"]
                detail = error.get("message") if isinstance(error.get("message"), str) else "unknown error"
                raise AppServerError(
                    f"App Server request {method} failed: {detail}{self._error_detail()}"
                )
            raise AppServerError("App Server response has an invalid shape")

    def wait_for_turn(self, turn_id: str) -> dict[str, object]:
        """Consume validated notifications until the requested turn is terminal."""
        if not isinstance(turn_id, str) or not turn_id:
            raise AppServerError("turn ID must be a non-empty string")
        while True:
            message = self._read_message()
            if "id" in message:
                raise AppServerError("unexpected App Server response while waiting for a turn")
            method, params = self._validate_notification(message)
            if method != "turn/completed":
                continue
            turn = params.get("turn")
            if not isinstance(turn, dict):
                raise AppServerError("turn/completed must contain a turn object")
            notified_id = turn.get("id")
            status = turn.get("status")
            if not isinstance(notified_id, str) or not isinstance(status, str):
                raise AppServerError("turn/completed has invalid terminal fields")
            if notified_id != turn_id:
                continue
            if status not in {"completed", "interrupted", "failed"}:
                raise AppServerError("turn/completed has a non-terminal status")
            return turn

    def close(self) -> None:
        process = getattr(self, "process", None)
        if process is None:
            return
        try:
            if process.stdin is not None and not process.stdin.closed:
                process.stdin.close()
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=1)
        finally:
            thread = getattr(self, "_stderr_thread", None)
            if thread is not None:
                thread.join(timeout=0.2)

    def __enter__(self) -> "AppServerClient":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()
