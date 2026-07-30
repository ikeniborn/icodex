#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

write_registry() { # <path>
  mkdir -p "$(dirname "$1")"
  printf '%s\n' \
    'schema_version: 1' \
    'registry_version: 1' \
    'dimensions:' \
    '  capability:' \
    '    comparator: gte' \
    '    tiers:' \
    '      - baseline' \
    '      - strong' \
    '      - strongest' \
    '  context:' \
    '    comparator: gte' \
    '    tiers:' \
    '      - small' \
    '      - medium' \
    '      - large' \
    '  latency:' \
    '    comparator: lte' \
    '    tiers:' \
    '      - low' \
    '      - medium' \
    '      - high' \
    '  cost:' \
    '    comparator: lte' \
    '    tiers:' \
    '      - low' \
    '      - medium' \
    '      - high' \
    '  throughput:' \
    '    comparator: gte' \
    '    tiers:' \
    '      - low' \
    '      - medium' \
    '      - high' \
    'profiles:' \
    '  fast:' \
    '    model: gpt-fast' \
    '    effort: medium' \
    '    capacities:' \
    '      capability: strong' \
    '      context: medium' \
    '      latency: low' \
    '      cost: low' \
    '      throughput: high' \
    '  weak:' \
    '    model: gpt-weak' \
    '    effort: medium' \
    '    capacities:' \
    '      capability: baseline' \
    '      context: medium' \
    '      latency: low' \
    '      cost: low' \
    '      throughput: high' \
    '  expensive:' \
    '    model: gpt-expensive' \
    '    effort: medium' \
    '    capacities:' \
    '      capability: strongest' \
    '      context: large' \
    '      latency: high' \
    '      cost: high' \
    '      throughput: high' \
    '  engineering:' \
    '    model: gpt-engineering' \
    '    effort: medium' \
    '    capacities:' \
    '      capability: strongest' \
    '      context: large' \
    '      latency: medium' \
    '      cost: medium' \
    '      throughput: medium' >"$1"
}

write_topic() { # <path> <registry-hash> <preferred-profile-lines...>
  local path="$1" registry_hash="$2"
  shift 2
  mkdir -p "$(dirname "$path")"
  {
    printf '%s\n' \
      'schema_version: 1' \
      'topic: demo' \
      'status: approved' \
      'registry:' \
      '  authority: icodex-shared' \
      '  path: profiles/registry.yaml' \
      "  sha256: $registry_hash" \
      'context_inputs:' \
      '  - docs/context/demo.md' \
      'tasks:' \
      '  - id: build' \
      '    requirements:' \
      '      capability: strong' \
      '      context: medium' \
      '      latency: medium' \
      '      cost: medium' \
      '      throughput: medium' \
      '    live_remaining_context: false' \
      '    preferred_profiles:'
    printf '      - %s\n' "$@"
  } >"$path"
}

git_init() { # <repo>
  git -C "$1" init -q -b main
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name Test
}

init_policy_fixture() { # <base> <preferred-profile-lines...>
  FIXTURE_BASE="$1"
  shift
  SHARED_REPO="$FIXTURE_BASE/shared"
  SHARED_ROOT="$SHARED_REPO/.codex-isolated"
  SHARED_REGISTRY="$SHARED_ROOT/profiles/registry.yaml"
  TARGET_REPO="$FIXTURE_BASE/target"
  MANIFEST="$TARGET_REPO/docs/profiles/demo.yaml"
  CODEX_HOME="$FIXTURE_BASE/home"
  HOME_REGISTRY="$CODEX_HOME/profiles/registry.yaml"

  mkdir -p "$SHARED_ROOT/profiles" "$TARGET_REPO/docs/context" "$CODEX_HOME"
  write_registry "$SHARED_REGISTRY"
  git_init "$SHARED_REPO"
  git -C "$SHARED_REPO" add .codex-isolated/profiles/registry.yaml
  git -C "$SHARED_REPO" commit -qm 'shared registry'

  printf '%s\n' '# Demo context' >"$TARGET_REPO/docs/context/demo.md"
  write_topic "$MANIFEST" "$(sha256sum "$SHARED_REGISTRY" | awk '{print $1}')" "$@"
  git_init "$TARGET_REPO"
  git -C "$TARGET_REPO" add docs
  git -C "$TARGET_REPO" commit -qm 'target manifest'

  ln -s "$SHARED_ROOT/profiles" "$CODEX_HOME/profiles"
}

validate_topic() {
  python3 "$ROOT/lib/profile/policy.py" validate-topic \
    "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$HOME_REGISTRY"
}

validate_topic_schema() {
  python3 "$ROOT/lib/profile/policy.py" validate-topic-schema \
    "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$HOME_REGISTRY"
}

select_topic() { # <task> <available-json>
  python3 "$ROOT/lib/profile/policy.py" select \
    "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$1" "$2"
}

run_capture() { # <cmd...>
  OUTPUT="$("$@" 2>&1)"
  CODE=$?
}

# Strict parser and registry schema coverage.
VALID_REGISTRY="$TMP/valid-registry.yaml"
write_registry "$VALID_REGISTRY"
assert_exit "valid registry" 0 python3 "$ROOT/lib/profile/policy.py" validate-registry "$VALID_REGISTRY"

BOOL_REGISTRY="$TMP/bool-schema-registry.yaml"
sed 's/^schema_version: 1$/schema_version: true/' "$VALID_REGISTRY" >"$BOOL_REGISTRY"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-registry "$BOOL_REGISTRY"
assert_eq "registry boolean schema version exit" 2 "$CODE"
assert_contains "registry boolean schema version rejected" "$OUTPUT" "unsupported registry schema_version"

DUPLICATE_REGISTRY="$TMP/duplicate-registry.yaml"
write_registry "$DUPLICATE_REGISTRY"
printf '%s\n' \
  '  engineering:' \
  '    model: duplicate' \
  '    effort: medium' \
  '    capacities:' \
  '      capability: strong' \
  '      context: medium' \
  '      latency: medium' \
  '      cost: medium' \
  '      throughput: medium' >>"$DUPLICATE_REGISTRY"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-registry "$DUPLICATE_REGISTRY"
assert_eq "duplicate key exit" 2 "$CODE"
assert_contains "duplicate key path" "$OUTPUT" "duplicate key: profiles.engineering"

FLOW_REGISTRY="$TMP/flow-registry.yaml"
printf '%s\n' \
  'schema_version: 1' \
  'registry_version: 1' \
  'dimensions: {capability: strong}' \
  'profiles:' >"$FLOW_REGISTRY"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-registry "$FLOW_REGISTRY"
assert_eq "unsupported YAML exit" 2 "$CODE"
assert_contains "unsupported YAML message" "$OUTPUT" "unsupported YAML"

UNKNOWN_DIMENSION_REGISTRY="$TMP/unknown-dimension-registry.yaml"
awk '{ print; if ($0 == "dimensions:") { print "  mystery:"; print "    comparator: gte"; print "    tiers:"; print "      - low" } }' "$VALID_REGISTRY" >"$UNKNOWN_DIMENSION_REGISTRY"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-registry "$UNKNOWN_DIMENSION_REGISTRY"
assert_eq "unknown dimension exit" 2 "$CODE"
assert_contains "unknown dimension message" "$OUTPUT" "dimensions unknown keys: mystery"

UNKNOWN_TIER_REGISTRY="$TMP/unknown-tier-registry.yaml"
sed 's/capability: strong/capability: mythical/' "$VALID_REGISTRY" >"$UNKNOWN_TIER_REGISTRY"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-registry "$UNKNOWN_TIER_REGISTRY"
assert_eq "unknown tier exit" 2 "$CODE"
assert_contains "unknown tier message" "$OUTPUT" "unknown tier"

INVALID_COMPARATOR_REGISTRY="$TMP/invalid-comparator-registry.yaml"
sed '0,/comparator: gte/s//comparator: lte/' "$VALID_REGISTRY" >"$INVALID_COMPARATOR_REGISTRY"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-registry "$INVALID_COMPARATOR_REGISTRY"
assert_eq "invalid comparator exit" 2 "$CODE"
assert_contains "invalid comparator rejected" "$OUTPUT" "dimensions.capability.comparator must be gte"

UNKNOWN_NESTED_KEY_REGISTRY="$TMP/unknown-nested-key-registry.yaml"
awk '{ print; if ($0 == "    model: gpt-fast") print "    mystery: forbidden" }' \
  "$VALID_REGISTRY" >"$UNKNOWN_NESTED_KEY_REGISTRY"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-registry "$UNKNOWN_NESTED_KEY_REGISTRY"
assert_eq "unknown nested key exit" 2 "$CODE"
assert_contains "unknown nested key rejected" "$OUTPUT" "profiles.fast unknown keys: mystery"

DUPLICATE_PAIR_REGISTRY="$TMP/duplicate-model-effort-registry.yaml"
sed 's/model: gpt-weak/model: gpt-fast/' "$VALID_REGISTRY" >"$DUPLICATE_PAIR_REGISTRY"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-registry "$DUPLICATE_PAIR_REGISTRY"
assert_eq "duplicate model effort pair exit" 2 "$CODE"
assert_contains "duplicate model effort pair rejected" "$OUTPUT" "duplicate model/effort profile: gpt-fast/medium"

# Two independent Git authorities plus one CODEX_HOME symlink.
init_policy_fixture "$TMP/valid" fast engineering
assert_exit "split-authority schema validation" 0 validate_topic_schema
assert_exit "split-authority runtime validation" 0 validate_topic
SHARED_HEAD="$(git -C "$SHARED_REPO" rev-parse HEAD)"
TARGET_HEAD="$(git -C "$TARGET_REPO" rev-parse HEAD)"
if [[ "$SHARED_HEAD" != "$TARGET_HEAD" ]]; then
  echo "PASS [independent immutable HEADs]"; PASS=$((PASS+1))
else
  echo "FAIL [independent immutable HEADs]: fixture commits unexpectedly equal"; FAIL=$((FAIL+1))
fi

SNAPSHOT_JSON="$(PYTHONPATH="$ROOT/lib/profile" python3 - "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$HOME_REGISTRY" <<'PY'
import json
import sys
from pathlib import Path
from policy import load_policy

value = load_policy(*(Path(item) for item in sys.argv[1:]))
metadata = {
    "manifest_sha256": value.manifest_sha256,
    "registry_commit": value.registry_commit,
    "target_commit": value.target_commit,
}
print(json.dumps(metadata, sort_keys=True, separators=(",", ":")))
PY
)"
assert_contains "snapshot includes registry commit" "$SNAPSHOT_JSON" "\"registry_commit\":\"$SHARED_HEAD\""
assert_contains "snapshot includes target commit" "$SNAPSHOT_JSON" "\"target_commit\":\"$TARGET_HEAD\""
assert_contains "snapshot includes manifest hash" "$SNAPSHOT_JSON" "\"manifest_sha256\":\"$(sha256sum "$MANIFEST" | awk '{print $1}')\""

assert_exit "validated policy rejects nested registry and manifest mutation" 0 \
  env PYTHONPATH="$ROOT/lib/profile" python3 - \
    "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$HOME_REGISTRY" <<'PY'
import sys
from pathlib import Path

from policy import load_policy

validated = load_policy(*(Path(value) for value in sys.argv[1:]))
mutations = (
    lambda: validated.manifest["tasks"][0]["requirements"].__setitem__("capability", "baseline"),
    lambda: validated.manifest["tasks"][0]["preferred_profiles"].__setitem__(0, "weak"),
    lambda: validated.registry["profiles"]["engineering"]["capacities"].__setitem__("context", "small"),
)
for mutation in mutations:
    try:
        mutation()
    except (AttributeError, TypeError):
        continue
    raise AssertionError("validated policy exposes mutable nested state")
PY

assert_exit "sealed validated policy is the selection boundary" 0 \
  env PYTHONPATH="$ROOT/lib/profile" python3 - \
    "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$HOME_REGISTRY" <<'PY'
import sys
from pathlib import Path

from policy import load_policy, select_validated_profile

validated = load_policy(*(Path(value) for value in sys.argv[1:]))
available = [
    {
        "id": "gpt-engineering",
        "supportedReasoningEfforts": [{"reasoningEffort": "medium"}],
    }
]
selected = select_validated_profile(validated, "build", available)
assert selected == {
    "effort": "medium",
    "model": "gpt-engineering",
    "profile": "engineering",
    "task": "build",
}
PY

init_policy_fixture "$TMP/dirty-registry" fast engineering
printf '%s\n' '# dirty registry' >>"$SHARED_REGISTRY"
run_capture validate_topic
assert_eq "dirty registry exit" 3 "$CODE"
assert_contains "dirty registry rejected" "$OUTPUT" "registry differs from pinned HEAD"

init_policy_fixture "$TMP/untracked-registry" fast engineering
cp "$SHARED_REGISTRY" "$TMP/untracked-registry-copy.yaml"
git -C "$SHARED_REPO" rm -q .codex-isolated/profiles/registry.yaml
git -C "$SHARED_REPO" commit -qm 'remove registry'
mkdir -p "$(dirname "$SHARED_REGISTRY")"
cp "$TMP/untracked-registry-copy.yaml" "$SHARED_REGISTRY"
run_capture validate_topic
assert_eq "untracked registry exit" 3 "$CODE"
assert_contains "untracked registry rejected" "$OUTPUT" "registry is not tracked at pinned HEAD"

init_policy_fixture "$TMP/symlink-registry" fast engineering
mv "$SHARED_REGISTRY" "$TMP/real-registry.yaml"
ln -s "$TMP/real-registry.yaml" "$SHARED_REGISTRY"
run_capture validate_topic
assert_eq "symlink registry exit" 3 "$CODE"
assert_contains "symlink registry rejected" "$OUTPUT" "registry worktree path must be a regular file"

init_policy_fixture "$TMP/fifo-registry" fast engineering
rm "$SHARED_REGISTRY"
mkfifo "$SHARED_REGISTRY"
run_capture timeout 2s python3 "$ROOT/lib/profile/policy.py" validate-topic \
  "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$HOME_REGISTRY"
assert_eq "FIFO registry rejects without blocking exit" 3 "$CODE"
assert_contains "FIFO registry rejected as non-regular" "$OUTPUT" \
  "registry worktree path must be a regular file"

init_policy_fixture "$TMP/symlink-registry-parent" fast engineering
mv "$SHARED_ROOT/profiles" "$FIXTURE_BASE/real-profiles"
ln -s "$FIXTURE_BASE/real-profiles" "$SHARED_ROOT/profiles"
run_capture validate_topic
assert_eq "symlink registry parent exit" 3 "$CODE"
assert_contains "symlink registry parent rejected" "$OUTPUT" "registry path component must be a real directory"

init_policy_fixture "$TMP/dirty-manifest" fast engineering
printf '%s\n' '# dirty manifest' >>"$MANIFEST"
assert_exit "schema preparation permits dirty manifest bytes" 0 validate_topic_schema
run_capture validate_topic
assert_eq "dirty manifest exit" 3 "$CODE"
assert_contains "dirty manifest rejected" "$OUTPUT" "topic manifest differs from pinned HEAD"

init_policy_fixture "$TMP/untracked-manifest" fast engineering
cp "$MANIFEST" "$TMP/untracked-manifest-copy.yaml"
git -C "$TARGET_REPO" rm -q docs/profiles/demo.yaml
git -C "$TARGET_REPO" commit -qm 'remove manifest'
mkdir -p "$(dirname "$MANIFEST")"
cp "$TMP/untracked-manifest-copy.yaml" "$MANIFEST"
run_capture validate_topic
assert_eq "untracked manifest exit" 3 "$CODE"
assert_contains "untracked manifest rejected" "$OUTPUT" "topic manifest is not tracked at pinned HEAD"

init_policy_fixture "$TMP/symlink-manifest" fast engineering
mv "$MANIFEST" "$TMP/real-manifest.yaml"
ln -s "$TMP/real-manifest.yaml" "$MANIFEST"
run_capture validate_topic
assert_eq "symlink manifest exit" 3 "$CODE"
assert_contains "symlink manifest rejected" "$OUTPUT" "topic manifest worktree path must be a regular file"

init_policy_fixture "$TMP/fifo-manifest" fast engineering
rm "$MANIFEST"
mkfifo "$MANIFEST"
run_capture timeout 2s python3 "$ROOT/lib/profile/policy.py" validate-topic \
  "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$HOME_REGISTRY"
assert_eq "FIFO manifest rejects without blocking exit" 3 "$CODE"
assert_contains "FIFO manifest rejected as non-regular" "$OUTPUT" \
  "topic manifest worktree path must be a regular file"

init_policy_fixture "$TMP/symlink-manifest-parent" fast engineering
mv "$TARGET_REPO/docs/profiles" "$FIXTURE_BASE/real-manifests"
ln -s "$FIXTURE_BASE/real-manifests" "$TARGET_REPO/docs/profiles"
run_capture validate_topic
assert_eq "symlink manifest parent exit" 3 "$CODE"
assert_contains "symlink manifest parent rejected" "$OUTPUT" "topic manifest path component must be a real directory"

init_policy_fixture "$TMP/dirty-context" fast engineering
printf '%s\n' 'dirty context' >"$TARGET_REPO/docs/context/demo.md"
assert_exit "schema preparation permits dirty context bytes" 0 validate_topic_schema
run_capture validate_topic
assert_eq "dirty context exit" 3 "$CODE"
assert_contains "dirty context rejected" "$OUTPUT" "context input differs from pinned HEAD"

init_policy_fixture "$TMP/untracked-context" fast engineering
printf '%s\n' 'untracked context' >"$TARGET_REPO/untracked.md"
sed -i 's#docs/context/demo.md#untracked.md#' "$MANIFEST"
git -C "$TARGET_REPO" add docs/profiles/demo.yaml
git -C "$TARGET_REPO" commit -qm 'reference untracked context'
run_capture validate_topic
assert_eq "untracked context exit" 3 "$CODE"
assert_contains "untracked context rejected" "$OUTPUT" "context input is not tracked at pinned HEAD"

init_policy_fixture "$TMP/symlink-context" fast engineering
rm "$TARGET_REPO/docs/context/demo.md"
ln -s ../profiles/demo.yaml "$TARGET_REPO/docs/context/demo.md"
assert_exit "schema checks pinned regular context blob only" 0 validate_topic_schema
run_capture validate_topic
assert_eq "symlink context exit" 3 "$CODE"
assert_contains "symlink context rejected" "$OUTPUT" "context input worktree path must be a regular file"

init_policy_fixture "$TMP/fifo-context" fast engineering
rm "$TARGET_REPO/docs/context/demo.md"
mkfifo "$TARGET_REPO/docs/context/demo.md"
run_capture timeout 2s python3 "$ROOT/lib/profile/policy.py" validate-topic \
  "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$HOME_REGISTRY"
assert_eq "FIFO context rejects without blocking exit" 3 "$CODE"
assert_contains "FIFO context rejected as non-regular" "$OUTPUT" \
  "context input worktree path must be a regular file"

init_policy_fixture "$TMP/symlink-context-parent" fast engineering
mv "$TARGET_REPO/docs/context" "$TARGET_REPO/docs/real-context"
ln -s real-context "$TARGET_REPO/docs/context"
run_capture validate_topic
assert_eq "symlink context parent exit" 3 "$CODE"
assert_contains "symlink context parent rejected" "$OUTPUT" "context input path component must be a real directory"

init_policy_fixture "$TMP/tracked-symlink-context" fast engineering
ln -s docs/context/demo.md "$TARGET_REPO/tracked-link.md"
sed -i 's#docs/context/demo.md#tracked-link.md#' "$MANIFEST"
git -C "$TARGET_REPO" add docs/profiles/demo.yaml tracked-link.md
git -C "$TARGET_REPO" commit -qm 'reference tracked symlink'
run_capture validate_topic_schema
assert_eq "tracked symlink context exit" 3 "$CODE"
assert_contains "tracked symlink context rejected" "$OUTPUT" "context input must be a tracked regular file at pinned HEAD"

init_policy_fixture "$TMP/pathspec-context" fast engineering
printf '%s\n' 'literal wildcard' >"$TARGET_REPO/docs/context/*.md"
sed -i 's#docs/context/demo.md#docs/context/*.md#' "$MANIFEST"
git -C "$TARGET_REPO" add docs/profiles/demo.yaml
git -C "$TARGET_REPO" commit -qm 'reference literal wildcard'
run_capture validate_topic
assert_eq "pathspec context exit" 3 "$CODE"
assert_contains "pathspec treated literally" "$OUTPUT" "context input is not tracked at pinned HEAD: docs/context/*.md"

init_policy_fixture "$TMP/magic-pathspec-context" fast engineering
MAGIC_CONTEXT=':(top)docs/context/demo.md'
mkdir -p "$TARGET_REPO/:(top)docs/context"
printf '%s\n' 'literal Git magic path' >"$TARGET_REPO/$MAGIC_CONTEXT"
sed -i "s#docs/context/demo.md#$MAGIC_CONTEXT#" "$MANIFEST"
git -C "$TARGET_REPO" add docs/profiles/demo.yaml
git -C "$TARGET_REPO" commit -qm 'reference literal Git magic path'
run_capture validate_topic
assert_eq "Git magic context pathspec exit" 3 "$CODE"
assert_contains "Git magic context treated literally" "$OUTPUT" \
  "context input is not tracked at pinned HEAD: $MAGIC_CONTEXT"

init_policy_fixture "$TMP/wrong-authority" fast engineering
sed -i 's/authority: icodex-shared/authority: target-project/' "$MANIFEST"
run_capture validate_topic_schema
assert_eq "wrong authority exit" 2 "$CODE"
assert_contains "wrong authority rejected" "$OUTPUT" "registry.authority must be icodex-shared"

init_policy_fixture "$TMP/absolute-registry-path" fast engineering
sed -i 's#path: profiles/registry.yaml#path: /profiles/registry.yaml#' "$MANIFEST"
run_capture validate_topic_schema
assert_eq "absolute registry path exit" 2 "$CODE"
assert_contains "absolute registry path rejected" "$OUTPUT" "registry.path must be a repository-relative path"

init_policy_fixture "$TMP/traversal-registry-path" fast engineering
sed -i 's#path: profiles/registry.yaml#path: profiles/../profiles/registry.yaml#' "$MANIFEST"
run_capture validate_topic_schema
assert_eq "traversal registry path exit" 2 "$CODE"
assert_contains "traversal registry path rejected" "$OUTPUT" "registry.path must be a repository-relative path"

init_policy_fixture "$TMP/portable-history" fast engineering
sed -i '/^tasks:/i portable_history:\n  enabled: true' "$MANIFEST"
run_capture validate_topic_schema
assert_eq "portable history exit" 2 "$CODE"
assert_contains "portable history rejected" "$OUTPUT" "topic manifest unknown keys: portable_history"

init_policy_fixture "$TMP/bool-topic-schema" fast engineering
sed -i 's/^schema_version: 1$/schema_version: true/' "$MANIFEST"
run_capture validate_topic_schema
assert_eq "topic boolean schema version exit" 2 "$CODE"
assert_contains "topic boolean schema version rejected" "$OUTPUT" "unsupported topic schema_version"

init_policy_fixture "$TMP/unapproved-topic" fast engineering
sed -i 's/^status: approved$/status: draft/' "$MANIFEST"
run_capture validate_topic_schema
assert_eq "unapproved topic exit" 3 "$CODE"
assert_contains "unapproved topic rejected" "$OUTPUT" "topic status must be approved"

init_policy_fixture "$TMP/wrong-home-link" fast engineering
rm "$CODEX_HOME/profiles"
mkdir -p "$FIXTURE_BASE/other/profiles"
cp "$SHARED_REGISTRY" "$FIXTURE_BASE/other/profiles/registry.yaml"
ln -s "$FIXTURE_BASE/other/profiles" "$CODEX_HOME/profiles"
run_capture validate_topic
assert_eq "wrong home link target exit" 3 "$CODE"
assert_contains "wrong home link target rejected" "$OUTPUT" "CODEX_HOME profiles link must target shared profiles"

init_policy_fixture "$TMP/target-local-registry" fast engineering
cp "$SHARED_REGISTRY" "$TARGET_REPO/docs/profiles/registry.yaml"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic \
  "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$TARGET_REPO/docs/profiles/registry.yaml"
assert_eq "target-local registry exit" 3 "$CODE"
assert_contains "target-local registry rejected" "$OUTPUT" "registry path must be CODEX_HOME/profiles/registry.yaml"

# Pin both authorities before either policy snapshot is read.
init_policy_fixture "$TMP/move-target" fast engineering
TARGET_A="$(git -C "$TARGET_REPO" rev-parse HEAD)"
cp "$MANIFEST" "$TMP/target-a.yaml"
printf '%s\n' '# target B' >>"$MANIFEST"
git -C "$TARGET_REPO" add docs/profiles/demo.yaml
git -C "$TARGET_REPO" commit -qm 'target B'
TARGET_B="$(git -C "$TARGET_REPO" rev-parse HEAD)"
git -C "$TARGET_REPO" update-ref HEAD "$TARGET_A"
cp "$TMP/target-a.yaml" "$MANIFEST"
GIT_WRAPPER="$TMP/move-target-bin"
mkdir -p "$GIT_WRAPPER"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -eu' \
  'if [[ "$*" == *"-C $SHARED_REPO"* && "$*" == *"ls-tree"* ]]; then' \
  '  "$REAL_GIT" -C "$TARGET_REPO" update-ref HEAD "$TARGET_B"' \
  'fi' \
  'exec "$REAL_GIT" "$@"' >"$GIT_WRAPPER/git"
chmod +x "$GIT_WRAPPER/git"
run_capture env PATH="$GIT_WRAPPER:$PATH" REAL_GIT="$(command -v git)" SHARED_REPO="$SHARED_REPO" TARGET_REPO="$TARGET_REPO" TARGET_B="$TARGET_B" \
  python3 "$ROOT/lib/profile/policy.py" validate-topic "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$HOME_REGISTRY"
assert_eq "target HEAD movement during registry validation uses pinned target commit" 0 "$CODE"

init_policy_fixture "$TMP/move-shared" fast engineering
SHARED_A="$(git -C "$SHARED_REPO" rev-parse HEAD)"
cp "$SHARED_REGISTRY" "$TMP/shared-a.yaml"
printf '%s\n' '# shared B' >>"$SHARED_REGISTRY"
git -C "$SHARED_REPO" add .codex-isolated/profiles/registry.yaml
git -C "$SHARED_REPO" commit -qm 'shared B'
SHARED_B="$(git -C "$SHARED_REPO" rev-parse HEAD)"
git -C "$SHARED_REPO" update-ref HEAD "$SHARED_A"
cp "$TMP/shared-a.yaml" "$SHARED_REGISTRY"
GIT_WRAPPER="$TMP/move-shared-bin"
mkdir -p "$GIT_WRAPPER"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -eu' \
  'if [[ "$*" == *"-C $TARGET_REPO"* && "$*" == *"ls-tree"* ]]; then' \
  '  "$REAL_GIT" -C "$SHARED_REPO" update-ref HEAD "$SHARED_B"' \
  'fi' \
  'exec "$REAL_GIT" "$@"' >"$GIT_WRAPPER/git"
chmod +x "$GIT_WRAPPER/git"
run_capture env PATH="$GIT_WRAPPER:$PATH" REAL_GIT="$(command -v git)" SHARED_REPO="$SHARED_REPO" TARGET_REPO="$TARGET_REPO" SHARED_B="$SHARED_B" \
  python3 "$ROOT/lib/profile/policy.py" validate-topic "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$HOME_REGISTRY"
assert_eq "shared HEAD movement during target validation uses pinned registry commit" 0 "$CODE"

init_policy_fixture "$TMP/directory-swap" fast engineering
ORIGINAL_PROFILES="$FIXTURE_BASE/original-profiles"
EVIL_PROFILES="$FIXTURE_BASE/evil-profiles"
mkdir -p "$EVIL_PROFILES"
cp "$SHARED_REGISTRY" "$EVIL_PROFILES/registry.yaml"
printf '%s\n' '# swapped authority bytes' >>"$EVIL_PROFILES/registry.yaml"
assert_exit "directory swap cannot escape opened registry authority" 0 \
  env PYTHONPATH="$ROOT/lib/profile" EXPECTED_REGISTRY_HASH="$(sha256sum "$SHARED_REGISTRY" | awk '{print $1}')" python3 - \
    "$TARGET_REPO" "$CODEX_HOME" "$SHARED_ROOT" "$MANIFEST" "$HOME_REGISTRY" \
    "$SHARED_ROOT/profiles" "$ORIGINAL_PROFILES" "$EVIL_PROFILES" <<'PY'
import os
import sys
from pathlib import Path

import policy

arguments = [Path(value) for value in sys.argv[1:6]]
profiles_path, original_path, evil_path = [Path(value) for value in sys.argv[6:9]]
real_open = policy.os.open
swapped = False

def racing_open(path, flags, mode=0o777, *, dir_fd=None):
    global swapped
    if not swapped and Path(os.fsdecode(path)).name == "registry.yaml":
        os.rename(profiles_path, original_path)
        os.symlink(evil_path, profiles_path, target_is_directory=True)
        swapped = True
    return real_open(path, flags, mode, dir_fd=dir_fd)

policy.os.open = racing_open
validated = policy.load_policy(*arguments)
assert swapped
assert validated.registry_sha256 == os.environ["EXPECTED_REGISTRY_HASH"]
PY

# Selector, comparator, and model/list coverage.
ENGINEERING_AVAILABLE='[{"id":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]'
init_policy_fixture "$TMP/fallback" fast engineering
run_capture select_topic build "$ENGINEERING_AVAILABLE"
assert_eq "second sufficient profile selection exit" 0 "$CODE"
assert_eq "deterministic fallback" '{"effort":"medium","model":"gpt-engineering","profile":"engineering","task":"build"}' "$OUTPUT"

init_policy_fixture "$TMP/lte" expensive engineering
LTE_AVAILABLE='[{"id":"gpt-expensive","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]},{"id":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]'
run_capture select_topic build "$LTE_AVAILABLE"
assert_eq "lte decisive selection exit" 0 "$CODE"
assert_eq "high latency and cost fail lte" '{"effort":"medium","model":"gpt-engineering","profile":"engineering","task":"build"}' "$OUTPUT"

init_policy_fixture "$TMP/live-context" engineering
sed -i 's/live_remaining_context: false/live_remaining_context: true/' "$MANIFEST"
git -C "$TARGET_REPO" add docs/profiles/demo.yaml
git -C "$TARGET_REPO" commit -qm 'require live remaining context'
run_capture select_topic build "$ENGINEERING_AVAILABLE"
assert_eq "live remaining context exit" 4 "$CODE"
assert_contains "live remaining context rejected" "$OUTPUT" "requires live remaining-context confirmation"

init_policy_fixture "$TMP/model-list" engineering
DUPLICATE_MODELS='[{"id":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]},{"id":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]'
run_capture select_topic build "$DUPLICATE_MODELS"
assert_eq "duplicate model/list exit" 4 "$CODE"
assert_contains "duplicate model/list rejected" "$OUTPUT" "duplicate available model id: gpt-engineering"

MISSING_EFFORT_METADATA='[{"id":"gpt-engineering"}]'
run_capture select_topic build "$MISSING_EFFORT_METADATA"
assert_eq "missing effort metadata exit" 4 "$CODE"
assert_contains "missing effort metadata rejected" "$OUTPUT" "missing supported effort metadata"

DUPLICATE_EFFORT_METADATA='[{"id":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"},{"reasoningEffort":"medium"}]}]'
run_capture select_topic build "$DUPLICATE_EFFORT_METADATA"
assert_eq "duplicate supported reasoning effort exit" 4 "$CODE"
assert_eq "duplicate supported reasoning effort rejected" \
  "duplicate supported reasoning effort for model gpt-engineering: medium" "$OUTPUT"

MISMATCHED_MODEL_FIELDS='[{"id":"gpt-engineering","model":"gpt-other","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]'
run_capture select_topic build "$MISMATCHED_MODEL_FIELDS"
assert_eq "mismatched model fields exit" 4 "$CODE"
assert_contains "mismatched model fields rejected" "$OUTPUT" "model/list id and model disagree"

MODEL_FIELD_AVAILABLE='[{"model":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]'
run_capture select_topic build "$MODEL_FIELD_AVAILABLE"
assert_eq "documented model field selection exit" 0 "$CODE"
assert_eq "documented model field accepted" '{"effort":"medium","model":"gpt-engineering","profile":"engineering","task":"build"}' "$OUTPUT"

UNDOCUMENTED_TOP_LEVEL_EFFORTS='[{"id":"gpt-engineering","supported_efforts":["medium"]}]'
run_capture select_topic build "$UNDOCUMENTED_TOP_LEVEL_EFFORTS"
assert_eq "undocumented top-level efforts exit" 4 "$CODE"
assert_contains "undocumented top-level efforts rejected" "$OUTPUT" "missing supported effort metadata"

UNDOCUMENTED_NESTED_EFFORT='[{"id":"gpt-engineering","supportedReasoningEfforts":[{"effort":"medium"}]}]'
run_capture select_topic build "$UNDOCUMENTED_NESTED_EFFORT"
assert_eq "undocumented nested effort exit" 4 "$CODE"
assert_contains "undocumented nested effort rejected" "$OUTPUT" "reasoningEffort"

init_policy_fixture "$TMP/unavailable-and-insufficient" fast weak engineering
AVAILABLE='[{"id":"gpt-weak","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]},{"id":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]'
run_capture select_topic build "$AVAILABLE"
assert_eq "unavailable and insufficient fallback exit" 0 "$CODE"
assert_eq "unavailable and insufficient profiles skipped" '{"effort":"medium","model":"gpt-engineering","profile":"engineering","task":"build"}' "$OUTPUT"

init_policy_fixture "$TMP/insufficient" weak
run_capture select_topic build "$AVAILABLE"
assert_eq "no sufficient profile exit" 4 "$CODE"
assert_contains "no sufficient profile rejected" "$OUTPUT" "no available sufficient profile"
assert_contains "insufficient dimension evidence" "$OUTPUT" "capability"

# Curated production policy: canonical shared registry and direct project manifest.
PRODUCTION_SHARED_REGISTRY="$ROOT/.codex-isolated/profiles/registry.yaml"
PRODUCTION_STALE_REGISTRY="$ROOT/docs/profiles/registry.yaml"
PRODUCTION_MANIFEST="$ROOT/docs/profiles/profile-recheck-at-task-transition.yaml"
assert_exit "production shared registry exists at canonical path" 0 test -f "$PRODUCTION_SHARED_REGISTRY"
assert_eq "production shared registry keeps approved byte hash" \
  "7ef5c802e43fc96ecc23260e0460aa7a0df568c21dd369d86947d8e935d16a92" \
  "$(sha256sum "$PRODUCTION_SHARED_REGISTRY" | awk '{print $1}')"
assert_exit "stale project-local registry is absent" 0 test ! -e "$PRODUCTION_STALE_REGISTRY"
assert_exit "production manifest omits portable history" 1 grep -Fq 'portable_history' "$PRODUCTION_MANIFEST"
assert_exit "production manifest names shared authority" 0 grep -Fxq '  authority: icodex-shared' "$PRODUCTION_MANIFEST"
assert_exit "production manifest pins canonical shared path" 0 grep -Fxq '  path: profiles/registry.yaml' "$PRODUCTION_MANIFEST"
assert_eq "production manifest approved byte hash" \
  "6176029a40963ad9db08964606909dc9def856565a94db3817cc35522fa22eef" \
  "$(sha256sum "$PRODUCTION_MANIFEST" | awk '{print $1}')"

SELF_CODEX_HOME="$TMP/self-target-home"
mkdir -p "$SELF_CODEX_HOME"
ln -s "$ROOT/.codex-isolated/profiles" "$SELF_CODEX_HOME/profiles"
assert_exit "production manifest validates when target and shared roles use one repository" 0 \
  python3 "$ROOT/lib/profile/policy.py" validate-topic \
    "$ROOT" "$SELF_CODEX_HOME" "$ROOT/.codex-isolated" \
    "$PRODUCTION_MANIFEST" "$SELF_CODEX_HOME/profiles/registry.yaml"

PRODUCTION_BASE="$TMP/production-policy"
PRODUCTION_SHARED_REPO="$PRODUCTION_BASE/shared"
PRODUCTION_SHARED_ROOT="$PRODUCTION_SHARED_REPO/.codex-isolated"
PRODUCTION_TARGET_REPO="$PRODUCTION_BASE/target"
PRODUCTION_CODEX_HOME="$PRODUCTION_BASE/home"
PRODUCTION_FIXTURE_MANIFEST="$PRODUCTION_TARGET_REPO/docs/profiles/profile-recheck-at-task-transition.yaml"
PRODUCTION_HOME_REGISTRY="$PRODUCTION_CODEX_HOME/profiles/registry.yaml"
mkdir -p "$PRODUCTION_SHARED_ROOT/profiles" "$PRODUCTION_TARGET_REPO/docs/profiles" "$PRODUCTION_CODEX_HOME"
cp "$PRODUCTION_SHARED_REGISTRY" "$PRODUCTION_SHARED_ROOT/profiles/registry.yaml"
cp "$PRODUCTION_MANIFEST" "$PRODUCTION_FIXTURE_MANIFEST"
while IFS= read -r context_path; do
  mkdir -p "$PRODUCTION_TARGET_REPO/$(dirname "$context_path")"
  cp "$ROOT/$context_path" "$PRODUCTION_TARGET_REPO/$context_path"
done < <(sed -n 's/^  - \(docs\/superpowers\/.*\.md\)$/\1/p' "$PRODUCTION_MANIFEST")
git_init "$PRODUCTION_SHARED_REPO"
git -C "$PRODUCTION_SHARED_REPO" add .codex-isolated/profiles/registry.yaml
git -C "$PRODUCTION_SHARED_REPO" commit -qm 'production shared authority'
git_init "$PRODUCTION_TARGET_REPO"
git -C "$PRODUCTION_TARGET_REPO" add docs
git -C "$PRODUCTION_TARGET_REPO" commit -qm 'production target authority'
ln -s "$PRODUCTION_SHARED_ROOT/profiles" "$PRODUCTION_CODEX_HOME/profiles"
assert_exit "production manifest schema preparation" 0 \
  python3 "$ROOT/lib/profile/policy.py" validate-topic-schema \
    "$PRODUCTION_TARGET_REPO" "$PRODUCTION_CODEX_HOME" "$PRODUCTION_SHARED_ROOT" \
    "$PRODUCTION_FIXTURE_MANIFEST" "$PRODUCTION_HOME_REGISTRY"
assert_exit "production manifest committed runtime authority" 0 \
  python3 "$ROOT/lib/profile/policy.py" validate-topic \
    "$PRODUCTION_TARGET_REPO" "$PRODUCTION_CODEX_HOME" "$PRODUCTION_SHARED_ROOT" \
    "$PRODUCTION_FIXTURE_MANIFEST" "$PRODUCTION_HOME_REGISTRY"

finish
