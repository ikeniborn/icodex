#!/usr/bin/env bash
# Logging helpers. All output to stderr so stdout stays clean for data.
log_info()  { printf '\033[0;34m[icodex]\033[0m %s\n'       "$*" >&2; }
log_warn()  { printf '\033[0;33m[icodex] WARN:\033[0m %s\n'  "$*" >&2; }
log_error() { printf '\033[0;31m[icodex] ERROR:\033[0m %s\n' "$*" >&2; }
