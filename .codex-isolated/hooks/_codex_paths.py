#!/usr/bin/env python3
"""Shared Codex tool path extraction for the IDD hooks.

Codex's edit tool is `apply_patch` (its payload carries a `patch` string with
`*** Add/Update/Delete File:` headers), unlike Claude Code's `file_path`-keyed
Edit/Write. These helpers normalise both shapes to a list of touched paths.
Mirrors the predicate already used by block-secrets.py (kept separate so the
secret-guard is never imported for its side effects)."""

import re

PATCH_FILE_RE = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$")


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
    out = []
    for key in ("file_path", "path", "target_file", "target_path"):
        value = params.get(key)
        if isinstance(value, str):
            out.append(value)
    return out


def patch_paths(patch):
    out = []
    for line in (patch or "").splitlines():
        m = PATCH_FILE_RE.match(line)
        if m:
            out.append(m.group(1).strip())
    return out


def extract_paths(tool, params):
    """All filesystem paths a Write/Edit/apply_patch call touches."""
    paths = list(path_fields(params))
    if tool in ("apply_patch", "Write", "Edit"):
        paths.extend(patch_paths(patch_text_from_input(params)))
    # de-dup, preserve order
    seen, uniq = set(), []
    for p in paths:
        if p not in seen:
            seen.add(p); uniq.append(p)
    return uniq
