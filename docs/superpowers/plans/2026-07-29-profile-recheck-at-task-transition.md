---
review:
  plan_hash: b3b290977f3067fd
  last_run: 2026-07-30
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-29-profile-recheck-at-task-transition-intent.md
  spec: docs/superpowers/specs/2026-07-29-profile-recheck-at-task-transition-design.md
---

# Profile Recheck at Task Transition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route explicit tasks through a shared approved capacity registry and a directly read project manifest, with deterministic App Server selection and machine-local enforcement at every task boundary.

**Architecture:** icodex owns one tracked registry at `.codex-isolated/profiles/registry.yaml` and exposes it through an exact `$CODEX_HOME/profiles` symlink. Each target repository owns `docs/profiles/<topic>.yaml`; policy validation pins icodex HEAD and target HEAD independently, while runtime handoffs, decisions, and LoEn cache remain under `$CODEX_HOME/state/profile-routing/`. Explicit runner commands start App Server turns; ordinary interactive launches retain manual `/model` and `/status` handling.

**Tech Stack:** Bash, Python 3 standard library, strict project-owned YAML subset, Git plumbing, JSON-RPC over stdio, standalone Bash tests.

---

## File Map

- Modify `lib/profile/policy.py`: split Git authority snapshots, canonical shared-registry resolution, immutable policy metadata, and deterministic selection.
- Modify `tests/test_profile_policy.sh`: two-repository fixtures, authority/path failures, production policy, and stale-policy rejection.
- Modify `.gitignore`: whitelist only curated shared profile policy while keeping `.codex-homes/` ignored.
- Create `.codex-isolated/profiles/README.md`: shared registry contract and approval lifecycle.
- Create `.codex-isolated/profiles/registry.yaml`: single user-approved shared capacity registry.
- Modify `docs/profiles/README.md`: project-manifest contract and direct-read boundary.
- Delete `docs/profiles/registry.yaml`: remove stale project-local registry authority.
- Modify `docs/profiles/profile-recheck-at-task-transition.yaml`: split-authority reference and approved implementation tasks; no portable-history field or task.
- Modify `lib/config/isolated.sh`: exact managed-link validation and `$CODEX_HOME/profiles` wiring.
- Modify `tests/test_isolated.sh`: correct, idempotent, and wrong-target profile-link coverage.
- Create `lib/profile/state.py`: restrictive atomic handoffs, session decisions, exact LoEn cache tuple, invalidation, and cold-start detection.
- Create `tests/test_profile_state.sh`: state permissions, correlation, replay, isolation, cache, and deletion-recovery tests.
- Create `.codex-isolated/hooks/profile-transition.py`: protected-action authorization from correlated local evidence.
- Create `lib/profile/wiring.sh`: idempotent profile-hook composition.
- Create `tests/test_profile_hook.sh`: allow/deny, model-change, and interactive-fallback tests.
- Create `tests/test_profile_wiring.sh`: hook composition and idempotency tests.
- Create `lib/profile/app_server.py`: synchronous JSON-RPC process client and App Server adapters.
- Create `lib/profile/runner.py`: one-shot/orchestration sequencing, cold starts, and exact LoEn selection reuse.
- Create `lib/profile/profile.sh`: Bash runner entrypoints.
- Modify `lib/command/args.sh`: parse `--run-task` and `--orchestrate` without changing passthrough behavior.
- Modify `icodex.sh`: source profile modules, compose hook, and dispatch explicit profile modes after normal setup.
- Create `tests/test_profile_runner.sh`: fake App Server, transition, cold-start, and cache-request-count tests.
- Modify `tests/test_args.sh`: exact profile-command parsing and ordinary passthrough tests.
- Modify `tests/test_smoke.sh`: source/setup/dispatch order and absence of export/import commands.
- Modify `.codex-isolated/AGENTS.md`: orchestrated evidence branch versus ordinary interactive profile gate.
- Modify `docs/README.ru.md`: shared/project policy locations, commands, cold starts, and recovery.
- Modify `tests/test_workflow_boundaries.sh`: durable workflow wording and local-only state contract.
- Update iwiki pages `reference/model-and-reasoning-routing` and `plugin-and-hook-wiring` after behavior stabilizes.

## Requirement Coverage

| Spec requirement | Plan tasks |
|---|---|
| R1 Shared Versioned Capacity Registry | 1 |
| R2 Project-Local Topic Manifest | 1 |
| R3 Split Git Authority Validation | 1 |
| R4 Shared Profile Home Wiring | 2 |
| R5 Deterministic Profile Selection | 1, 5 |
| R6 App Server Task Runner | 5 |
| R7 Machine-Local State and Hook Enforcement | 3, 4, 5 |
| R8 Explicit Cold Starts | 3, 5 |
| R9 Documentation and Scope Boundary | 1, 5, 6 |

## Migration Rule

Commits `5d8c622` and `1e74dcc` remain in local history, but their policy layout is stale and must never become runtime authority. Task 1 reconciles them through normal forward commits: delete the project-local registry, replace the manifest schema, move the already approved registry bytes into the shared tracked directory, and replace tests that accept the stale layout. Do not reset, amend, rebase, or force-push those commits.

### Task 1: Migrate Policy to Split Git Authorities

**Closes:** R1, R2, R3, and policy-side R5. Produces the first valid shared registry plus direct project manifest and prevents the stale single-repository layout from being accepted.

**Files:**

- Modify: `lib/profile/policy.py`
- Modify: `tests/test_profile_policy.sh`
- Modify: `.gitignore`
- Create: `.codex-isolated/profiles/README.md`
- Create: `.codex-isolated/profiles/registry.yaml`
- Modify: `docs/profiles/README.md`
- Delete: `docs/profiles/registry.yaml`
- Modify: `docs/profiles/profile-recheck-at-task-transition.yaml`

- [ ] **Step 1: Write failing two-authority policy tests**

Replace the fixture layout in `tests/test_profile_policy.sh` with two Git repositories and one home link:

```bash
init_policy_pair() { # <shared-repo> <target-repo> <home> <preferred-profile> [preferred-profile]
  local shared_repo="$1" target_repo="$2" home="$3" registry hash
  shift 3
  registry="$shared_repo/.codex-isolated/profiles/registry.yaml"
  mkdir -p "$(dirname "$registry")" "$target_repo/docs/profiles" "$target_repo/docs/superpowers/plans" "$home"
  write_registry "$registry"
  ln -s "$shared_repo/.codex-isolated/profiles" "$home/profiles"
  hash="$(sha256sum "$registry" | awk '{print $1}')"
  write_topic "$target_repo/docs/profiles/demo.yaml" "$hash" "$@"
  printf '%s\n' '# Demo plan' >"$target_repo/docs/superpowers/plans/demo.md"
  git -C "$shared_repo" init -q -b main
  git -C "$shared_repo" config user.email test@example.com
  git -C "$shared_repo" config user.name Test
  git -C "$shared_repo" add .codex-isolated/profiles
  git -C "$shared_repo" commit -qm 'shared registry fixture'
  git -C "$target_repo" init -q -b main
  git -C "$target_repo" config user.email test@example.com
  git -C "$target_repo" config user.name Test
  git -C "$target_repo" add docs
  git -C "$target_repo" commit -qm 'target manifest fixture'
}
```

`write_topic` must emit exactly this authority object and omit `portable_history`:

```yaml
registry:
  authority: icodex-shared
  path: profiles/registry.yaml
  sha256: REGISTRY_SHA256
```

Invoke runtime validation with explicit authority inputs:

```bash
python3 "$ROOT/lib/profile/policy.py" validate-topic "$target_repo" "$home" "$shared_repo/.codex-isolated" "$target_repo/docs/profiles/demo.yaml" "$home/profiles/registry.yaml"
python3 "$ROOT/lib/profile/policy.py" select "$target_repo" "$home" "$shared_repo/.codex-isolated" "$target_repo/docs/profiles/demo.yaml" build "$available_json"
```

Add assertions for: independent immutable HEADs; dirty/untracked/symlink registry; dirty/untracked/symlink/pathspec context; wrong authority; absolute/traversal registry path; wrong home-link target; project-local `docs/profiles/registry.yaml` rejection; changed registry HEAD during target validation; changed target HEAD during registry validation; manifest SHA and both commit OIDs in successful snapshot output; deterministic fallback; duplicate `model/list`; missing effort metadata; and live remaining-context rejection.

- [ ] **Step 2: Run policy tests and verify the revised contract fails**

```bash
bash tests/test_profile_policy.sh
```

Expected: non-zero with assertions showing the existing CLI still assumes one repository and still requires `portable_history`.

- [ ] **Step 3: Refactor policy loading around explicit immutable snapshots**

Preserve the existing strict YAML parser, registry schema, availability parser, and dimension comparators. Replace `_PolicyPair` with these immutable public data objects in `lib/profile/policy.py`:

```python
@dataclass(frozen=True)
class GitBlobSnapshot:
    repo_root: Path
    commit_oid: str
    relative_path: str
    sha256: str
    data: bytes


@dataclass(frozen=True)
class ValidatedPolicy:
    registry: dict[str, object]
    manifest: dict[str, object]
    registry_commit: str
    registry_sha256: str
    registry_version: int
    target_commit: str
    manifest_sha256: str
    target_root: str
    topic: str
```

Add exact authority entrypoints:

```python
def snapshot_regular_blob(repo_root: Path, commit_oid: str, path: Path, label: str) -> GitBlobSnapshot:
    """Read one no-follow worktree file and require equality with one regular blob at commit_oid."""


def load_policy(
    target_root: Path,
    codex_home: Path,
    shared_root: Path,
    manifest_path: Path,
    registry_path: Path,
) -> ValidatedPolicy:
    """Pin both HEADs once, validate canonical paths, parse each snapshot once, and return immutable metadata."""
```

`load_policy` must enforce these resolved paths before reading bytes:

```python
expected_manifest = target_root.resolve() / "docs" / "profiles" / f"{topic}.yaml"
expected_registry = shared_root.resolve() / "profiles" / "registry.yaml"
home_registry = codex_home.resolve() / "profiles" / "registry.yaml"
if manifest_path.resolve() != expected_manifest:
    raise PolicyError(f"topic manifest path must be docs/profiles/{topic}.yaml", 3)
if registry_path.resolve() != expected_registry or home_registry.resolve() != expected_registry:
    raise PolicyError("registry must resolve through CODEX_HOME/profiles to shared profiles/registry.yaml", 3)
```

Resolve the registry repository root with `git -C <shared-root> rev-parse --show-toplevel`, require `<shared-root>` to equal its `.codex-isolated` directory, then resolve `registry_commit` from that repository. Resolve `target_commit` independently from `target_root` before either snapshot read. Use `git ls-tree --literal-pathspecs` plus `git cat-file blob`; do not use `git show HEAD:path` after pinning. Validate context inputs against `target_commit` only. Validate registry bytes against `registry_commit` only. Return the already parsed `ValidatedPolicy`; selection receives it and performs no file read.

- [ ] **Step 4: Replace manifest schema and CLI adapters**

The manifest exact top-level keys become:

```python
MANIFEST_KEYS = {
    "schema_version",
    "topic",
    "status",
    "registry",
    "context_inputs",
    "tasks",
}
REGISTRY_REFERENCE_KEYS = {"authority", "path", "sha256"}
```

Require `authority == "icodex-shared"`, `path == "profiles/registry.yaml"`, lowercase SHA-256, `status == "approved"`, and exact filename/topic match. Delete every parser branch and error mentioning `portable_history`.

Use these CLI forms:

```text
policy.py validate-registry <registry-path>
policy.py validate-topic-schema <target-root> <codex-home> <shared-root> <manifest-path> <registry-path>
policy.py validate-topic <target-root> <codex-home> <shared-root> <manifest-path> <registry-path>
policy.py select <target-root> <codex-home> <shared-root> <manifest-path> <task-id> <available-models-json>
```

`validate-topic-schema` may skip worktree-versus-HEAD equality only for the target manifest being prepared; it must still validate canonical paths, both repository identities, registry hash, context blob types at pinned target HEAD, and schema. Runtime `validate-topic` must require all worktree bytes equal the pinned blobs.

- [ ] **Step 5: Run focused policy tests**

```bash
bash tests/test_profile_policy.sh
```

Expected: `FAIL=0` and exit 0 for temporary two-repository fixtures; production-policy assertions still fail because migration files are not yet written.

- [ ] **Step 6: Write curated shared registry location and ignore rules**

Move the previously user-approved registry bytes unchanged from `docs/profiles/registry.yaml` to `.codex-isolated/profiles/registry.yaml`. Its SHA-256 must remain:

```text
7ef5c802e43fc96ecc23260e0460aa7a0df568c21dd369d86947d8e935d16a92
```

Add only this whitelist to `.gitignore` beside other curated `.codex-isolated` entries:

```gitignore
!.codex-isolated/profiles/
!.codex-isolated/profiles/**
```

Create `.codex-isolated/profiles/README.md` stating: registry is shared policy; changes require explicit approval; manifests pin byte hash; directory must contain no manifests, runtime state, auth, cache, binaries, sessions, or live measurements. Update `docs/profiles/README.md` to state that this directory contains direct-read project manifests only and never a registry or runtime-state copy.

- [ ] **Step 7: HUMAN CHECKPOINT — approve revised project manifest bytes**

Present the complete revised `docs/profiles/profile-recheck-at-task-transition.yaml` and SHA-256. It must pin `authority: icodex-shared`, `path: profiles/registry.yaml`, the approved registry hash, current intent/spec/plan context inputs, and exactly these routed task IDs:

```text
shared-profile-home-wiring
machine-local-routing-state
transition-gate-hook-and-wiring
app-server-task-runner
documentation-verification-and-result-reconciliation
```

Present these complete proposed bytes, substituting no values:

```yaml
schema_version: 1
topic: profile-recheck-at-task-transition
status: approved
registry:
  authority: icodex-shared
  path: profiles/registry.yaml
  sha256: 7ef5c802e43fc96ecc23260e0460aa7a0df568c21dd369d86947d8e935d16a92
context_inputs:
  - docs/superpowers/intents/2026-07-29-profile-recheck-at-task-transition-intent.md
  - docs/superpowers/specs/2026-07-29-profile-recheck-at-task-transition-design.md
  - docs/superpowers/plans/2026-07-29-profile-recheck-at-task-transition.md
tasks:
  - id: shared-profile-home-wiring
    requirements:
      capability: strongest
      context: medium
      latency: high
      cost: high
      throughput: low
    live_remaining_context: false
    preferred_profiles:
      - deep
  - id: machine-local-routing-state
    requirements:
      capability: strongest
      context: medium
      latency: high
      cost: high
      throughput: low
    live_remaining_context: false
    preferred_profiles:
      - deep
  - id: transition-gate-hook-and-wiring
    requirements:
      capability: strongest
      context: medium
      latency: high
      cost: high
      throughput: low
    live_remaining_context: false
    preferred_profiles:
      - deep
  - id: app-server-task-runner
    requirements:
      capability: strongest
      context: medium
      latency: high
      cost: high
      throughput: low
    live_remaining_context: false
    preferred_profiles:
      - deep
  - id: documentation-verification-and-result-reconciliation
    requirements:
      capability: strongest
      context: medium
      latency: high
      cost: high
      throughput: low
    live_remaining_context: false
    preferred_profiles:
      - deep
```

The manifest contains neither a `portable_history` field nor a portable-history task. Stop until user approves exact bytes; plan approval does not count as manifest approval.

- [ ] **Step 8: Replace stale production policy and validate pre-commit schema**

Delete `docs/profiles/registry.yaml`, write approved manifest bytes, and extend production assertions in `tests/test_profile_policy.sh`:

```bash
PRODUCTION_REGISTRY="$ROOT/.codex-isolated/profiles/registry.yaml"
PRODUCTION_TOPIC="$ROOT/docs/profiles/profile-recheck-at-task-transition.yaml"
assert_exit "shared registry not ignored by policy whitelist" 1 git -C "$ROOT" check-ignore -q --no-index "$PRODUCTION_REGISTRY"
assert_exit "stale project registry absent" 1 test -e "$ROOT/docs/profiles/registry.yaml"
assert_exit "portable history absent from manifest" 1 grep -q 'portable_history\|portable-history' "$PRODUCTION_TOPIC"
python3 "$ROOT/lib/profile/policy.py" validate-registry "$PRODUCTION_REGISTRY"
```

For schema validation, create a temporary home whose `profiles` link targets `$ROOT/.codex-isolated/profiles`; use the real target root and shared root. Expected: registry and schema commands exit 0, stale path checks pass.

- [ ] **Step 9: Commit migration, then validate committed production authorities**

```bash
git add .gitignore .codex-isolated/profiles docs/profiles lib/profile/policy.py tests/test_profile_policy.sh
git commit -m "feat(profile): split routing policy authorities"
bash tests/test_profile_policy.sh
```

Expected: commit succeeds; `FAIL=0`; runtime validation reports distinct `registry_commit` and `target_commit`; `git ls-files docs/profiles/registry.yaml` prints nothing.

### Task 2: Wire the Shared Registry into Every Project Home

**Closes:** R4. Makes the shared registry discoverable at one stable home-relative path without creating any home manifest.

**Files:**

- Modify: `lib/config/isolated.sh`
- Modify: `tests/test_isolated.sh`

- [ ] **Step 1: Write failing managed-link tests**

Add a shared profile fixture and assertions to `tests/test_isolated.sh`:

```bash
mkdir -p "$ICODEX_SHARED_DIR/profiles"
printf 'schema_version: 1\n' >"$ICODEX_SHARED_DIR/profiles/registry.yaml"
setup_codex_home
assert_exit "profiles symlink" 0 test -L "$ICODEX_HOME_DIR/profiles"
assert_eq "profiles exact target" "$ICODEX_SHARED_DIR/profiles" "$(readlink "$ICODEX_HOME_DIR/profiles")"
assert_exit "home manifest absent" 1 test -e "$ICODEX_HOME_DIR/profiles/demo.yaml"
```

Capture `stat -c '%i:%Y'` for a correct link, rerun setup, and require unchanged output. Replace it with a wrong symlink, rerun setup, and require exact repair.

- [ ] **Step 2: Run isolated-home test and verify failure**

```bash
bash tests/test_isolated.sh
```

Expected: failure because `setup_codex_home` does not create `profiles` and `_link_shared` accepts any existing symlink.

- [ ] **Step 3: Make the shared-link helper exact and add profiles wiring**

Change `_link_shared` in `lib/config/isolated.sh` to accept only the exact raw target:

```bash
_link_shared() { # <name>
  local name="$1"
  local target="$ICODEX_HOME_DIR/$name" src="$ICODEX_SHARED_DIR/$name"
  if [[ -L "$target" && "$(readlink "$target")" == "$src" ]]; then
    return 0
  fi
  rm -rf "$target" 2>/dev/null || true
  ln -s "$src" "$target"
}
```

Add `_link_shared profiles` beside other curated shared directories. Do not create `$ICODEX_HOME/docs/profiles`, copy a manifest, or create routing state during home setup.

- [ ] **Step 4: Run isolated and smoke tests**

```bash
bash tests/test_isolated.sh
bash tests/test_smoke.sh
```

Expected: both exit 0 and report `FAIL=0`.

- [ ] **Step 5: Commit shared home wiring**

```bash
git add lib/config/isolated.sh tests/test_isolated.sh
git commit -m "feat(profile): link shared registry into homes"
```

### Task 3: Implement Machine-Local Handoffs, Decisions, and Cache

**Closes:** state-side R7 and R8. Makes authorization single-use and session-bound while treating missing state as an empty local cold start.

**Files:**

- Create: `lib/profile/state.py`
- Create: `tests/test_profile_state.sh`

- [ ] **Step 1: Write failing state API tests**

Create `tests/test_profile_state.sh` with Python fixture calls covering:

```python
create_handoff(state_root, request)
consume_handoff(state_root, run_id, sequence, session_id, payload_model)
load_decision(state_root, session_id)
save_selection_cache(state_root, run_id, selection_tuple, session_id)
load_selection_cache(state_root, run_id)
cache_matches(cache, selection_tuple, authorized_decision)
invalidate_run(state_root, run_id)
detect_cold_start(state_root)
```

Assert `0700` state directories and `0600` JSON files; same-directory atomic replace; one consumer; replay, cross-run, cross-task, sequence, hash, request-ID, and model mismatch rejection; concurrent runners cannot consume each other's handoffs; exact tuple match; every tuple-field change misses; missing decision misses; observed-model change misses; deletion returns cold start with no inferred task or history.

- [ ] **Step 2: Run state test and verify red state**

```bash
bash tests/test_profile_state.sh
```

Expected: non-zero because `lib/profile/state.py` is missing.

- [ ] **Step 3: Implement restrictive JSON storage and complete cache tuple**

Create `lib/profile/state.py` with these exact data fields:

```python
@dataclass(frozen=True)
class SelectionTuple:
    target_root: str
    topic: str
    task_id: str
    requirement_fingerprint: str
    registry_commit: str
    registry_version: int
    registry_hash: str
    manifest_commit: str
    manifest_hash: str
    profile: str
    model: str
    effort: str


class StateError(Exception):
    pass


def routing_root(codex_home: Path) -> Path:
    return codex_home / "state" / "profile-routing"


def detect_cold_start(state_root: Path) -> bool:
    return not state_root.exists()
```

Implement `atomic_json_write` with a same-directory `os.open(temp_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)` temporary file, `flush`, `os.fsync`, `os.chmod(0o600)`, `os.replace`, and directory `fsync`. Create directories at `0700`. Use per-handoff lock files created with `O_CREAT | O_EXCL`; atomically move consumed handoffs out of `pending/` before writing `decisions/<session-id>.json`.

- [ ] **Step 4: Implement exact correlation, cache reuse, and invalidation**

Require handoff keys: run ID, sequence, canonical target root, topic, task, both commit OIDs, both hashes, registry version, selected profile, exact model/effort, App Server request ID, and a SHA-256 of the exact `turn/start` request. Persist no prompt, response, transcript, auth path, session history, or tool output.

`cache_matches` must compare `dataclasses.asdict(expected)` with the stored tuple, require the same run ID and session ID, and require `decision["authorized"] is True` plus `decision["observed_model"] == expected.model`. Missing or malformed state returns `False`; correlation or replay errors raise `StateError`.

- [ ] **Step 5: Run focused state tests**

```bash
bash tests/test_profile_state.sh
```

Expected: `FAIL=0`, exit 0, and deletion case reports a cold start without recovered progress.

- [ ] **Step 6: Commit local state support**

```bash
git add lib/profile/state.py tests/test_profile_state.sh
git commit -m "feat(profile): persist local routing evidence"
```

### Task 4: Enforce Profile Decisions in Existing Hook Wiring

**Closes:** hook-side R7 and R9. Adds a validation-only guard without weakening secret, caveman, chain, LoEn, or iwiki behavior.

**Files:**

- Create: `.codex-isolated/hooks/profile-transition.py`
- Create: `lib/profile/wiring.sh`
- Create: `tests/test_profile_hook.sh`
- Create: `tests/test_profile_wiring.sh`
- Modify: `icodex.sh`
- Modify: `tests/test_smoke.sh`

- [ ] **Step 1: Write failing hook behavior tests**

Feed JSON hook payloads with temporary `ICODEX_PROFILE_RUN_ID`, `ICODEX_PROFILE_SEQUENCE`, `ICODEX_PROFILE_REQUEST_ID`, `ICODEX_ROOT`, and `CODEX_HOME`. Use this protected payload:

```json
{"session_id":"s1","cwd":"/repo","hook_event_name":"PreToolUse","model":"gpt-5.6-terra","tool_name":"Write","tool_input":{"file_path":"x"}}
```

Assert: matching handoff authorizes once; later protected action reuses matching decision; replay, missing handoff, wrong run/task/sequence/request/hash, or changed model denies; direct unrelated `Read` allows; `rg --files` allows; unknown shell command denies; reading an execution skill `SKILL.md` is protected; no routed env allows ordinary interactive work without claiming routed authorization; hook never reads `transcript_path` and never invokes network or `/model`.

- [ ] **Step 2: Write failing wiring-composition tests**

Create `tests/test_profile_wiring.sh` following the existing wiring tests. Compose base secret hooks, caveman, chain/IDD, LoEn, iwiki, then profile wiring. Assert valid JSON, one profile hook with matcher `*`, idempotent bytes, and preservation of every existing hook entry.

- [ ] **Step 3: Run hook tests and verify red state**

```bash
bash tests/test_profile_hook.sh
bash tests/test_profile_wiring.sh
```

Expected: both fail because hook and wiring module are missing.

- [ ] **Step 4: Implement protected-action classification and state binding**

Create `.codex-isolated/hooks/profile-transition.py` with:

```python
READ_ONLY_TOOLS = {"Read", "Glob", "Grep"}
MUTATING_TOOLS = {"Write", "Edit", "apply_patch"}


def is_protected(event: dict[str, object]) -> bool:
    """Return false only for a closed read-only discovery allowlist."""


def validate_event(event: dict[str, object], environ: Mapping[str, str]) -> dict[str, object]:
    """Consume the correlated handoff or validate its persisted session decision."""
```

For Bash, reject shell operators, redirections, substitutions, assignments, and compound syntax before parsing argv. Allow only argv prefixes `rg`, `sed -n`, `git status`, `git diff`, `git show`, `git log`, `git branch --show-current`, `git rev-parse`, `tree`, and `find` without action flags. Unknown syntax/tool/skill is protected. Resolve state code only from absolute `ICODEX_ROOT/lib/profile/state.py`; never use cwd or transcript paths. Return standard hook JSON allowing a match or denying with one remediation: restart through `icodex --run-task <topic> <task-id>`.

- [ ] **Step 5: Implement idempotent profile-hook composition**

Create `lib/profile/wiring.sh` using the established JSON merge/write-if-changed pattern. Add exactly one `PreToolUse` command:

```json
{"matcher":"*","hooks":[{"type":"command","command":"python3 \"$CODEX_HOME/hooks/profile-transition.py\"","timeout":30,"statusMessage":"Checking routed profile evidence"}]}
```

Source `profile/wiring` in `icodex.sh` and call `ensure_profile_wiring` after existing hook wiring. Do not replace or reorder unrelated entries.

- [ ] **Step 6: Run hook regressions**

```bash
bash tests/test_profile_hook.sh
bash tests/test_profile_wiring.sh
bash tests/test_idd_wiring.sh
bash tests/test_smoke.sh
```

Expected: all commands exit 0 with `FAIL=0`; wiring test proves LoEn and iwiki hook entries remain byte-equivalent.

- [ ] **Step 7: Commit hook enforcement**

```bash
git add .codex-isolated/hooks/profile-transition.py lib/profile/wiring.sh icodex.sh tests/test_profile_hook.sh tests/test_profile_wiring.sh tests/test_smoke.sh
git commit -m "feat(profile): enforce routed task evidence"
```

### Task 5: Add App Server Task Runner and Explicit Commands

**Closes:** R5, R6, remaining R7, and R8. Starts explicit tasks with selected profile, advances only on structured completion, and treats missing local state as a new run.

**Files:**

- Create: `lib/profile/app_server.py`
- Create: `lib/profile/runner.py`
- Create: `lib/profile/profile.sh`
- Modify: `lib/profile/state.py`
- Create: `tests/test_profile_runner.sh`
- Modify: `tests/test_profile_state.sh`
- Modify: `lib/command/args.sh`
- Modify: `icodex.sh`
- Modify: `tests/test_args.sh`
- Modify: `tests/test_smoke.sh`

- [ ] **Step 1: Write failing CLI parsing tests**

Extend `tests/test_args.sh` with exact cases:

```text
--run-task demo build -> ICODEX_CMD=profile-run-task, ICODEX_PROFILE_TOPIC=demo, ICODEX_PROFILE_TASK=build
--orchestrate demo -> ICODEX_CMD=profile-orchestrate, ICODEX_PROFILE_TOPIC=demo
--run-task with missing topic/task -> non-zero
--orchestrate with missing topic -> non-zero
ordinary --model gpt-x -> unchanged passthrough
--export-profile-history and --import-profile-history -> ordinary passthrough, never wrapper commands
```

- [ ] **Step 2: Write fake App Server and runner tests**

Create `tests/test_profile_runner.sh`. Fake executable reads newline-delimited JSON and handles `initialize`, `model/list`, `thread/start`, and `turn/start`, recording every request. Require `turn/start.params` to contain exact `model`, `effort`, `cwd`, and:

```json
{"additionalProperties":false,"properties":{"evidence":{"items":{"type":"string"},"type":"array"},"summary":{"type":"string"},"transition":{"enum":["complete","needs_input","blocked"],"type":"string"}},"required":["transition","summary","evidence"],"type":"object"}
```

Test: cold `--run-task` starts only requested task with fresh run ID; cold `--orchestrate` prints `Starting new run from first task: <id>` and starts first declared task; `complete` advances exactly once; `needs_input`, `blocked`, malformed output, interruption, or server error never advances. Verify no home manifest is read or created.

For LoEn reuse, seed an authorized session decision and exact cache tuple. Assert second same-run iteration makes zero additional `model/list` requests. Change each tuple field one at a time, delete state, change run ID, and change observed model; each case must add one `model/list` request and create a new handoff.

Test orchestration-state safety directly: same-topic concurrent starts allow only one executor, while different topics retain independent restrictive progress files and resume independently. A failed warm attempt keeps its task position, increments the attempt sequence, and retires only its own handoff, decision, and locks through the hardened state API. Symlink, FIFO, hardlink, malformed-state, absolute-ID, traversal-ID, and consume-versus-retire races must fail closed without deleting external or unrelated state.

- [ ] **Step 3: Run CLI and runner tests and verify red state**

```bash
bash tests/test_args.sh
bash tests/test_profile_runner.sh
```

Expected: new CLI assertions fail and runner files are missing.

- [ ] **Step 4: Implement strict JSON-RPC process client**

Create `lib/profile/app_server.py` with:

```python
class AppServerError(Exception):
    pass


class AppServerClient:
    def __init__(self, command: list[str], cwd: Path):
        self.command = command
        self.cwd = cwd
        self.next_request_id = 1

    def request(
        self,
        method: str,
        params: dict[str, object],
        before_send: Callable[[int, dict[str, object]], None] | None = None,
    ) -> dict[str, object]:
        """Allocate an ID, persist correlation through before_send, flush one request, and return its matching result."""

    def wait_for_turn(self, turn_id: str) -> dict[str, object]:
        """Consume validated notifications until the requested turn reaches a terminal state."""
```

Use `subprocess.Popen` stdio pipes, monotonically increasing integer IDs, exact response correlation, bounded shutdown, and captured stderr. Validate notification object shape before ignoring unrelated events. Call `before_send` after building the exact request and immediately before writing; callback failure must write no App Server request.

- [ ] **Step 5: Implement policy resolution, selection, and cold run sequencing**

Create `lib/profile/runner.py` with these boundaries:

```python
TRANSITION_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "transition": {"type": "string", "enum": ["complete", "needs_input", "blocked"]},
        "summary": {"type": "string"},
        "evidence": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["transition", "summary", "evidence"],
}


def run_task(config: RunnerConfig, topic: str, task_id: str) -> int:
    """Start exactly one explicit task and return without selecting a successor."""


def orchestrate(config: RunnerConfig, topic: str) -> int:
    """Start or continue only local run state and advance on structured complete."""
```

Resolve manifest only as `target_root / "docs/profiles" / f"{topic}.yaml"`; resolve registry only as `codex_home / "profiles/registry.yaml"` plus exact shared-root check. Validate the sealed policy and current manifest task position before every orchestration attempt so mutable local state cannot select work before authority checks. Store progress in restrictive per-topic local files so independent topics cannot overwrite each other. On cache miss: call `model/list`, select first sufficient preferred profile, compute requirement fingerprint from canonical sorted JSON, and build the full `SelectionTuple`. On exact LoEn cache hit: reuse selection without a second `model/list`, but only when the freshly validated full tuple, same run namespace, and matching authorized session decision all agree. Failed attempts retain the current task with a new sequence and retire exact correlated evidence only through an exclusive, descriptor-anchored state operation that is linearized with hook consumption.

Allocate request ID first through `AppServerClient.request`; in `before_send`, write handoff containing SHA-256 of canonical exact request plus explicit model/effort/cwd. Export only run/sequence/request correlation variables to App Server child environment. A new state root always creates a fresh run ID. Never infer previous task completion from Git or manifest.

- [ ] **Step 6: Wire Bash commands after normal setup**

Create `lib/profile/profile.sh`:

```bash
run_profile_task() {
  python3 "$ICODEX_ROOT/lib/profile/runner.py" run-task --target-root "$ICODEX_PROJECT_ROOT" --codex-home "$CODEX_HOME" --shared-root "$ICODEX_SHARED_DIR" --binary "$ICODEX_BIN" --topic "$ICODEX_PROFILE_TOPIC" --task "$ICODEX_PROFILE_TASK"
}

run_profile_orchestrator() {
  python3 "$ICODEX_ROOT/lib/profile/runner.py" orchestrate --target-root "$ICODEX_PROJECT_ROOT" --codex-home "$CODEX_HOME" --shared-root "$ICODEX_SHARED_DIR" --binary "$ICODEX_BIN" --topic "$ICODEX_PROFILE_TOPIC"
}
```

Parse exact arity in `lib/command/args.sh`. Source `profile/profile` in `icodex.sh`; after normal home, trust, permission, hooks, binary, CLI tools, proxy, PII, and telemetry setup, dispatch `profile-run-task` or `profile-orchestrate` instead of interactive launch. App Server command is `"$ICODEX_BIN" app-server`; when PII masking is active, reuse existing proxy startup/cleanup and exact `openai_base_url` override.

- [ ] **Step 7: Run focused runner and wrapper tests**

```bash
bash tests/test_args.sh
bash tests/test_profile_runner.sh
bash tests/test_profile_state.sh
bash tests/test_smoke.sh
```

Expected: all exit 0 with `FAIL=0`; fake request log proves exact one-shot/orchestration counts and zero second `model/list` on exact LoEn cache reuse.

- [ ] **Step 8: Commit explicit task runner**

```bash
git add lib/profile/app_server.py lib/profile/runner.py lib/profile/profile.sh lib/profile/state.py lib/command/args.sh icodex.sh tests/test_args.sh tests/test_profile_runner.sh tests/test_profile_state.sh tests/test_smoke.sh
git commit -m "feat(profile): orchestrate App Server tasks"
```

### Task 6: Align Durable Guidance and Reconcile the Result

**Closes:** R9 and verifies R1–R8 as one end-to-end behavior set.

**Files:**

- Modify: `.codex-isolated/AGENTS.md`
- Modify: `docs/README.ru.md`
- Modify: `tests/test_workflow_boundaries.sh`
- Modify: `tests/test_smoke.sh`
- Update through iwiki MCP: `reference/model-and-reasoning-routing`
- Update through iwiki MCP: `plugin-and-hook-wiring`

- [ ] **Step 1: Write failing documentation and scope-boundary tests**

Extend `tests/test_workflow_boundaries.sh` and `tests/test_smoke.sh` to require these exact distinctions:

```text
shared registry authority: .codex-isolated/profiles/registry.yaml
project manifest authority: <target-repository>/docs/profiles/<topic>.yaml
orchestrated work: validated split policy plus correlated local handoff
interactive work: manual /model and /status confirmation remains required
missing state: new cold run, never cross-machine continuation
hook: validates evidence, never selects or changes model
portable history/export/import: out of scope
.codex-homes/: fully ignored
```

Assert help documents only `--run-task` and `--orchestrate` as profile wrapper commands. Assert `git ls-files` returns no `.codex-homes/`, `auth.json`, SQLite, raw session, cache, temp, or stale `docs/profiles/registry.yaml` path.

- [ ] **Step 2: Run boundary tests and verify red state**

```bash
bash tests/test_workflow_boundaries.sh
bash tests/test_smoke.sh
```

Expected: new assertions fail before durable guidance and help text are updated.

- [ ] **Step 3: Update `.codex-isolated/AGENTS.md` and user docs**

Split Task Transition Gate into two explicit branches:

```text
Orchestrated branch: runner validates shared registry and direct project manifest, then the hook accepts only correlated local handoff/session evidence. Matching routed evidence replaces manual /status confirmation for that protected task only.

Interactive branch: retain route classification, /model switch request, /status confirmation, downgrade/escalation handling, and critical-migration rules.
```

Document in `docs/README.ru.md`: policy locations; exact home symlink; two independent Git commits; manifest approval and registry repin lifecycle; command examples; cold `--run-task`; cold `--orchestrate` from first task; local state deletion recovery; actionable dirty/hash/path/model failures; no home manifest; no portable session history. Update CLI help with the two commands and their exact arguments.

- [ ] **Step 4: Run focused integration checks**

```bash
bash tests/test_profile_policy.sh
bash tests/test_isolated.sh
bash tests/test_profile_state.sh
bash tests/test_profile_hook.sh
bash tests/test_profile_wiring.sh
bash tests/test_profile_runner.sh
bash tests/test_args.sh
bash tests/test_smoke.sh
bash tests/test_workflow_boundaries.sh
bash tests/test_idd_wiring.sh
```

Expected: every command exits 0 and every test reports `FAIL=0`.

- [ ] **Step 5: Update iwiki after behavior is verified**

Use `wiki_update_page` for `reference/model-and-reasoning-routing` and `plugin-and-hook-wiring`. Record only implemented command semantics, split authorities, home symlink, cold-start behavior, local-only state/cache, hook composition, and interactive fallback. Run `wiki_lint`.

Expected: no broken references, orphan/stale pages, missing sources, or tag drift caused by this change.

- [ ] **Step 6: Run full repository and tracking verification**

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
git diff --check
git ls-files .codex-homes
git ls-files '.codex-isolated/auth.json' '.codex-isolated/state/**' '.codex-isolated/sessions/**' '*.sqlite' '*.sqlite3'
git ls-files docs/profiles/registry.yaml
git status --short
```

Expected: full suite exits 0; diff check clean; all three tracking queries print nothing; status contains only intended closeout metadata or is clean.

- [ ] **Step 7: Commit durable guidance**

```bash
git add .codex-isolated/AGENTS.md docs/README.ru.md lib/command/args.sh tests/test_workflow_boundaries.sh tests/test_smoke.sh
git commit -m "docs(profile): document split routing authorities"
```

- [ ] **Step 8: Run chain result reconciliation**

Run `$check-chain result docs/superpowers/plans/2026-07-29-profile-recheck-at-task-transition.md`.

Expected: `OK`; result evidence covers R1–R9; stale commits are reconciled by later commits; topic row becomes `done` with `Result: OK` and current date.

- [ ] **Step 9: Commit machine-readable result closeout**

```bash
git add docs/superpowers/plans/2026-07-29-profile-recheck-at-task-transition.md docs/TODO.md
git commit -m "docs(result): close profile transition orchestration"
```

Expected: commit contains matching result-check metadata and closed topic row; no runtime state or session artifact is staged.
