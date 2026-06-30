#!/usr/bin/env python3
"""Codex PreToolUse hook that blocks secret-looking content.

Claude's original hook rewrote tool input with toolInputOverride. Codex does
not document that stdout protocol, so this port blocks instead of mutating.
"""

from __future__ import annotations

import json
import re
import sys


SECRET_PATTERNS = (
    (re.compile(r"\bsk-(?:ant-api03-|ant-|proj-|or-v1-)?[A-Za-z0-9\-_]{20,}"), "API key"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS access key id"),
    (
        re.compile(
            r"(?i)(aws[_\-]?secret[_\-]?(?:access[_\-]?)?key|AWS_SECRET_ACCESS_KEY)"
            r"\s*[=:]\s*[\"']?[A-Za-z0-9/+]{40}[\"']?"
        ),
        "AWS secret key",
    ),
    (
        re.compile(
            r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?:-----| BLOCK-----)"
            r"[\s\S]*?"
            r"-----END (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?:-----| BLOCK-----)"
        ),
        "private key",
    ),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{36,}\b"), "GitHub token"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{40,}\b"), "GitHub fine-grained token"),
    (re.compile(r"\bglpat-[A-Za-z0-9_\-]{20,}\b"), "GitLab token"),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{20,}\b"), "Slack token"),
    (re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b"), "Google API key"),
)

CONTENT_FIELDS = {
    "Bash": ("command", "cmd"),
    "Shell": ("command", "cmd"),
    "apply_patch": ("patch", "input", "content", "text"),
    "Edit": ("old_string", "new_string", "content", "patch", "input", "text"),
    "Write": ("content", "patch", "input", "text"),
}

EXCLUDE_DIRS = (
    ".codex-isolated/hooks",
    ".codex/hooks",
    ".claude-isolated/hooks",
    ".claude/hooks",
)


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


def is_excluded_path(path):
    normalized = str(path).replace("\\", "/")
    return any(part in normalized for part in EXCLUDE_DIRS)


def collect_text(tool, params):
    if isinstance(params, str):
        return [params]
    if not isinstance(params, dict):
        return []

    file_path = params.get("file_path") or params.get("path")
    if file_path and is_excluded_path(file_path):
        return []

    fields = CONTENT_FIELDS.get(tool, ())
    texts = []
    for field in fields:
        value = params.get(field)
        if isinstance(value, str):
            texts.append(value)

    edits = params.get("edits")
    if isinstance(edits, list):
        for edit in edits:
            if isinstance(edit, dict):
                for field in ("old_string", "new_string", "content", "text"):
                    value = edit.get(field)
                    if isinstance(value, str):
                        texts.append(value)

    return texts


def find_secret(texts):
    for text in texts:
        for regex, label in SECRET_PATTERNS:
            if regex.search(text):
                return label
    return ""


def main():
    data = load_payload()
    tool = tool_name(data)
    params = tool_input(data)

    label = find_secret(collect_text(tool, params))
    if not label:
        sys.exit(0)

    reason = "secret content blocked: %s detected in %s input" % (label, tool or "tool")
    print(reason, file=sys.stderr)
    print(json.dumps({"reason": reason}))
    sys.exit(2)


if __name__ == "__main__":
    main()
