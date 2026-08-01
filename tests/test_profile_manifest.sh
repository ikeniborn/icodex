#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

HELPER="$ROOT/lib/profile/manifest.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

project="$tmp/project"
registry="$tmp/registry.yaml"
mkdir -p "$project/docs/superpowers/intents"
cp "$ROOT/.codex-isolated/profiles/registry.yaml" "$registry"
printf '%s\n' '# intent' > "$project/docs/superpowers/intents/demo-intent.md"

bootstrap() { # <topic> <status>
  python3 "$HELPER" bootstrap --project-root "$project" --registry "$registry" \
    --topic "$1" --intent docs/superpowers/intents/demo-intent.md --status "$2"
}

expand() { # <topic> <route>
  python3 "$HELPER" expand --project-root "$project" --registry "$registry" \
    --topic "$1" --route "$2"
}

assert_exit "bootstrap writes direct manifest" 0 bootstrap direct-profile draft
direct_manifest="$project/docs/profiles/direct-profile.yaml"
assert_contains "bootstrap records topic" "$(cat "$direct_manifest")" 'topic: direct-profile'
assert_contains "bootstrap records draft status" "$(cat "$direct_manifest")" 'status: draft'
assert_contains "bootstrap records intent input" "$(cat "$direct_manifest")" '  - docs/superpowers/intents/demo-intent.md'
assert_contains "bootstrap starts intent selection" "$(cat "$direct_manifest")" '  - id: intent-profile-selection'
assert_exit "expand direct route" 0 expand direct-profile direct
assert_eq "direct route task order" "direct-work" "$(awk '/^  - id: / { print $3 }' "$direct_manifest" | tail -n +2 | paste -sd, -)"
assert_contains "direct route selects engineering" "$(cat "$direct_manifest")" '      - engineering'

special_intent='docs/superpowers/intents/intent # note: example.md'
printf '%s\n' '# special intent' > "$project/$special_intent"
assert_exit "bootstrap quotes YAML-significant intent path" 0 python3 "$HELPER" bootstrap --project-root "$project" --registry "$registry" --topic special-input --intent "$special_intent" --status draft
special_manifest="$project/docs/profiles/special-input.yaml"
special_context="$(PYTHONPATH="$ROOT/lib/profile" python3 - "$special_manifest" <<'PY'
from pathlib import Path
import sys
from policy import parse_yaml_subset
print(parse_yaml_subset(Path(sys.argv[1]).read_text())['context_inputs'][0])
PY
)"
assert_eq "quoted intent parses without YAML changes" "$special_intent" "$special_context"
assert_exit "quoted intent manifest validates strict YAML" 0 env PYTHONPATH="$ROOT/lib/profile" python3 -c 'from pathlib import Path; from policy import parse_yaml_subset; import sys; parse_yaml_subset(Path(sys.argv[1]).read_text())' "$special_manifest"

printf '%s\n' '# Profile contexts' > "$project/docs/profiles/README.md"
assert_exit "direct bootstrap creates direct-only manifest" 0 python3 "$HELPER" bootstrap --project-root "$project" --registry "$registry" --topic direct-bootstrap --intent docs/profiles/README.md --status approved --route direct
direct_bootstrap_manifest="$project/docs/profiles/direct-bootstrap.yaml"
assert_eq "direct bootstrap has only direct work" "direct-work" "$(awk '/^  - id: / { print $3 }' "$direct_bootstrap_manifest")"
assert_contains "direct bootstrap is approved" "$(cat "$direct_bootstrap_manifest")" 'status: approved'
assert_contains "direct bootstrap uses README context" "$(cat "$direct_bootstrap_manifest")" '  - docs/profiles/README.md'

assert_exit "bootstrap writes full manifest" 0 bootstrap full-profile approved
full_manifest="$project/docs/profiles/full-profile.yaml"
assert_exit "expand full route" 0 expand full-profile full
assert_eq "full route task order" "intent-profile-selection,spec-design,plan-writing,implementation,result-reconciliation" "$(awk '/^  - id: / { print $3 }' "$full_manifest" | paste -sd, -)"
assert_eq "full route profile order" "engineering,synthesis,synthesis,engineering,engineering" "$(awk '/^      - / { print $2 }' "$full_manifest" | paste -sd, -)"
full_hash_before="$(sha256sum "$full_manifest" | awk '{print $1}')"
assert_exit "full expansion is idempotent" 0 expand full-profile full
assert_eq "idempotence preserves bytes" "$full_hash_before" "$(sha256sum "$full_manifest" | awk '{print $1}')"

sed -i '/- id: implementation/,/- id: result-reconciliation/ s/- engineering/- deep/' "$full_manifest"
conflict_hash_before="$(sha256sum "$full_manifest" | awk '{print $1}')"
assert_exit "conflicting canonical task fails" 2 expand full-profile full
assert_eq "conflict leaves manifest unchanged" "$conflict_hash_before" "$(sha256sum "$full_manifest" | awk '{print $1}')"

assert_exit "bad route fails" 2 expand direct-profile invalid
assert_exit "bad topic fails" 2 bootstrap Not-Canonical draft
assert_exit "missing registry fails" 2 python3 "$HELPER" bootstrap --project-root "$project" --registry "$tmp/missing.yaml" --topic missing-registry --intent docs/superpowers/intents/demo-intent.md --status draft
printf '%s\n' 'topic: malformed' > "$project/docs/profiles/malformed.yaml"
assert_exit "malformed manifest fails" 2 expand malformed direct

escaped_project="$tmp/escaped-project"
external_profiles="$tmp/external-profiles"
mkdir -p "$escaped_project/docs/superpowers/intents" "$external_profiles"
printf '%s\n' '# escaped intent' > "$escaped_project/docs/superpowers/intents/demo-intent.md"
ln -s "$external_profiles" "$escaped_project/docs/profiles"
assert_exit "bootstrap rejects symlinked profile directory" 2 python3 "$HELPER" bootstrap --project-root "$escaped_project" --registry "$registry" --topic escape-bootstrap --intent docs/superpowers/intents/demo-intent.md --status draft
assert_exit "bootstrap leaves external profile directory unchanged" 0 test ! -e "$external_profiles/escape-bootstrap.yaml"
sed 's/topic: direct-profile/topic: escape-expand/' "$direct_manifest" > "$external_profiles/escape-expand.yaml"
escaped_hash_before="$(sha256sum "$external_profiles/escape-expand.yaml" | awk '{print $1}')"
assert_exit "expand rejects symlinked profile directory" 2 python3 "$HELPER" expand --project-root "$escaped_project" --registry "$registry" --topic escape-expand --route full
assert_eq "expand leaves external manifest unchanged" "$escaped_hash_before" "$(sha256sum "$external_profiles/escape-expand.yaml" | awk '{print $1}')"

finish
