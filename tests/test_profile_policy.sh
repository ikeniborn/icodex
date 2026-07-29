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
