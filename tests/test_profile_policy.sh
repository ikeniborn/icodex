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
      '  path: docs/profiles/registry.yaml' \
      "  sha256: $registry_hash" \
      'context_inputs:' \
      '  - docs/superpowers/plans/demo.md' \
      'portable_history:' \
      '  enabled: true' \
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

init_policy_repo() { # <repo> <preferred-profile-lines...>
  local repo="$1" registry hash
  shift
  registry="$repo/docs/profiles/registry.yaml"
  mkdir -p "$repo/docs/superpowers/plans"
  write_registry "$registry"
  printf '%s\n' '# Demo plan' >"$repo/docs/superpowers/plans/demo.md"
  hash="$(sha256sum "$registry" | awk '{print $1}')"
  write_topic "$repo/docs/profiles/demo.yaml" "$hash" "$@"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  git -C "$repo" add docs
  git -C "$repo" commit -qm 'test fixture'
}

run_capture() { # <cmd...>
  OUTPUT="$("$@" 2>&1)"
  CODE=$?
}

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

DIRTY_REPO="$TMP/dirty"
init_policy_repo "$DIRTY_REPO" fast engineering
printf '%s\n' '# dirty' >>"$DIRTY_REPO/docs/profiles/demo.yaml"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$DIRTY_REPO/docs/profiles/demo.yaml" "$DIRTY_REPO/docs/profiles/registry.yaml"
assert_eq "dirty topic exit" 3 "$CODE"
assert_contains "dirty topic message" "$OUTPUT" "topic manifest differs from HEAD"

MISMATCH_REPO="$TMP/mismatch"
init_policy_repo "$MISMATCH_REPO" fast engineering
printf '%s\n' '# changed registry' >>"$MISMATCH_REPO/docs/profiles/registry.yaml"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$MISMATCH_REPO/docs/profiles/demo.yaml" "$MISMATCH_REPO/docs/profiles/registry.yaml"
assert_eq "registry mismatch exit" 3 "$CODE"
assert_contains "registry mismatch message" "$OUTPUT" "registry hash mismatch"

SNAPSHOT_REPO="$TMP/snapshot"
init_policy_repo "$SNAPSHOT_REPO" fast engineering
cp "$SNAPSHOT_REPO/docs/profiles/demo.yaml" "$TMP/snapshot-topic-a.yaml"
cp "$SNAPSHOT_REPO/docs/profiles/registry.yaml" "$TMP/snapshot-registry-a.yaml"
printf '%s\n' '# registry from commit B' >>"$SNAPSHOT_REPO/docs/profiles/registry.yaml"
git -C "$SNAPSHOT_REPO" add docs/profiles/registry.yaml
git -C "$SNAPSHOT_REPO" commit -qm 'inconsistent old snapshot'
SNAPSHOT_OLD_HEAD="$(git -C "$SNAPSHOT_REPO" rev-parse HEAD)"
cp "$TMP/snapshot-registry-a.yaml" "$SNAPSHOT_REPO/docs/profiles/registry.yaml"
printf '%s\n' '# topic from commit C' >>"$SNAPSHOT_REPO/docs/profiles/demo.yaml"
git -C "$SNAPSHOT_REPO" add docs/profiles/demo.yaml docs/profiles/registry.yaml
git -C "$SNAPSHOT_REPO" commit -qm 'inconsistent new snapshot'
SNAPSHOT_NEW_HEAD="$(git -C "$SNAPSHOT_REPO" rev-parse HEAD)"
git -C "$SNAPSHOT_REPO" update-ref HEAD "$SNAPSHOT_OLD_HEAD"
cp "$TMP/snapshot-topic-a.yaml" "$SNAPSHOT_REPO/docs/profiles/demo.yaml"
SNAPSHOT_GIT_DIR="$TMP/snapshot-git"
mkdir -p "$SNAPSHOT_GIT_DIR"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -eu' \
  'if [[ "$*" == "-C $SNAPSHOT_REPO rev-parse --verify HEAD^{commit}" ]]; then' \
  '  output="$("$REAL_GIT" "$@")"' \
  '  "$REAL_GIT" -C "$SNAPSHOT_REPO" update-ref HEAD "$SNAPSHOT_NEW_HEAD"' \
  '  printf "%s\n" "$output"' \
  '  exit 0' \
  'fi' \
  'if [[ "$*" == "-C $SNAPSHOT_REPO show HEAD:docs/profiles/demo.yaml" ]]; then' \
  '  output="$("$REAL_GIT" "$@")"' \
  '  "$REAL_GIT" -C "$SNAPSHOT_REPO" update-ref HEAD "$SNAPSHOT_NEW_HEAD"' \
  '  printf "%s\n" "$output"' \
  '  exit 0' \
  'fi' \
  'exec "$REAL_GIT" "$@"' >"$SNAPSHOT_GIT_DIR/git"
chmod +x "$SNAPSHOT_GIT_DIR/git"
run_capture env PATH="$SNAPSHOT_GIT_DIR:$PATH" REAL_GIT="$(command -v git)" SNAPSHOT_REPO="$SNAPSHOT_REPO" SNAPSHOT_NEW_HEAD="$SNAPSHOT_NEW_HEAD" python3 "$ROOT/lib/profile/policy.py" validate-topic "$SNAPSHOT_REPO/docs/profiles/demo.yaml" "$SNAPSHOT_REPO/docs/profiles/registry.yaml"
assert_eq "single immutable HEAD snapshot exit" 3 "$CODE"
assert_contains "single immutable HEAD snapshot message" "$OUTPUT" "registry differs from pinned HEAD"

WRONG_TOPIC_REPO="$TMP/wrong-topic-path"
init_policy_repo "$WRONG_TOPIC_REPO" fast engineering
mkdir -p "$WRONG_TOPIC_REPO/policies"
git -C "$WRONG_TOPIC_REPO" mv docs/profiles/demo.yaml policies/demo.yaml
git -C "$WRONG_TOPIC_REPO" commit -qm 'move topic outside authority directory'
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$WRONG_TOPIC_REPO/policies/demo.yaml" "$WRONG_TOPIC_REPO/docs/profiles/registry.yaml"
assert_eq "wrong topic directory exit" 3 "$CODE"
assert_contains "wrong topic directory message" "$OUTPUT" "topic manifest path must be"

WRONG_REGISTRY_REPO="$TMP/wrong-registry-path"
init_policy_repo "$WRONG_REGISTRY_REPO" fast engineering
mkdir -p "$WRONG_REGISTRY_REPO/policies"
git -C "$WRONG_REGISTRY_REPO" mv docs/profiles/registry.yaml policies/registry.yaml
sed -i 's#path: docs/profiles/registry.yaml#path: policies/registry.yaml#' "$WRONG_REGISTRY_REPO/docs/profiles/demo.yaml"
git -C "$WRONG_REGISTRY_REPO" add docs/profiles/demo.yaml
git -C "$WRONG_REGISTRY_REPO" commit -qm 'move registry outside authority directory'
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$WRONG_REGISTRY_REPO/docs/profiles/demo.yaml" "$WRONG_REGISTRY_REPO/policies/registry.yaml"
assert_eq "wrong registry directory exit" 3 "$CODE"
assert_contains "wrong registry directory message" "$OUTPUT" "registry path must be"

UNTRACKED_CONTEXT_REPO="$TMP/untracked-context"
init_policy_repo "$UNTRACKED_CONTEXT_REPO" fast engineering
printf '%s\n' 'untracked context' >"$UNTRACKED_CONTEXT_REPO/untracked-context.md"
sed -i 's#docs/superpowers/plans/demo.md#untracked-context.md#' "$UNTRACKED_CONTEXT_REPO/docs/profiles/demo.yaml"
git -C "$UNTRACKED_CONTEXT_REPO" add docs/profiles/demo.yaml
git -C "$UNTRACKED_CONTEXT_REPO" commit -qm 'reference untracked context'
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$UNTRACKED_CONTEXT_REPO/docs/profiles/demo.yaml" "$UNTRACKED_CONTEXT_REPO/docs/profiles/registry.yaml"
assert_eq "untracked context input exit" 3 "$CODE"
assert_contains "untracked context input message" "$OUTPUT" "context input is not tracked at pinned HEAD"

UNTRACKED_CONTEXT_LINK_REPO="$TMP/untracked-context-link"
init_policy_repo "$UNTRACKED_CONTEXT_LINK_REPO" fast engineering
ln -s docs/superpowers/plans/demo.md "$UNTRACKED_CONTEXT_LINK_REPO/untracked-link.md"
sed -i 's#docs/superpowers/plans/demo.md#untracked-link.md#' "$UNTRACKED_CONTEXT_LINK_REPO/docs/profiles/demo.yaml"
git -C "$UNTRACKED_CONTEXT_LINK_REPO" add docs/profiles/demo.yaml
git -C "$UNTRACKED_CONTEXT_LINK_REPO" commit -qm 'reference untracked context symlink'
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$UNTRACKED_CONTEXT_LINK_REPO/docs/profiles/demo.yaml" "$UNTRACKED_CONTEXT_LINK_REPO/docs/profiles/registry.yaml"
assert_eq "untracked context symlink exit" 3 "$CODE"
assert_contains "untracked context symlink message" "$OUTPUT" "context input is not tracked at pinned HEAD: untracked-link.md"

TRACKED_CONTEXT_LINK_REPO="$TMP/tracked-context-link"
init_policy_repo "$TRACKED_CONTEXT_LINK_REPO" fast engineering
ln -s docs/superpowers/plans/demo.md "$TRACKED_CONTEXT_LINK_REPO/tracked-link.md"
sed -i 's#docs/superpowers/plans/demo.md#tracked-link.md#' "$TRACKED_CONTEXT_LINK_REPO/docs/profiles/demo.yaml"
git -C "$TRACKED_CONTEXT_LINK_REPO" add docs/profiles/demo.yaml tracked-link.md
git -C "$TRACKED_CONTEXT_LINK_REPO" commit -qm 'reference tracked context symlink'
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$TRACKED_CONTEXT_LINK_REPO/docs/profiles/demo.yaml" "$TRACKED_CONTEXT_LINK_REPO/docs/profiles/registry.yaml"
assert_eq "tracked context symlink exit" 3 "$CODE"
assert_contains "tracked context symlink message" "$OUTPUT" "context input must be a tracked regular file at pinned HEAD: tracked-link.md"

PATHSPEC_CONTEXT_REPO="$TMP/pathspec-context"
init_policy_repo "$PATHSPEC_CONTEXT_REPO" fast engineering
printf '%s\n' 'untracked literal wildcard path' >"$PATHSPEC_CONTEXT_REPO/docs/superpowers/plans/*.md"
sed -i 's#docs/superpowers/plans/demo.md#docs/superpowers/plans/*.md#' "$PATHSPEC_CONTEXT_REPO/docs/profiles/demo.yaml"
git -C "$PATHSPEC_CONTEXT_REPO" add docs/profiles/demo.yaml
git -C "$PATHSPEC_CONTEXT_REPO" commit -qm 'reference untracked literal wildcard path'
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$PATHSPEC_CONTEXT_REPO/docs/profiles/demo.yaml" "$PATHSPEC_CONTEXT_REPO/docs/profiles/registry.yaml"
assert_eq "context input pathspec treated literally exit" 3 "$CODE"
assert_contains "context input pathspec treated literally message" "$OUTPUT" "context input is not tracked at pinned HEAD: docs/superpowers/plans/*.md"

MAGIC_CONTEXT_REPO="$TMP/magic-context"
MAGIC_CONTEXT_VALUE=':(top)docs/superpowers/plans/demo.md'
init_policy_repo "$MAGIC_CONTEXT_REPO" fast engineering
mkdir -p "$MAGIC_CONTEXT_REPO/:(top)docs/superpowers/plans"
printf '%s\n' 'untracked literal magic path' >"$MAGIC_CONTEXT_REPO/$MAGIC_CONTEXT_VALUE"
sed -i "s#docs/superpowers/plans/demo.md#$MAGIC_CONTEXT_VALUE#" "$MAGIC_CONTEXT_REPO/docs/profiles/demo.yaml"
git -C "$MAGIC_CONTEXT_REPO" add docs/profiles/demo.yaml
git -C "$MAGIC_CONTEXT_REPO" commit -qm 'reference untracked literal magic path'
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$MAGIC_CONTEXT_REPO/docs/profiles/demo.yaml" "$MAGIC_CONTEXT_REPO/docs/profiles/registry.yaml"
assert_eq "context input magic path treated literally exit" 3 "$CODE"
assert_contains "context input magic path treated literally message" "$OUTPUT" "context input is not tracked at pinned HEAD: $MAGIC_CONTEXT_VALUE"

OUTSIDE_CONTEXT_REPO="$TMP/outside-context"
init_policy_repo "$OUTSIDE_CONTEXT_REPO" fast engineering
printf '%s\n' 'outside context' >"$TMP/outside-context.md"
ln -s "$TMP/outside-context.md" "$OUTSIDE_CONTEXT_REPO/outside-link.md"
sed -i 's#docs/superpowers/plans/demo.md#outside-link.md#' "$OUTSIDE_CONTEXT_REPO/docs/profiles/demo.yaml"
git -C "$OUTSIDE_CONTEXT_REPO" add docs/profiles/demo.yaml outside-link.md
git -C "$OUTSIDE_CONTEXT_REPO" commit -qm 'reference outside context'
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$OUTSIDE_CONTEXT_REPO/docs/profiles/demo.yaml" "$OUTSIDE_CONTEXT_REPO/docs/profiles/registry.yaml"
assert_eq "outside context input exit" 3 "$CODE"
assert_contains "outside context input message" "$OUTPUT" "context input must resolve inside repository"

UNAPPROVED_REPO="$TMP/unapproved-topic"
init_policy_repo "$UNAPPROVED_REPO" fast engineering
sed -i 's/^status: approved$/status: draft/' "$UNAPPROVED_REPO/docs/profiles/demo.yaml"
git -C "$UNAPPROVED_REPO" add docs/profiles/demo.yaml
git -C "$UNAPPROVED_REPO" commit -qm 'mark topic unapproved'
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$UNAPPROVED_REPO/docs/profiles/demo.yaml" "$UNAPPROVED_REPO/docs/profiles/registry.yaml"
assert_eq "unapproved topic exit" 3 "$CODE"
assert_contains "unapproved topic message" "$OUTPUT" "topic status must be approved"

UNTRACKED_TOPIC_REPO="$TMP/untracked-topic"
init_policy_repo "$UNTRACKED_TOPIC_REPO" fast engineering
cp "$UNTRACKED_TOPIC_REPO/docs/profiles/demo.yaml" "$TMP/untracked-topic.yaml"
git -C "$UNTRACKED_TOPIC_REPO" rm -q docs/profiles/demo.yaml
git -C "$UNTRACKED_TOPIC_REPO" commit -qm 'remove tracked topic'
cp "$TMP/untracked-topic.yaml" "$UNTRACKED_TOPIC_REPO/docs/profiles/demo.yaml"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$UNTRACKED_TOPIC_REPO/docs/profiles/demo.yaml" "$UNTRACKED_TOPIC_REPO/docs/profiles/registry.yaml"
assert_eq "untracked topic exit" 3 "$CODE"
assert_contains "untracked topic message" "$OUTPUT" "topic manifest is not tracked at pinned HEAD"

UNTRACKED_REGISTRY_REPO="$TMP/untracked-registry"
init_policy_repo "$UNTRACKED_REGISTRY_REPO" fast engineering
cp "$UNTRACKED_REGISTRY_REPO/docs/profiles/registry.yaml" "$TMP/untracked-registry.yaml"
git -C "$UNTRACKED_REGISTRY_REPO" rm -q docs/profiles/registry.yaml
git -C "$UNTRACKED_REGISTRY_REPO" commit -qm 'remove tracked registry'
cp "$TMP/untracked-registry.yaml" "$UNTRACKED_REGISTRY_REPO/docs/profiles/registry.yaml"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic "$UNTRACKED_REGISTRY_REPO/docs/profiles/demo.yaml" "$UNTRACKED_REGISTRY_REPO/docs/profiles/registry.yaml"
assert_eq "untracked registry exit" 3 "$CODE"
assert_contains "untracked registry message" "$OUTPUT" "registry is not tracked at pinned HEAD"

BOOL_TOPIC_REPO="$TMP/bool-topic-schema"
init_policy_repo "$BOOL_TOPIC_REPO" fast engineering
sed -i 's/^schema_version: 1$/schema_version: true/' "$BOOL_TOPIC_REPO/docs/profiles/demo.yaml"
run_capture python3 "$ROOT/lib/profile/policy.py" validate-topic-schema "$BOOL_TOPIC_REPO/docs/profiles/demo.yaml" "$BOOL_TOPIC_REPO/docs/profiles/registry.yaml"
assert_eq "topic boolean schema version exit" 2 "$CODE"
assert_contains "topic boolean schema version rejected" "$OUTPUT" "unsupported topic schema_version"

FALLBACK_REPO="$TMP/exact-fallback"
init_policy_repo "$FALLBACK_REPO" fast engineering
ENGINEERING_AVAILABLE='[{"id":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]'
run_capture python3 "$ROOT/lib/profile/policy.py" select "$FALLBACK_REPO/docs/profiles/demo.yaml" build "$ENGINEERING_AVAILABLE"
assert_eq "second sufficient profile selection exit" 0 "$CODE"
assert_eq "unavailable first profile falls through to second" '{"effort":"medium","model":"gpt-engineering","profile":"engineering","task":"build"}' "$OUTPUT"

LTE_REPO="$TMP/lte-comparator"
init_policy_repo "$LTE_REPO" expensive engineering
LTE_AVAILABLE='[{"id":"gpt-expensive","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]},{"id":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]'
run_capture python3 "$ROOT/lib/profile/policy.py" select "$LTE_REPO/docs/profiles/demo.yaml" build "$LTE_AVAILABLE"
assert_eq "lte decisive selection exit" 0 "$CODE"
assert_eq "high latency and cost fail lte" '{"effort":"medium","model":"gpt-engineering","profile":"engineering","task":"build"}' "$OUTPUT"

LIVE_CONTEXT_REPO="$TMP/live-context"
init_policy_repo "$LIVE_CONTEXT_REPO" engineering
sed -i 's/live_remaining_context: false/live_remaining_context: true/' "$LIVE_CONTEXT_REPO/docs/profiles/demo.yaml"
git -C "$LIVE_CONTEXT_REPO" add docs/profiles/demo.yaml
git -C "$LIVE_CONTEXT_REPO" commit -qm 'require live remaining context'
run_capture python3 "$ROOT/lib/profile/policy.py" select "$LIVE_CONTEXT_REPO/docs/profiles/demo.yaml" build "$ENGINEERING_AVAILABLE"
assert_eq "live remaining context exit" 4 "$CODE"
assert_contains "live remaining context message" "$OUTPUT" "requires live remaining-context confirmation"

DUPLICATE_MODELS='[{"id":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]},{"id":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]'
run_capture python3 "$ROOT/lib/profile/policy.py" select "$FALLBACK_REPO/docs/profiles/demo.yaml" build "$DUPLICATE_MODELS"
assert_eq "duplicate available model id exit" 4 "$CODE"
assert_contains "duplicate available model id message" "$OUTPUT" "duplicate available model id: gpt-engineering"

MISMATCHED_MODEL_FIELDS='[{"id":"gpt-engineering","model":"gpt-other","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]'
run_capture python3 "$ROOT/lib/profile/policy.py" select "$FALLBACK_REPO/docs/profiles/demo.yaml" build "$MISMATCHED_MODEL_FIELDS"
assert_eq "mismatched id and model exit" 4 "$CODE"
assert_contains "mismatched id and model message" "$OUTPUT" "model/list id and model disagree"

MISSING_EFFORT_METADATA='[{"id":"gpt-engineering"}]'
run_capture python3 "$ROOT/lib/profile/policy.py" select "$FALLBACK_REPO/docs/profiles/demo.yaml" build "$MISSING_EFFORT_METADATA"
assert_eq "missing effort metadata exit" 4 "$CODE"
assert_contains "missing effort metadata message" "$OUTPUT" "missing supported effort metadata"

MODEL_FIELD_AVAILABLE='[{"model":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]'
run_capture python3 "$ROOT/lib/profile/policy.py" select "$FALLBACK_REPO/docs/profiles/demo.yaml" build "$MODEL_FIELD_AVAILABLE"
assert_eq "documented model field selection exit" 0 "$CODE"
assert_eq "documented model field accepted" '{"effort":"medium","model":"gpt-engineering","profile":"engineering","task":"build"}' "$OUTPUT"

UNDOCUMENTED_TOP_LEVEL_EFFORTS='[{"id":"gpt-engineering","supported_efforts":["medium"]}]'
run_capture python3 "$ROOT/lib/profile/policy.py" select "$FALLBACK_REPO/docs/profiles/demo.yaml" build "$UNDOCUMENTED_TOP_LEVEL_EFFORTS"
assert_eq "undocumented top-level efforts rejected exit" 4 "$CODE"
assert_contains "undocumented top-level efforts rejected message" "$OUTPUT" "missing supported effort metadata"

UNDOCUMENTED_NESTED_EFFORT='[{"id":"gpt-engineering","supportedReasoningEfforts":[{"effort":"medium"}]}]'
run_capture python3 "$ROOT/lib/profile/policy.py" select "$FALLBACK_REPO/docs/profiles/demo.yaml" build "$UNDOCUMENTED_NESTED_EFFORT"
assert_eq "undocumented nested effort rejected exit" 4 "$CODE"
assert_contains "undocumented nested effort rejected message" "$OUTPUT" "reasoningEffort"

SELECT_REPO="$TMP/select"
init_policy_repo "$SELECT_REPO" fast weak engineering
AVAILABLE='[{"id":"gpt-weak","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]},{"id":"gpt-engineering","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]'
run_capture python3 "$ROOT/lib/profile/policy.py" select "$SELECT_REPO/docs/profiles/demo.yaml" build "$AVAILABLE"
assert_eq "fallback selection exit" 0 "$CODE"
assert_eq "unavailable and insufficient profiles skipped" '{"effort":"medium","model":"gpt-engineering","profile":"engineering","task":"build"}' "$OUTPUT"

INSUFFICIENT_REPO="$TMP/insufficient"
init_policy_repo "$INSUFFICIENT_REPO" weak
run_capture python3 "$ROOT/lib/profile/policy.py" select "$INSUFFICIENT_REPO/docs/profiles/demo.yaml" build "$AVAILABLE"
assert_eq "no sufficient profile exit" 4 "$CODE"
assert_contains "no sufficient profile message" "$OUTPUT" "no available sufficient profile"
assert_contains "insufficient dimension evidence" "$OUTPUT" "capability"

finish
