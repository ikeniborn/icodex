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
  printf '{"name":"superpowers"}\n' > "$cache/.codex-plugin/plugin.json"
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

cat > "$patches/0001-brainstorming-check-chain.patch" <<'PATCH'
diff --git a/skills/brainstorming/SKILL.md b/skills/brainstorming/SKILL.md
--- a/skills/brainstorming/SKILL.md
+++ b/skills/brainstorming/SKILL.md
@@ -1 +1,4 @@
 upstream brainstorming
+Run `$check-chain spec <path>`
+provisional design-section feedback
+commit the spec document once
PATCH
cat > "$patches/0002-writing-plans-check-chain.patch" <<'PATCH'
diff --git a/skills/writing-plans/SKILL.md b/skills/writing-plans/SKILL.md
--- a/skills/writing-plans/SKILL.md
+++ b/skills/writing-plans/SKILL.md
@@ -1 +1,4 @@
 upstream writing plans
+Run `$check-chain plan <path>`
+Commit the approved plan
+offer execution choice
PATCH

code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" "deadbeef" || code=$?
out="$dest/openai-curated/superpowers/11c74d6b"
assert_eq "staged publication succeeds" "0" "$code"
assert_exit "canonical path created" 0 test -f "$out/.codex-plugin/plugin.json"
assert_exit "nested git stripped" 1 test -d "$out/.git"
assert_eq "no nested gitignore remains" "0" "$(find "$out" -name .gitignore | wc -l | tr -d ' ')"
assert_contains "first ordered patch applied" "$(cat "$out/skills/brainstorming/SKILL.md")" 'Run `$check-chain spec <path>`'
assert_contains "second ordered patch applied" "$(cat "$out/skills/writing-plans/SKILL.md")" 'Run `$check-chain plan <path>`'
assert_eq "exact cache path published to pin" "openai-curated/superpowers/11c74d6b" "$(cat "$pin")"
assert_contains "verified provenance stored in generation" "$(cat "$out/.icodex-vendor-provenance.json")" '"status":"verified-immutable-source-ref"'
assert_contains "source ref stored in generation" "$(cat "$out/.icodex-vendor-provenance.json")" '"source_ref":"deadbeef"'
assert_exit "no separately published source ref" 1 test -e "$tmp/vendor/superpowers/source-ref"

# Same immutable generation is an exact no-op; conflicting content is rejected.
before_tree="$(find "$out" -type f -print0 | sort -z | xargs -0 sha256sum)"
_vendor_publish "$scratch" "$dest" "$pin" "$patches" "deadbeef"
assert_eq "identical generation is no-op" "$before_tree" "$(find "$out" -type f -print0 | sort -z | xargs -0 sha256sum)"
printf 'local drift\n' >> "$out/skills/brainstorming/SKILL.md"
drift_code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" "deadbeef" >/dev/null 2>&1 || drift_code=$?
assert_exit "existing generation conflict fails" 1 test "$drift_code" -eq 0
assert_contains "conflicting generation remains visible" "$(cat "$out/skills/brainstorming/SKILL.md")" "local drift"
sed -i '$d' "$out/skills/brainstorming/SKILL.md"

# Failed refresh preserves both previously published cache and pin.
before_tree="$(find "$dest" -type f -print0 | sort -z | xargs -0 sha256sum)"
before_pin="$(cat "$pin")"
sed -i 's/^ upstream brainstorming$/ conflicting upstream/' "$patches/0001-brainstorming-check-chain.patch"
conflict_code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" "deadbeef" >/dev/null 2>&1 || conflict_code=$?
assert_exit "conflicting patch fails" 1 test "$conflict_code" -eq 0
assert_eq "failed patch preserves destination" "$before_tree" "$(find "$dest" -type f -print0 | sort -z | xargs -0 sha256sum)"
assert_eq "failed patch preserves pin" "$before_pin" "$(cat "$pin")"
sed -i 's/^ conflicting upstream$/ upstream brainstorming/' "$patches/0001-brainstorming-check-chain.patch"

rm -rf "$scratch"/*
missing_code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" "deadbeef" >/dev/null 2>&1 || missing_code=$?
assert_exit "zero source caches rejected" 1 test "$missing_code" -eq 0
assert_eq "zero source preserves destination" "$before_tree" "$(find "$dest" -type f -print0 | sort -z | xargs -0 sha256sum)"

make_source "$scratch" openai-curated 11c74d6b "upstream brainstorming"
make_source "$scratch" second-market 22aa44bb "upstream brainstorming"
ambiguous_code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" "deadbeef" >/dev/null 2>&1 || ambiguous_code=$?
assert_exit "multiple source caches rejected" 1 test "$ambiguous_code" -eq 0
assert_eq "ambiguity preserves pin" "$before_pin" "$(cat "$pin")"

# Committed reconstructed baseline plus patches must reproduce materialized skills.
clean="$tmp/clean/openai-curated/superpowers/11c74d6b"
mkdir -p "$clean/skills/brainstorming" "$clean/skills/writing-plans"
committed="$ROOT/.codex-isolated/plugins/cache/$(cat "$ROOT/vendor/superpowers/pin")"
cp "$ROOT/vendor/superpowers/reconstructed-baseline/skills/brainstorming/SKILL.md" "$clean/skills/brainstorming/SKILL.md"
cp "$ROOT/vendor/superpowers/reconstructed-baseline/skills/writing-plans/SKILL.md" "$clean/skills/writing-plans/SKILL.md"
legacy_provenance="$(cat "$committed/.icodex-vendor-provenance.json")"
assert_contains "legacy provenance is explicitly unverified" "$legacy_provenance" '"status":"legacy-unverified-cache-generation"'
assert_contains "legacy provenance records cache generation" "$legacy_provenance" '"cache_generation":"11c74d6b"'
assert_contains "legacy provenance does not claim source ref" "$legacy_provenance" '"source_ref":null'
for overlay in "$ROOT"/vendor/superpowers/patches/*.patch; do
  patch --batch --forward --fuzz=0 -d "$clean" -p1 < "$overlay" >/dev/null
done
assert_exit "brainstorming materialization matches patches" 0 cmp -s "$clean/skills/brainstorming/SKILL.md" "$committed/skills/brainstorming/SKILL.md"
assert_exit "writing-plans materialization matches patches" 0 cmp -s "$clean/skills/writing-plans/SKILL.md" "$committed/skills/writing-plans/SKILL.md"

# Mandatory patch set, semantic markers, and strict plugin JSON fail before pin changes.
printf 'stable/pin/value\n' > "$pin"
rm -rf "$scratch"
make_source "$scratch" openai-curated 22aa44bb "upstream brainstorming"
cp "$patches/0002-writing-plans-check-chain.patch" "$tmp/0002-writing-plans-check-chain.patch"
rm -f "$patches/0002-writing-plans-check-chain.patch"
mandatory_code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" "deadbeef" >/dev/null 2>&1 || mandatory_code=$?
assert_exit "missing mandatory patch rejected" 1 test "$mandatory_code" -eq 0
assert_eq "missing patch preserves pin" "stable/pin/value" "$(cat "$pin")"
cp "$tmp/0002-writing-plans-check-chain.patch" "$patches/0002-writing-plans-check-chain.patch"
cp "$patches/0001-brainstorming-check-chain.patch" "$patches/0003-extra.patch"
extra_code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" "deadbeef" >/dev/null 2>&1 || extra_code=$?
assert_exit "unexpected patch rejected" 1 test "$extra_code" -eq 0
rm -f "$patches/0003-extra.patch"
sed -i 's/provisional design-section feedback/unchecked design feedback/' "$patches/0001-brainstorming-check-chain.patch"
semantic_code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" "deadbeef" >/dev/null 2>&1 || semantic_code=$?
assert_exit "missing semantic marker rejected" 1 test "$semantic_code" -eq 0
assert_eq "semantic failure preserves pin" "stable/pin/value" "$(cat "$pin")"
printf '{broken\n' > "$scratch/openai-curated/superpowers/22aa44bb/.codex-plugin/plugin.json"
manifest_code=0
_vendor_publish "$scratch" "$dest" "$pin" "$patches" "deadbeef" >/dev/null 2>&1 || manifest_code=$?
assert_exit "invalid plugin manifest rejected" 1 test "$manifest_code" -eq 0
assert_eq "manifest failure preserves pin" "stable/pin/value" "$(cat "$pin")"

# Direct wrapper always removes scratch space and persists its supplied ref.
wrapper_root="$tmp/wrapper-root"
wrapper_tmp="$tmp/wrapper-tmp"
mkdir -p "$wrapper_root/.codex-isolated/bin" "$wrapper_root/vendor/superpowers" "$wrapper_root/lib/core" "$wrapper_tmp"
cp -R "$ROOT/vendor/superpowers/patches" "$wrapper_root/vendor/superpowers/patches"
cp "$ROOT/lib/core/logging.sh" "$wrapper_root/lib/core/logging.sh"
cat > "$wrapper_root/.codex-isolated/bin/codex" <<'FAKE'
#!/usr/bin/env bash
set -eu
[[ -z "${FAKE_CALL_LOG:-}" ]] || printf 'called\n' >> "$FAKE_CALL_LOG"
case "${FAKE_CODEX_MODE:-success}" in
  fail) exit 9 ;;
  int) kill -INT "$PPID"; sleep 1; exit 130 ;;
  term) kill -TERM "$PPID"; sleep 1; exit 143 ;;
esac
if [[ "$2" == "marketplace" ]]; then
  printf '[marketplaces.openai-curated]\n' > "$CODEX_HOME/config.toml"
  exit 0
fi
cache="$CODEX_HOME/plugins/cache/openai-curated/superpowers/22aa44bb"
mkdir -p "$cache/.codex-plugin" "$cache/skills/brainstorming" "$cache/skills/writing-plans"
printf '{"name":"superpowers"}\n' > "$cache/.codex-plugin/plugin.json"
cp "$FAKE_UPSTREAM/skills/brainstorming/SKILL.md" "$cache/skills/brainstorming/SKILL.md"
cp "$FAKE_UPSTREAM/skills/writing-plans/SKILL.md" "$cache/skills/writing-plans/SKILL.md"
FAKE
chmod +x "$wrapper_root/.codex-isolated/bin/codex"

run_wrapper_case() { # <mode> <expected-exit>
  local mode="$1" expected="$2" code=0 output
  rm -rf "$wrapper_tmp"/*
  output="$(VENDOR_ROOT="$wrapper_root" TMPDIR="$wrapper_tmp" FAKE_CODEX_MODE="$mode" FAKE_UPSTREAM="$ROOT/vendor/superpowers/reconstructed-baseline" \
    bash "$ROOT/scripts/vendor-superpowers.sh" deadbeef 2>&1)" || code=$?
  [[ "$code" == "$expected" ]] || printf '%s\n' "$output"
  assert_eq "wrapper $mode exit" "$expected" "$code"
  assert_eq "wrapper $mode cleans scratch" "0" "$(find "$wrapper_tmp" -mindepth 1 | wc -l | tr -d ' ')"
}

run_wrapper_case success 0
wrapper_generation="$wrapper_root/.codex-isolated/plugins/cache/openai-curated/superpowers/22aa44bb"
assert_contains "wrapper persists supplied ref inside generation" "$(cat "$wrapper_generation/.icodex-vendor-provenance.json")" '"source_ref":"deadbeef"'
assert_exit "wrapper does not publish global source ref" 1 test -e "$wrapper_root/vendor/superpowers/source-ref"
invalid_call_log="$tmp/invalid-ref-calls"
invalid_ref_code=0
VENDOR_ROOT="$wrapper_root" TMPDIR="$wrapper_tmp" FAKE_CALL_LOG="$invalid_call_log" \
  bash "$ROOT/scripts/vendor-superpowers.sh" not-a-sha >/dev/null 2>&1 || invalid_ref_code=$?
assert_exit "wrapper rejects nonimmutable source ref" 1 test "$invalid_ref_code" -eq 0
assert_exit "invalid source ref fails before codex" 1 test -e "$invalid_call_log"
run_wrapper_case fail 9
run_wrapper_case int 130
run_wrapper_case term 143

rm -rf "$tmp"
finish
