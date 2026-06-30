#!/usr/bin/env bash
# Refresh the upstream caveman SKILL.md reference snapshot. Manual, network-only.
# The curated block lives in .codex-isolated/caveman/agents-block.md and is
# hand-maintained from this snapshot (hybrid source: upstream rules, native hook).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/.codex-isolated/caveman/upstream-SKILL.md"
URL="https://raw.githubusercontent.com/JuliusBrussee/caveman/main/skills/caveman/SKILL.md"

proxy_args=()
[[ -n "${ICODEX_PROXY:-}" ]] && proxy_args+=("--proxy" "$ICODEX_PROXY")

mkdir -p "$(dirname "$DEST")"
echo "Fetching $URL"
curl -fsSL "${proxy_args[@]}" -o "$DEST" "$URL"
echo "Wrote $DEST"
echo "Now hand-update .codex-isolated/caveman/agents-block.md from this snapshot (keep it < 2 KiB)."
