#!/usr/bin/env bash
# Read/write the flat, self-controlled pin file .codex-lockfile.json.
lockfile_get() { # <file> <key>
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 1
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" | head -1
}

lockfile_write() { # <file> <version> <asset> <sha256>
  local file="$1" version="$2" asset="$3" sha="$4"
  cat >"$file" <<EOF
{
  "version": "$version",
  "asset": "$asset",
  "sha256": "$sha"
}
EOF
}
