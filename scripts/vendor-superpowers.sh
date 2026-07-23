#!/usr/bin/env bash
# Maintainer tool: regenerate the committed Superpowers plugin cache.
#
#   ./scripts/vendor-superpowers.sh <sha>
#
# Installs Superpowers into a scratch CODEX_HOME via the real `codex plugin`
# commands, then normalizes the produced cache into the repo at the canonical
# path named by vendor/superpowers/pin (git-tracked).
# "Install once on one machine -> deliver via git."
set -euo pipefail
VENDOR_ROOT="${VENDOR_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

_vendor_validate_manifest() { # <plugin.json>
  python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)
if not isinstance(manifest, dict) or manifest.get("name") != "superpowers":
    raise SystemExit(1)
PY
}

_vendor_validate_overlay() { # <stage>
  local stage="$1" brainstorming writing
  brainstorming="$stage/skills/brainstorming/SKILL.md"
  writing="$stage/skills/writing-plans/SKILL.md"
  [[ -f "$brainstorming" && -f "$writing" ]] || return 1
  grep -qF 'Run `$check-chain spec <path>`' "$brainstorming" &&
    grep -qF 'provisional design-section feedback' "$brainstorming" &&
    grep -qF 'commit the spec document once' "$brainstorming" &&
    grep -qF 'Run `$check-chain plan <path>`' "$writing" &&
    grep -qF 'Commit the approved plan' "$writing" &&
    grep -qF 'offer execution choice' "$writing"
}

_vendor_publish() { # <source-cache-root> <dest-cache-root> <pin> <patch-dir> <source-ref>
  local source_root="$1" dest_root="$2" pin="$3" patch_dir="$4" source_ref="$5"
  local -a sources overlays
  local source rel destination parent stage pin_stage overlay

  [[ "$source_ref" =~ ^[0-9a-f]{7,64}$ ]] || { log_error "source ref must be an immutable hexadecimal revision"; return 1; }

  mapfile -t sources < <(find "$source_root" -mindepth 3 -maxdepth 3 -type d -path '*/superpowers/*' -exec test -f '{}/.codex-plugin/plugin.json' \; -print | sort)
  [[ "${#sources[@]}" -eq 1 ]] || { log_error "expected exactly one Superpowers source cache, found ${#sources[@]}"; return 1; }
  source="${sources[0]}"
  rel="${source#"$source_root"/}"
  [[ "$rel" =~ ^[A-Za-z0-9._-]+/superpowers/[A-Za-z0-9._-]+$ ]] || { log_error "invalid source cache identity: $rel"; return 1; }

  mapfile -t overlays < <(find "$patch_dir" -maxdepth 1 -type f -name '*.patch' -print | sort)
  [[ "${#overlays[@]}" -eq 2 && "$(basename "${overlays[0]}")" == "0001-brainstorming-check-chain.patch" && "$(basename "${overlays[1]}")" == "0002-writing-plans-check-chain.patch" ]] || {
    log_error "Superpowers overlay patch set must contain exactly the two mandatory ordered patches"
    return 1
  }

  destination="$dest_root/$rel"
  parent="$(dirname "$destination")"
  mkdir -p "$parent" "$(dirname "$pin")"
  stage="$(mktemp -d "$parent/.stage.XXXXXX")"
  pin_stage="$(mktemp "$(dirname "$pin")/.pin.XXXXXX")"
  trap 'rm -rf "$stage"; rm -f "$pin_stage"' RETURN

  rsync -a --delete "$source/" "$stage/"
  rm -rf "$stage/.git"
  find "$stage" -name .gitignore -delete
  for overlay in "${overlays[@]}"; do
    patch --batch --forward --fuzz=0 -d "$stage" -p1 < "$overlay" >/dev/null || {
      log_error "Superpowers overlay conflict: $(basename "$overlay")"
      return 1
    }
  done
  _vendor_validate_manifest "$stage/.codex-plugin/plugin.json" || { log_error "plugin manifest invalid after staging"; return 1; }
  _vendor_validate_overlay "$stage" || {
    log_error "validation-first semantic markers missing after staging"
    return 1
  }
  printf '%s\n' "$rel" > "$pin_stage"
  printf '{"status":"verified-immutable-source-ref","source_ref":"%s"}\n' "$source_ref" > "$stage/.icodex-vendor-provenance.json"

  if [[ -e "$destination" ]]; then
    diff -qr "$stage" "$destination" >/dev/null || { log_error "immutable generation conflict: $destination"; return 1; }
    rm -rf "$stage"
  else
    mv "$stage" "$destination"
  fi
  mv "$pin_stage" "$pin"
  trap - RETURN
}

# Network wrapper — only runs when executed directly, never when sourced by tests.
_vendor_main() (
  local sha="${1:?usage: vendor-superpowers.sh <immutable-sha>}"
  [[ "$sha" =~ ^[0-9a-f]{7,64}$ ]] || { log_error "source ref must be an immutable hexadecimal revision"; return 1; }
  local bin="$VENDOR_ROOT/.codex-isolated/bin/codex"
  [[ -x "$bin" ]] || { log_error "codex binary missing — run ./icodex.sh --install"; return 1; }
  local scratch; scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  CODEX_HOME="$scratch" "$bin" plugin marketplace add obra/superpowers --ref "$sha" >&2
  local mkt; mkt="$(grep -oE '\[marketplaces\.[^]]+\]' "$scratch/config.toml" | head -1 | sed -E 's/\[marketplaces\.(.+)\]/\1/')"
  [[ -n "$mkt" ]] || { log_error "could not determine marketplace name from $scratch/config.toml"; return 1; }
  CODEX_HOME="$scratch" "$bin" plugin add "superpowers@$mkt" >&2
  _vendor_publish "$scratch/plugins/cache" "$VENDOR_ROOT/.codex-isolated/plugins/cache" \
    "$VENDOR_ROOT/vendor/superpowers/pin" "$VENDOR_ROOT/vendor/superpowers/patches" "$sha"
  log_info "vendored pinned Superpowers cache with ordered zero-fuzz overlays"
)

# Run the wrapper only on direct execution (so tests can source the file safely).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # shellcheck source=/dev/null
  source "$VENDOR_ROOT/lib/core/logging.sh"
  _vendor_main "$@"
fi
