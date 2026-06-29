#!/usr/bin/env bash
# Parse icodex flags; collect the rest as passthrough for codex.
ICODEX_CMD="run"
ICODEX_DISABLE_PROXY=0
ICODEX_SET_PROXY=""
ICODEX_PASSTHROUGH=()
ICODEX_FULL_ACCESS=0

parse_args() {
  while (( $# )); do
    case "$1" in
      --proxy)
        if [[ -z "${2:-}" ]]; then log_error "--proxy requires a url"; return 1; fi
        ICODEX_SET_PROXY="$2"; shift 2 ;;
      --no-proxy) ICODEX_DISABLE_PROXY=1; shift ;;
      --full-access) ICODEX_FULL_ACCESS=1; shift ;;
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
  --proxy <url>   Save ICODEX_PROXY to .codex_config and route codex through it
  --no-proxy      Disable the proxy for this run (ICODEX_NO_PROXY is the host
                  bypass list, NOT a disable switch)
  --full-access   Escalate sandbox to danger-full-access for this run (prints a warning)
  --clear         Remove the saved config file (.codex_config)
  --update        Update codex binary to latest, re-pin lockfile
  --install       Install codex binary per lockfile (no launch)
  --version       Print icodex + codex versions
  --help, -h      Show this help

Persistent settings: copy .codex_config.example to .codex_config (ICODEX_* keys).
  ICODEX_MODE selects a run profile: ro | safe | full-ask (default) | full-auto.
Precedence: defaults < .codex_config < flags.
Anything after the first non-flag (or after --) is passed to codex verbatim.
EOF
}
