#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/scripts/vendor-superpowers.sh"

make_source() { # <root> <marketplace> <version> <brainstorming-marker>
  local root="$1" marketplace="$2" version="$3" marker="$4"
  local cache="$root/$marketplace/superpowers/$version"
  mkdir -p "$cache/.codex-plugin" "$cache/.git" "$cache/skills/brainstorming" "$cache/skills/writing-plans"
  printf '{}\n' > "$cache/.codex-plugin/plugin.json"
  printf 'tmp/\n' > "$cache/.gitignore"
  printf '%s\n' "$marker" > "$cache/skills/brainstorming/SKILL.md"
  printf 'upstream writing plans\n' > "$cache/skills/writing-plans/SKILL.md"
}

tmp="$(mktemp -d)"
scratch="$tmp/scratch/plugins/cache"
dest="$tmp/dest/plugins/cache"
pin="$tmp/vendor/superpowers/pin"
patches="$tmp/vendor/superpowers/patches"
mkdir -p "$patches" "$(dirname "$pin")"
make_source "$scratch" openai-curated 11c74d6b "upstream brainstorming"

cat > "$patches/0001-brainstorming.patch" <<'PATCH'
diff --git a/skills/brainstorming/SKILL.md b/skills/brainstorming/SKILL.md
--- a/skills/brainstorming/SKILL.md
+++ b/skills/brainstorming/SKILL.md
@@ -1 +1,2 @@
 upstream brainstorming
+checked spec approval
PATCH
cat > "$patches/0002-writing-plans.patch" <<'PATCH'
diff --git a/skills/writing-plans/SKILL.md b/skills/writing-plans/SKILL.md
--- a/skills/writing-plans/SKILL.md
+++ b/skills/writing-plans/SKILL.md
@@ -1 +1,2 @@
 upstream writing plans
+checked plan approval
PATCH

code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" || code=$?
out="$dest/openai-curated/superpowers/11c74d6b"
assert_eq "staged publication succeeds" "0" "$code"
assert_exit "canonical path created" 0 test -f "$out/.codex-plugin/plugin.json"
assert_exit "nested git stripped" 1 test -d "$out/.git"
assert_eq "no nested gitignore remains" "0" "$(find "$out" -name .gitignore | wc -l | tr -d ' ')"
assert_contains "first ordered patch applied" "$(cat "$out/skills/brainstorming/SKILL.md")" "checked spec approval"
assert_contains "second ordered patch applied" "$(cat "$out/skills/writing-plans/SKILL.md")" "checked plan approval"
assert_eq "exact cache path published to pin" "openai-curated/superpowers/11c74d6b" "$(cat "$pin")"

# Re-vendor replaces drifted destination from clean source plus ordered patches.
printf 'local drift\n' >> "$out/skills/brainstorming/SKILL.md"
_vendor_publish "$scratch" "$dest" "$pin" "$patches"
assert_eq "re-vendor removes cache drift" $'upstream brainstorming\nchecked spec approval' "$(cat "$out/skills/brainstorming/SKILL.md")"

# Failed refresh preserves both previously published cache and pin.
before_tree="$(find "$dest" -type f -print0 | sort -z | xargs -0 sha256sum)"
before_pin="$(cat "$pin")"
sed -i 's/^ upstream brainstorming$/ conflicting upstream/' "$patches/0001-brainstorming.patch"
conflict_code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" >/dev/null 2>&1 || conflict_code=$?
assert_exit "conflicting patch fails" 1 test "$conflict_code" -eq 0
assert_eq "failed patch preserves destination" "$before_tree" "$(find "$dest" -type f -print0 | sort -z | xargs -0 sha256sum)"
assert_eq "failed patch preserves pin" "$before_pin" "$(cat "$pin")"
sed -i 's/^ conflicting upstream$/ upstream brainstorming/' "$patches/0001-brainstorming.patch"

rm -rf "$scratch"/*
missing_code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" >/dev/null 2>&1 || missing_code=$?
assert_exit "zero source caches rejected" 1 test "$missing_code" -eq 0
assert_eq "zero source preserves destination" "$before_tree" "$(find "$dest" -type f -print0 | sort -z | xargs -0 sha256sum)"

make_source "$scratch" openai-curated 11c74d6b "upstream brainstorming"
make_source "$scratch" second-market 22aa44bb "upstream brainstorming"
ambiguous_code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" >/dev/null 2>&1 || ambiguous_code=$?
assert_exit "multiple source caches rejected" 1 test "$ambiguous_code" -eq 0
assert_eq "ambiguity preserves pin" "$before_pin" "$(cat "$pin")"

# Committed materialization must be byte-identical to clean upstream plus patches.
clean="$tmp/clean/openai-curated/superpowers/11c74d6b"
mkdir -p "$clean/skills/brainstorming" "$clean/skills/writing-plans"
committed="$ROOT/.codex-isolated/plugins/cache/$(cat "$ROOT/vendor/superpowers/pin")"
cp "$committed/skills/brainstorming/SKILL.md" "$clean/skills/brainstorming/SKILL.md"
cp "$committed/skills/writing-plans/SKILL.md" "$clean/skills/writing-plans/SKILL.md"
mapfile -t reverse_overlays < <(find "$ROOT/vendor/superpowers/patches" -maxdepth 1 -type f -name '*.patch' -print | sort -r)
for overlay in "${reverse_overlays[@]}"; do
  patch --batch --reverse --fuzz=0 -d "$clean" -p1 < "$overlay" >/dev/null
done
for overlay in "$ROOT"/vendor/superpowers/patches/*.patch; do
  patch --batch --forward --fuzz=0 -d "$clean" -p1 < "$overlay" >/dev/null
done
assert_exit "brainstorming materialization matches patches" 0 cmp -s "$clean/skills/brainstorming/SKILL.md" "$committed/skills/brainstorming/SKILL.md"
assert_exit "writing-plans materialization matches patches" 0 cmp -s "$clean/skills/writing-plans/SKILL.md" "$committed/skills/writing-plans/SKILL.md"

rm -rf "$tmp"
finish
