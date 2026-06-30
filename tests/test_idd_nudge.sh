#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

NUDGE="$ROOT/.codex-isolated/hooks/idd-nudge.py"
assert_exit "nudge file exists" 0 test -f "$NUDGE"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/docs/superpowers/specs"
SPEC="docs/superpowers/specs/2026-06-30-bar-design.md"
printf '# Bar\n\nBody.\n' > "$WORK/$SPEC"

run_nudge() { # <json> -> prints stdout
  ( cd "$WORK" && python3 "$NUDGE" 2>/dev/null <<<"$1" )
}

body_hash() { # <path>
  ( cd "$WORK" && bash -c 'set -o pipefail; awk '\''BEGIN{fm=0} /^---$/{fm++; next} fm>=2{print}'\'' "$1" | sha256sum | cut -c1-16' -- "$1" )
}

write_review_spec() { # <path> <hash> <phases_yaml> <findings_yaml>
  local path="$1" hash="$2" phases="$3" findings="$4"
  mkdir -p "$(dirname "$WORK/$path")"
  {
    printf '%s\n' '---' 'review:' "  spec_hash: $hash"
    if [[ -n "$phases" ]]; then
      printf '%s\n' "$phases"
    fi
    printf '%s\n' "$findings" '---' '# Bar' '' 'Body.'
  } > "$WORK/$path"
}

make_valid_spec() { # <path>
  local path="$1" hash
  write_review_spec "$path" "PLACEHOLDER" "  phases:
    design:
      status: passed" "  findings: []"
  hash="$(body_hash "$path")"
  write_review_spec "$path" "$hash" "  phases:
    design:
      status: passed" "  findings: []"
}

# 1. Write of an unvalidated spec -> nudge mentions check-spec.
w='{"tool_name":"Write","tool_input":{"file_path":"'"$SPEC"'","content":"x"}}'
out="$(run_nudge "$w")"
assert_contains "nudge emitted for new spec" "$out" "additionalContext"
assert_contains "nudge names check-spec" "$out" "check-spec"

# 2. apply_patch Add File of the spec -> also nudges.
p='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Add File: '"$SPEC"'\n+# Bar\n*** End Patch\n"}}'
assert_contains "nudge emitted for apply_patch spec" "$(run_nudge "$p")" "check-spec"

# 3. Write of a non-artifact path -> silent.
n='{"tool_name":"Write","tool_input":{"file_path":"README.md","content":"x"}}'
assert_eq "non-artifact silent" "" "$(run_nudge "$n")"

# 4. Malformed stdin -> silent, exit 0.
assert_eq "malformed stdin silent" "" "$(run_nudge 'not json')"

# 5. Validated artifact -> silent.
make_valid_spec "$SPEC"
assert_eq "validated artifact silent" "" "$(run_nudge "$w")"

# 6. Stale hash -> nudge.
write_review_spec "$SPEC" "stalehash" "  phases:
    design:
      status: passed" "  findings: []"
assert_contains "stale hash nudges" "$(run_nudge "$w")" "check-spec"

# 7. Malformed review state -> nudge.
hash="$(body_hash "$SPEC")"
write_review_spec "$SPEC" "$hash" "" "  findings: []"
assert_contains "missing phases nudges" "$(run_nudge "$w")" "check-spec"

write_review_spec "$SPEC" "$hash" "  phases: nope" "  findings: []"
assert_contains "non-dict phases nudges" "$(run_nudge "$w")" "check-spec"

write_review_spec "$SPEC" "$hash" "  phases:
    design:
      status: passed" "  findings: nope"
assert_contains "non-list findings nudges" "$(run_nudge "$w")" "check-spec"

printf '%s\n' '---' 'review: [' '---' '# Bar' '' 'Body.' > "$WORK/$SPEC"
assert_contains "invalid YAML frontmatter nudges" "$(run_nudge "$w")" "check-spec"

# 8. Shell metacharacters in path must not execute command substitution.
META_SPEC='docs/superpowers/specs/2026-06-30-$(touch PROOF)-design.md'
make_valid_spec "$META_SPEC"
m='{"tool_name":"Write","tool_input":{"file_path":"'"$META_SPEC"'","content":"x"}}'
run_nudge "$m" >/dev/null
assert_exit "metachar path did not execute command substitution" 1 test -e "$WORK/PROOF"

finish
