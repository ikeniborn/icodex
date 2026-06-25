#!/usr/bin/env bash
# Parse icodex flags; collect the rest as passthrough for codex.
ICODEX_CMD="run"
ICODEX_NO_PROXY=0
ICODEX_SET_PROXY=""
ICODEX_PASSTHROUGH=()

parse_args() {
  while (( $# )); do
    case "$1" in
      --proxy)
        if [[ -z "${2:-}" ]]; then log_error "--proxy requires a url"; return 1; fi
        ICODEX_SET_PROXY="$2"; shift 2 ;;
      --no-proxy) ICODEX_NO_PROXY=1; shift ;;
      --clear)    ICODEX_CMD="clear";   shift ;;
      --update)   ICODEX_CMD="update";  shift ;;
      --install)  ICODEX_CMD="install"; shift ;;
      --version)  ICODEX_CMD="version"; shift ;;
      --help|-h)  ICODEX_CMD="help";    shift ;;
      --)         shift; ICODEX_PASSTHROUGH+=("$@"); break ;;
      *)          ICODEX_PASSTHROUGH+=("$@"); break ;;
    esac
  done
}

print_help() {
  cat <<'EOF'
icodex — isolated wrapper for OpenAI Codex CLI

Usage: icodex [icodex-flags] [-- codex-args...]

icodex flags:
  --proxy <url>   Save proxy URL and route codex through it
  --no-proxy      Run without proxy (ignore saved value)
  --clear         Remove saved proxy config (.codex_config)
  --update        Update codex binary to latest, re-pin lockfile
  --install       Install codex binary per lockfile (no launch)
  --version       Print icodex + codex versions
  --help, -h      Show this help

Anything after the first non-flag (or after --) is passed to codex verbatim.
EOF
}
