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


def heredoc_operator_line(command):
    """Find shell heredoc syntax without evaluating input or literal data."""
    stack = [["shell", 0, False]]
    word_ends = set()
    i = 0
    while i < len(command):
        mode, depth, word = stack[-1]
        char = command[i]
        if mode == "single":
            if char == "'":
                stack.pop()
            i += 1
            continue
        if char == "\\":
            # In double quotes only these characters can be escaped.
            if mode != "double" or (i + 1 < len(command) and command[i + 1] in '$`"\\\n'):
                boundary_before = i == 0 or (i - 1 not in word_ends and (
                    command[i - 1].isspace() or command[i - 1] in ';|&()'))
                if i + 1 < len(command) and (command[i + 1] != '\n' or not boundary_before):
                    word_ends.add(i + 1)
                i += 2
                continue
        if mode == "double" and char == '"':
            stack.pop()
            i += 1
            continue
        if mode == "backtick" and char == '`':
            stack.pop()
            i += 1
            continue
        if command.startswith("$((", i):
            stack.append(["arithmetic", 2, True])
            i += 3
            continue
        if command.startswith("$(", i):
            stack.append(["shell", 1, True])
            i += 2
            continue
        if char == '`':
            stack.append(["backtick", 0, True])
            i += 1
            continue
        if mode == "double":
            i += 1
            continue
        if char in "'\"":
            stack.append(["single" if char == "'" else "double", 0, False])
            i += 1
            continue
        boundary = i == 0 or (i - 1 not in word_ends and (
            command[i - 1].isspace() or command[i - 1] in ';|&()'))
        if mode != "arithmetic" and char == '#' and boundary:
            newline = command.find('\n', i)
            i = len(command) if newline == -1 else newline + 1
            continue
        prefix = command[:i].rstrip(' \t')
        command_start = not prefix or prefix[-1] in ';\n|&('
        if mode != "arithmetic" and command.startswith('((', i) and command_start:
            stack.append(["arithmetic", 2, False])
            i += 2
            continue
        if mode != "arithmetic":
            if command.startswith('<<<', i):
                i += 3
                continue
            if command.startswith('<<', i):
                return command.count('\n', 0, i) + 1
        if char == '(' and (depth or mode == "arithmetic"):
            stack[-1][1] += 1
        elif char == ')' and depth:
            stack[-1][1] -= 1
            if stack[-1][1] == 0:
                stack.pop()
                if word:
                    word_ends.add(i)
        i += 1
    if len(stack) > 1 and '<<' in command:
        return 1  # Unclosed quoting/nesting cannot establish a literal region.
    return None


def classify_heredoc(command):
    """Return kind, literal destination, denial category, and safe line locator."""
    header, separator, body = command.partition('\n')
    path = r'''(?P<destination>[A-Za-z0-9_./-]+|'[A-Za-z0-9_./ -]+'|"[A-Za-z0-9_./ -]+")'''
    output = r'>>?[ \t]*' + path
    heredoc = r'''<<[ \t]*(?P<quote>['"])(?P<delimiter>[A-Za-z_][A-Za-z0-9_]*)(?P=quote)'''
    for redirections in (output + r'[ \t]*' + heredoc, heredoc + r'[ \t]*' + output):
        match = re.fullmatch(r'[ \t]*(?:cat|/bin/cat|/usr/bin/cat)[ \t]+' + redirections + r'[ \t]*', header)
        if not match:
            continue
        lines = body.split('\n') if separator else []
        delimiter = match.group('delimiter')
        for index, line in enumerate(lines):
            if line == delimiter:
                if ''.join(lines[index + 1:]).strip():
                    return 'deny', None, 'ambiguous_heredoc', index + 3
                destination = match.group('destination')
                if destination[0] in "'\"":
                    destination = destination[1:-1]
                return 'literal_write', destination, None, 1
        return 'deny', None, 'unterminated_heredoc', 1
    line = heredoc_operator_line(command)
    if line is not None:
        return 'deny', None, 'ambiguous_heredoc', line
    return 'none', None, None, 1


def patch_paths(patch):
    paths = []
    for line in patch.splitlines():
        match = PATCH_FILE_RE.match(line)
        if match:
            paths.append(match.group(1).strip())
    return paths


def deny(category, locator, rule=None):
    actions = {
        'protected_path': 'Use a non-sensitive target.',
        'ambiguous_heredoc': 'Use the documented single-cat literal-write form.',
        'unterminated_heredoc': 'Close the quoted delimiter on its own line.',
    }
    reason = 'block-secrets.py: %s; source=%s' % (category, locator)
    if rule:
        reason += '; rule=' + rule
    reason += '. ' + actions[category]
    print(reason, file=sys.stderr)
    print(json.dumps({"reason": reason}))
    sys.exit(2)


def main():
    data = load_payload()
    tool = tool_name(data)
    params = tool_input(data)
    paths = []

    if tool in {"Bash", "Shell"}:
        command = command_from_input(params)
        kind, destination, category, line = classify_heredoc(command)
        if kind == 'deny':
            deny(category, 'command line %d' % line)
        paths.extend([destination] if kind == 'literal_write' else command_path_tokens(command))
    elif tool in {"apply_patch", "Edit", "Write", "Read"}:
        paths.extend(path_fields(params))
        paths.extend(patch_paths(patch_text_from_input(params)))
    else:
        paths.extend(path_fields(params))

    for index, path in enumerate(paths, 1):
        blocked, pattern = is_sensitive_path(path)
        if blocked:
            deny('protected_path', 'path candidate %d' % index, pattern)

    sys.exit(0)


if __name__ == "__main__":
    main()
