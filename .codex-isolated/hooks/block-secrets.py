#!/usr/bin/env python3
"""Codex PreToolUse hook that blocks access to sensitive paths.

The script is intentionally fail-open for malformed hook payloads, and
fail-closed when a requested path matches a known secret-bearing location.
"""

import json
import os
import re
import shlex
import sys


EXCLUDE_DIRS = (
    ".codex-isolated/hooks",
    ".codex/hooks",
    ".claude-isolated/hooks",
    ".claude/hooks",
)

SAFE_SUFFIXES = (
    ".example",
    ".sample",
    ".template",
    ".dist",
    ".defaults",
    ".placeholder",
)

SENSITIVE_PATH_PATTERNS = (
    ".env",
    ".pem",
    ".key",
    ".pfx",
    ".p12",
    "credentials",
    "secret",
    ".ssh",
    ".aws",
    ".gnupg",
    ".kube",
    "id_rsa",
    "id_ed25519",
    "id_ecdsa",
    "private_key",
    ".netrc",
    ".pgpass",
)

TOKEN_FILENAME_PATTERNS = (
    ".token",
    "token.json",
    "token.txt",
    "token.yaml",
    "token.yml",
    "token.xml",
    "access_token",
    "refresh_token",
    "oauth_token",
    "auth_token",
)

PATCH_FILE_RE = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$")


def load_payload():
    try:
        raw = sys.stdin.read()
        return json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, TypeError, ValueError):
        return {}


def tool_name(data):
    return str(data.get("tool_name") or data.get("tool") or data.get("name") or "")


def tool_input(data):
    value = data.get("tool_input", data.get("input", data.get("arguments", {})))
    return value if value is not None else {}


def is_excluded(path):
    normalized = path.replace("\\", "/")
    return any(part in normalized for part in EXCLUDE_DIRS)


def is_safe_template(path):
    base = os.path.basename(path).lower()
    return base == ".envrc" or any(base.endswith(suffix) for suffix in SAFE_SUFFIXES)


def is_sensitive_path(path):
    if not path or is_excluded(path) or is_safe_template(path):
        return False, ""

    lower = path.lower()
    filename = os.path.basename(lower)

    for pattern in TOKEN_FILENAME_PATTERNS:
        if filename == pattern or filename.startswith(pattern + "."):
            return True, pattern

    for pattern in SENSITIVE_PATH_PATTERNS:
        if pattern in lower:
            return True, pattern

    return False, ""


def command_from_input(params):
    if isinstance(params, str):
        return params
    if not isinstance(params, dict):
        return ""
    return str(params.get("command") or params.get("cmd") or "")


def patch_text_from_input(params):
    if isinstance(params, str):
        return params
    if not isinstance(params, dict):
        return ""
    for key in ("patch", "input", "content", "text"):
        value = params.get(key)
        if isinstance(value, str):
            return value
    return ""


def path_fields(params):
    if not isinstance(params, dict):
        return []
    paths = []
    for key in ("file_path", "path", "target_file", "target_path"):
        value = params.get(key)
        if isinstance(value, str):
            paths.append(value)
    return paths


def command_path_tokens(command):
    if not command:
        return []
    try:
        tokens = shlex.split(command)
    except ValueError:
        tokens = command.split()

    prefixes = ("/", "~/", "./", "../", "$HOME")
    return [token for token in tokens if token.startswith(prefixes) or token.startswith(".env")]


def patch_paths(patch):
    paths = []
    for line in patch.splitlines():
        match = PATCH_FILE_RE.match(line)
        if match:
            paths.append(match.group(1).strip())
    return paths


def block(path, pattern):
    reason = "sensitive path blocked: %s matched %s" % (path, pattern)
    print(reason, file=sys.stderr)
    print(json.dumps({"reason": reason}))
    sys.exit(2)


def main():
    data = load_payload()
    tool = tool_name(data)
    params = tool_input(data)
    paths = []

    if tool in {"Bash", "Shell"}:
        paths.extend(command_path_tokens(command_from_input(params)))
    elif tool in {"apply_patch", "Edit", "Write", "Read"}:
        paths.extend(path_fields(params))
        paths.extend(patch_paths(patch_text_from_input(params)))
    else:
        paths.extend(path_fields(params))

    for path in paths:
        blocked, pattern = is_sensitive_path(path)
        if blocked:
            block(path, pattern)

    sys.exit(0)


if __name__ == "__main__":
    main()
