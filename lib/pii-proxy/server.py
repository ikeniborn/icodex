#!/usr/bin/env python3
from __future__ import annotations

import os
import re
from typing import Any

DEFAULT_MASK_TOKEN = os.environ.get("PII_PROXY_MASK_TOKEN", "REDACTED")
MASKING_LEVEL = os.environ.get("PII_PROXY_MASKING_LEVEL", "standard").strip().lower()

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
