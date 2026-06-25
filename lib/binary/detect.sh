#!/usr/bin/env bash
# Map host OS/arch -> GitHub release asset name. Env overrides aid testing.
detect_asset() {
  local s="${ICODEX_UNAME_S:-$(uname -s)}"
  local m="${ICODEX_UNAME_M:-$(uname -m)}"
  local os arch
  case "$s" in
    Linux)  os="unknown-linux-musl" ;;
    Darwin) os="apple-darwin" ;;
    *) log_error "unsupported OS: $s (supported: Linux, Darwin)"; return 1 ;;
  esac
  case "$m" in
    x86_64|amd64)  arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) log_error "unsupported arch: $m (supported: x86_64, aarch64)"; return 1 ;;
  esac
  printf 'codex-%s-%s.tar.gz\n' "$arch" "$os"
}
