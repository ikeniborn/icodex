---
review:
  plan_hash: 18e884530a192064
  last_run: 2026-07-29
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

**Goal:** Add committed profile policy, deterministic App Server task routing, hook enforcement, and portable cross-machine task history while preserving ordinary interactive Codex launches.

**Architecture:** A dependency-free Python profile layer validates tracked YAML policy, selects the first available sufficient profile, manages one-time state, and speaks App Server JSON-RPC. Bash wrapper modules expose explicit commands and merge a validation-only hook into existing hook wiring. Tracked policy under `docs/profiles/` remains separate from disposable state under `$CODEX_HOME/state/profile-routing/`.

**Tech Stack:** Bash, Python 3 standard library, JSON-RPC over stdio, strict project-owned YAML subset, Git, standalone Bash tests.

---

## File Map

- Create `lib/profile/policy.py`: strict YAML-subset parser, schema checks, Git checks,
  capacity comparison, and deterministic selection.
- Create `lib/profile/state.py`: restrictive atomic files, one-time handoffs, session
  decisions, cache keys, and portable bundle validation.
- Create `lib/profile/app_server.py`: synchronous JSON-RPC process client and documented
  App Server method adapters.
- Create `lib/profile/runner.py`: one-shot/orchestration sequencing, structured result
  handling, LoEn selection reuse, export, and import.
- Create `lib/profile/profile.sh`: Bash entrypoints that invoke the Python runner.
- Create `lib/profile/wiring.sh`: idempotent profile-hook composition.
- Create `.codex-isolated/hooks/profile-transition.py`: protected-action enforcement.
- Modify `lib/command/args.sh`: parse profile commands without changing passthrough
  behavior.
- Modify `icodex.sh`: source profile modules, wire the hook, and dispatch profile modes.
- Create `docs/profiles/README.md`: schema and approval lifecycle.
- Create `docs/profiles/registry.yaml`: user-approved exact profile capacities.
- Create `docs/profiles/profile-recheck-at-task-transition.yaml`: approved topic policy
  used as the first real manifest.
- Modify `.codex-isolated/AGENTS.md`: orchestrated path and manual interactive fallback.
- Modify `docs/README.ru.md`: user-facing commands, failures, and portable transfer.
- Create `tests/test_profile_policy.sh`: policy, Git state, and selection tests.
- Create `tests/test_profile_state.sh`: handoff, replay, cache, and permission tests.
- Create `tests/test_profile_hook.sh`: hook allow/deny and model-change tests.
- Create `tests/test_profile_runner.sh`: fake App Server and sequencing tests.
- Create `tests/test_profile_bundle.sh`: portable export/import tests.
- Create `tests/test_profile_wiring.sh`: hook composition and idempotency tests.
- Modify `tests/test_args.sh`, `tests/test_smoke.sh`, and
  `tests/test_workflow_boundaries.sh`: wrapper and documentation integration checks.

## Requirement Coverage

| Spec requirement | Plan tasks |
|---|---|
| R1 Versioned Capacity Registry | 1, 2 |
| R2 Committed Topic Profile Manifest | 1, 2 |
| R3 Deterministic Profile Selection | 1, 5 |
| R4 Explicit App Server Orchestration | 4, 5 |
| R5 One-Time Handoff and Hook Enforcement | 3, 4 |
| R6 Runtime Cache and LoEn Re-evaluation | 3, 5 |
| R7 Portable Cross-Machine History | 6 |
| R8 Policy and User Documentation | 2, 7 |
| R9 Verification Coverage | 1, 3, 4, 5, 6, 7 |

### Task 1: Build Strict Policy Validation and Selection

**Closes:** R1, R2, and R3 by creating the dependency-free policy boundary used by all
later runtime components.

**Files:**

- Create: `lib/profile/policy.py`
- Create: `tests/test_profile_policy.sh`

- [ ] **Step 1: Write failing schema and selector tests**

Create `tests/test_profile_policy.sh` using `tests/helpers.sh`. Its fixtures must cover:

```bash
python3 "$ROOT/lib/profile/policy.py" validate-registry "$repo/docs/profiles/registry.yaml"
python3 "$ROOT/lib/profile/policy.py" validate-topic "$repo/docs/profiles/demo.yaml" "$repo/docs/profiles/registry.yaml"
python3 "$ROOT/lib/profile/policy.py" select "$repo/docs/profiles/demo.yaml" build "$available_json"
```

Assert these exact observable cases:

```text
valid registry -> exit 0
duplicate mapping key -> exit 2 and "duplicate key: profiles.engineering"
unsupported YAML feature -> exit 2 and "unsupported YAML"
dirty topic manifest -> exit 3 and "topic manifest differs from HEAD"
registry hash mismatch -> exit 3 and "registry hash mismatch"
first profile unavailable -> second sufficient profile selected
available but insufficient profile -> skipped with failing dimension
no sufficient profile -> exit 4 and "no available sufficient profile"
```

- [ ] **Step 2: Run the policy test and confirm red state**

Run:

```bash
bash tests/test_profile_policy.sh
```

Expected: non-zero; `lib/profile/policy.py` is missing.

- [ ] **Step 3: Implement the strict YAML subset and schemas**

Create `lib/profile/policy.py` with these public interfaces:

```python
class PolicyError(Exception):
    def __init__(self, message: str, exit_code: int = 2):
        super().__init__(message)
        self.exit_code = exit_code


def parse_yaml_subset(text: str) -> dict[str, object]:
    """Parse mappings, lists, quoted/plain scalars, bools, nulls, and integers.

    Reject aliases, anchors, tags, flow collections, duplicate keys, tabs, and
    implicit type extensions. Return only JSON-compatible values.
    """


def load_registry(path: Path) -> dict[str, object]:
    """Validate schema_version, registry_version, dimensions, and exact profiles."""


def load_topic(path: Path, registry_path: Path, repo: Path) -> dict[str, object]:
    """Validate schema, committed HEAD equality, approval, registry pin, and tasks."""


def select_profile(
    registry: dict[str, object],
    topic: dict[str, object],
    task_id: str,
    available_models: list[dict[str, object]],
) -> dict[str, object]:
    """Return the first ordered profile that is available and sufficient."""
```

Implement comparators exactly as specified: `gte` uses candidate index greater than or
equal to requirement index; `lte` uses candidate index less than or equal to requirement
index. Treat missing dimensions, unknown tiers, unsupported efforts, and required live
remaining-context confirmation as blocking errors.

- [ ] **Step 4: Add CLI adapters and deterministic JSON output**

Add `validate-registry`, `validate-topic`, `validate-topic-schema`, and `select`
subcommands in the same file. `validate-topic-schema` performs all content and registry
checks except committed-HEAD equality; runtime code must call `validate-topic`.
Successful selection output must use sorted compact JSON:

```json
{"effort":"medium","model":"gpt-5.6-terra","profile":"engineering","task":"build"}
```

Errors go to stderr and use the `PolicyError.exit_code`; unexpected exceptions use exit
1 without a traceback unless `ICODEX_PROFILE_DEBUG=1`.

- [ ] **Step 5: Run focused policy tests**

Run:

```bash
bash tests/test_profile_policy.sh
```

Expected: `FAIL=0` and exit 0.

- [ ] **Step 6: Commit the policy boundary**

```bash
git add lib/profile/policy.py tests/test_profile_policy.sh
git commit -m "feat(profile): validate routing policy"
```

### Task 2: Add Approved Registry and Topic Policy

**Closes:** R1, R2, and the policy-documentation part of R8 by creating the first
durable cross-machine routing decision.

**Files:**

- Create: `docs/profiles/README.md`
- Create: `docs/profiles/registry.yaml`
- Create: `docs/profiles/profile-recheck-at-task-transition.yaml`
- Modify: `tests/test_profile_policy.sh`

- [ ] **Step 1: Write failing repository-policy tests**

Extend `tests/test_profile_policy.sh` to require both repository paths, strict schema
version `1`, exact registry hash pinning, and canonical topic
`profile-recheck-at-task-transition`. At this pre-commit stage, validate the production
topic with `validate-topic-schema`; committed-HEAD behavior remains covered by the
temporary-repository tests from Task 1.

Run:

```bash
bash tests/test_profile_policy.sh
```

Expected: FAIL because the production policy files do not exist.

- [ ] **Step 2: HUMAN CHECKPOINT — approve exact capacity classifications**

Generate a complete registry proposal from the exact model/effort pairs in the current
`.codex-isolated/AGENTS.md` catalog. For each pair, propose values for capability,
catalogued context capacity, latency, cost, and throughput; cite the local policy or
current `model/list` evidence used. Present the complete YAML and its SHA-256 to the
user. Stop until the user explicitly approves those exact bytes. Do not treat plan
approval as registry approval and do not invent live measurements.

- [ ] **Step 3: Write the approved registry and schema documentation**

Write the exact approved bytes to `docs/profiles/registry.yaml`. Document in
`docs/profiles/README.md`:

```text
tracked policy != runtime state
status: approved requires explicit review before commit
registry hash changes invalidate topic manifests
gte dimensions: capability, context, throughput
lte dimensions: latency, cost
live remaining context is not inferred from catalog context capacity
unsupported YAML constructs fail closed
```

- [ ] **Step 4: HUMAN CHECKPOINT — approve the topic task matrix**

Create a complete topic proposal whose task IDs match Tasks 3–7 in this plan. Each task
must contain requirements and an ordered `preferred_profiles` list referencing only the
approved registry. Present the full YAML and registry hash to the user. Stop until the
user explicitly approves those exact bytes.

- [ ] **Step 5: Write and validate the approved topic manifest**

Write the approved bytes to
`docs/profiles/profile-recheck-at-task-transition.yaml`, set `status: approved`, and run
pre-commit schema validation:

```bash
python3 lib/profile/policy.py validate-registry docs/profiles/registry.yaml
python3 lib/profile/policy.py validate-topic-schema docs/profiles/profile-recheck-at-task-transition.yaml docs/profiles/registry.yaml
bash tests/test_profile_policy.sh
```

Expected: schema commands exit 0. Repository tests may keep the production-manifest
HEAD-equality assertion skipped until the approved files are committed; all other
assertions end with `FAIL=0`.

- [ ] **Step 6: Commit approved policy once**

```bash
git add docs/profiles/README.md docs/profiles/registry.yaml docs/profiles/profile-recheck-at-task-transition.yaml tests/test_profile_policy.sh
git commit -m "docs(profile): add approved routing manifests"
```

- [ ] **Step 7: Verify committed policy authority**

```bash
python3 lib/profile/policy.py validate-topic docs/profiles/profile-recheck-at-task-transition.yaml docs/profiles/registry.yaml
bash tests/test_profile_policy.sh
```

Expected: both commands exit 0 and the test ends with `FAIL=0`.

- [ ] **Step 8: Enforce committed policy in the repository test**

Replace the production manifest's `validate-topic-schema` assertion with full
`validate-topic`, then run:

```bash
bash tests/test_profile_policy.sh
```

Expected: `FAIL=0`. Commit the stronger invariant:

```bash
git add tests/test_profile_policy.sh
git commit -m "test(profile): require committed routing policy"
```

### Task 3: Implement Atomic Handoffs and Session Decisions

**Closes:** R5 and R6 by making runtime authorization single-use, session-bound, and
recoverable without treating state as policy.

**Files:**

- Create: `lib/profile/state.py`
- Create: `tests/test_profile_state.sh`

- [ ] **Step 1: Write failing state tests**

Test these public operations with a temporary `CODEX_HOME`:

```python
create_handoff(state_root, request)
consume_handoff(state_root, run_id, sequence, session_id, payload_model)
load_decision(state_root, session_id)
cache_matches(decision, expected_tuple)
invalidate_run(state_root, run_id)
```

Assertions must prove mode `0600`, atomic replace, one consumer, replay rejection,
cross-run rejection, cross-task rejection, model mismatch, changed tuple invalidation,
and recovery after deleting state.

- [ ] **Step 2: Run the state test and confirm red state**

```bash
bash tests/test_profile_state.sh
```

Expected: non-zero; `lib/profile/state.py` is missing.

- [ ] **Step 3: Implement restrictive atomic state files**

Create `lib/profile/state.py` with:

```python
@dataclass(frozen=True)
class SelectionTuple:
    topic: str
    task_id: str
    requirement_hash: str
    registry_hash: str
    manifest_hash: str
    profile: str


def atomic_json_write(path: Path, payload: dict[str, object]) -> None:
    """Write through a same-directory temporary file, fsync, chmod 0600, replace."""


def create_handoff(state_root: Path, request: dict[str, object]) -> Path:
    """Validate required fields and create one pending run/sequence record."""


def consume_handoff(
    state_root: Path,
    run_id: str,
    sequence: int,
    session_id: str,
    payload_model: str,
) -> dict[str, object]:
    """Atomically move pending state to one session decision or raise StateError."""
```

Use `os.open` with restrictive creation mode, `os.replace`, and a per-handoff lock file
created with `O_CREAT | O_EXCL`. Store no prompts, tool output, auth material, or
transcript paths.

- [ ] **Step 4: Implement cache comparison and invalidation**

Require exact equality for topic, task, requirement hash, registry hash, manifest hash,
and selected profile. A later hook event must also match the persisted model. Missing
fields return false; they never inherit earlier values.

- [ ] **Step 5: Run focused state tests**

```bash
bash tests/test_profile_state.sh
```

Expected: `FAIL=0` and exit 0.

- [ ] **Step 6: Commit runtime state support**

```bash
git add lib/profile/state.py tests/test_profile_state.sh
git commit -m "feat(profile): persist transition handoffs"
```

### Task 4: Enforce Profile Decisions in Hook Wiring

**Closes:** R5 and the hook-composition part of R9 by adding a validation-only guard that
coexists with current enforcement.

**Files:**

- Create: `.codex-isolated/hooks/profile-transition.py`
- Create: `lib/profile/wiring.sh`
- Create: `tests/test_profile_hook.sh`
- Create: `tests/test_profile_wiring.sh`
- Modify: `icodex.sh`
- Modify: `tests/test_smoke.sh`

- [ ] **Step 1: Write failing hook behavior tests**

Feed JSON hook payloads on stdin with `ICODEX_PROFILE_RUN_ID`,
`ICODEX_PROFILE_SEQUENCE`, and temporary state. Cover:

```json
{"session_id":"s1","cwd":"/repo","hook_event_name":"PreToolUse","model":"gpt-5.6-terra","tool_name":"Write","tool_input":{"file_path":"x"}}
```

Assert allow for a matching one-time handoff, deny for missing/stale/replayed handoff,
deny for changed model on the next protected event, allow direct `Read`, allow the
closed read-only command `rg --files`, and deny an unknown shell command. A `Read` or
otherwise allowlisted shell command targeting an execution skill's `SKILL.md` must be
protected; an unrelated documentation read remains unprotected. Without
`ICODEX_PROFILE_RUN_ID`, the hook must allow the ordinary interactive path without
claiming routed authorization. Also assert that no code path opens `transcript_path`.

- [ ] **Step 2: Write failing wiring-composition tests**

Create `tests/test_profile_wiring.sh` following `tests/test_idd_wiring.sh`. Compose base
secret hooks, caveman, IDD, then profile wiring. Assert valid JSON, one profile hook,
idempotency, and preservation of `block-secrets.py`, `redact-secrets.py`,
`caveman-hook.py`, and both `chain-gate.py` entries.

- [ ] **Step 3: Run hook tests and confirm red state**

```bash
bash tests/test_profile_hook.sh
bash tests/test_profile_wiring.sh
```

Expected: both fail because the hook and wiring module are missing.

- [ ] **Step 4: Implement the transition hook**

Create `.codex-isolated/hooks/profile-transition.py`. It must:

```python
def is_protected(event: dict[str, object]) -> bool:
    """Protect writes, edits, patches, skills, unknown tools, and non-allowlisted shell."""


def validate_event(event: dict[str, object], environ: Mapping[str, str]) -> dict[str, object]:
    """Consume or reuse a decision and return a Codex hook allow/deny object."""
```

The closed read-only shell allowlist contains only commands whose parsed argv begin with
`rg`, `sed -n`, `git status`, `git diff`, `git show`, `git log`, `git branch
--show-current`, `git rev-parse`, `tree`, or `find` without action flags. Reject shell
operators, redirections, substitutions, and compound commands before allowlist matching.
Unknown syntax is protected.
Resolve `lib/profile/state.py` only through the wrapper-exported `ICODEX_ROOT`; reject a
missing or non-absolute root rather than importing from cwd or `transcript_path`.

- [ ] **Step 5: Implement idempotent hook wiring**

Create `lib/profile/wiring.sh` using the existing JSON merge pattern. Add one
`PreToolUse` command:

```text
python3 "$CODEX_HOME/hooks/profile-transition.py"
```

Use matcher `*` so unknown tool names reach `is_protected`, preserve every unrelated
entry, and avoid writing when JSON is unchanged. Source `profile/wiring` in `icodex.sh` and call
`ensure_profile_wiring` after `ensure_idd_wiring`.

- [ ] **Step 6: Run focused hook and smoke tests**

```bash
bash tests/test_profile_hook.sh
bash tests/test_profile_wiring.sh
bash tests/test_idd_wiring.sh
bash tests/test_smoke.sh
```

Expected: every test ends with `FAIL=0`.

- [ ] **Step 7: Commit hook enforcement**

```bash
git add .codex-isolated/hooks/profile-transition.py lib/profile/wiring.sh icodex.sh tests/test_profile_hook.sh tests/test_profile_wiring.sh tests/test_smoke.sh
git commit -m "feat(profile): enforce routed task transitions"
```

### Task 5: Add App Server Runner and Wrapper Commands

**Closes:** R3, R4, and R6 by starting tasks with the selected profile and advancing
only from validated structured output.

**Files:**

- Create: `lib/profile/app_server.py`
- Create: `lib/profile/runner.py`
- Create: `lib/profile/profile.sh`
- Create: `tests/test_profile_runner.sh`
- Modify: `lib/command/args.sh`
- Modify: `icodex.sh`
- Modify: `tests/test_args.sh`

- [ ] **Step 1: Write failing CLI parsing tests**

Extend `tests/test_args.sh` with exact cases:

```text
--run-task demo build -> command profile-run-task, topic demo, task build
--orchestrate demo -> command profile-orchestrate, topic demo
missing topic/task -> non-zero
ordinary --model gpt-x -> unchanged passthrough
```

- [ ] **Step 2: Write a deterministic fake App Server test**

Create `tests/test_profile_runner.sh`. Its fake executable reads newline-delimited JSON
and responds to `initialize`, `model/list`, `thread/start`, and `turn/start`. Record each
request to a temporary file. Assert that `turn/start.params` contains exact `model`,
`effort`, `cwd`, and this transition schema:

```json
{"additionalProperties":false,"properties":{"evidence":{"items":{"type":"string"},"type":"array"},"summary":{"type":"string"},"transition":{"enum":["complete","needs_input","blocked"],"type":"string"}},"required":["transition","summary","evidence"],"type":"object"}
```

Test one-shot starts one task. Test orchestration advances once on `complete` and stops
on `needs_input`, `blocked`, malformed output, interruption, or server error.

- [ ] **Step 3: Run CLI and runner tests and confirm red state**

```bash
bash tests/test_args.sh
bash tests/test_profile_runner.sh
```

Expected: new CLI assertions fail and the runner module is missing.

- [ ] **Step 4: Implement the JSON-RPC client**

Create `lib/profile/app_server.py` with:

```python
class AppServerClient:
    def __enter__(self) -> "AppServerClient": ...
    def __exit__(self, exc_type, exc, traceback) -> None: ...
    def request(
        self,
        method: str,
        params: dict[str, object],
        before_send: Callable[[int, dict[str, object]], None] | None = None,
    ) -> dict[str, object]: ...
    def wait_for_turn(self, turn_id: str) -> dict[str, object]: ...
```

Use `subprocess.Popen` with stdin/stdout pipes, monotonically increasing request IDs,
strict response correlation, stderr capture, and bounded shutdown. Ignore unrelated
notifications only after validating their object shape. Call `before_send` with the
allocated ID and exact request object immediately before writing and flushing it. If the
callback fails, write no request. No network transport is added.

- [ ] **Step 5: Implement one-shot and orchestration sequencing**

Create `lib/profile/runner.py`. Before `turn/start`, validate policy, call `model/list`,
select the profile, compute the complete cache tuple, and create the correlated handoff.
Create that handoff from the `before_send` callback so its request ID and exact
`turn/start` fields are durable before the request reaches App Server. Always pass
explicit `model`, `effort`, `cwd`, and `outputSchema`.

For LoEn, compare the persisted selection tuple before calling `model/list`. Reuse only
an exact match; otherwise re-evaluate. A `complete` result advances to the next declared
task. Every other terminal result stops without marking later tasks complete.

- [ ] **Step 6: Wire wrapper commands**

Create `lib/profile/profile.sh` functions `run_profile_task` and
`run_profile_orchestrator`. Update `lib/command/args.sh` and `icodex.sh` to dispatch them
after normal home, permission, hook, binary, and proxy setup. Launch App Server through
the installed isolated binary as `"$ICODEX_BIN" app-server`. When PII masking is
enabled, reuse `start_pii_proxy_server`, pass the same explicit
`openai_base_url="http://127.0.0.1:${PII_PROXY_ACTIVE_PORT}/v1"` override to the App
Server command, and stop the proxy on runner exit.

- [ ] **Step 7: Run focused runner tests**

```bash
bash tests/test_args.sh
bash tests/test_profile_runner.sh
bash tests/test_smoke.sh
```

Expected: every test ends with `FAIL=0`.

- [ ] **Step 8: Commit task orchestration**

```bash
git add lib/profile/app_server.py lib/profile/runner.py lib/profile/profile.sh lib/command/args.sh icodex.sh tests/test_args.sh tests/test_profile_runner.sh tests/test_smoke.sh
git commit -m "feat(profile): orchestrate App Server tasks"
```

### Task 6: Add Portable History Export and Import

**Closes:** R7 by moving supported model-visible history and routing progress without
copying internal Codex state.

**Files:**

- Modify: `lib/profile/app_server.py`
- Modify: `lib/profile/runner.py`
- Modify: `lib/profile/profile.sh`
- Modify: `lib/command/args.sh`
- Create: `tests/test_profile_bundle.sh`
- Modify: `tests/test_args.sh`

- [ ] **Step 1: Write failing bundle tests**

Add exact command parsing for:

```text
icodex --profile-export demo s1 /tmp/profile-bundle.json
icodex --profile-import demo /tmp/profile-bundle.json
```

The fake App Server must prove export calls `thread/read`, retains only raw Responses
items accepted by `thread/inject_items`, stores completed task IDs and last sequence,
and creates mode `0600`. Import must create a new local thread, call
`thread/inject_items`, and reject topic, schema, sequence, manifest hash, registry hash,
or unsupported-item mismatch before injection.

- [ ] **Step 2: Run bundle tests and confirm red state**

```bash
bash tests/test_profile_bundle.sh
```

Expected: non-zero because export/import commands are absent.

- [ ] **Step 3: Implement documented App Server adapters**

Add:

```python
def read_thread(self, thread_id: str) -> dict[str, object]:
    return self.request("thread/read", {"threadId": thread_id, "includeTurns": True})


def inject_items(self, thread_id: str, items: list[dict[str, object]]) -> dict[str, object]:
    return self.request("thread/inject_items", {"threadId": thread_id, "items": items})
```

Validate every exported item against the documented injection shapes. Fail the whole
operation on an unsupported item; never silently omit one.

- [ ] **Step 4: Implement restrictive bundle serialization**

Extend `lib/profile/state.py` with `write_bundle` and `load_bundle`. Serialize sorted
JSON with schema version, topic, source thread ID, completed task IDs, sequence, registry
hash, manifest hash, and compatible items. Use the same restrictive atomic writer as
handoffs. Explicitly exclude environment variables, auth paths, internal database paths,
and transcript paths.

- [ ] **Step 5: Wire export/import commands**

Export requires explicit topic, session ID, and destination. Import requires explicit
topic and bundle path, validates current committed policy, creates a new thread, injects
items, and stores the resulting local thread ID for the next matching runner invocation.
Neither command uploads, syncs, or deletes the source bundle.

- [ ] **Step 6: Run focused bundle and runner tests**

```bash
bash tests/test_profile_bundle.sh
bash tests/test_profile_runner.sh
bash tests/test_args.sh
```

Expected: every test ends with `FAIL=0`.

- [ ] **Step 7: Commit portable history support**

```bash
git add lib/profile/app_server.py lib/profile/runner.py lib/profile/state.py lib/profile/profile.sh lib/command/args.sh tests/test_profile_bundle.sh tests/test_profile_runner.sh tests/test_args.sh
git commit -m "feat(profile): transfer routed task history"
```

### Task 7: Align Policy Documentation and Complete Verification

**Closes:** R8 and R9 by documenting the verified paths, preserving hook composition,
and reconciling all design requirements.

**Files:**

- Modify: `.codex-isolated/AGENTS.md`
- Modify: `docs/README.ru.md`
- Modify: `lib/command/args.sh`
- Modify: `tests/test_workflow_boundaries.sh`
- Modify: `tests/test_smoke.sh`
- Update through iwiki MCP: `reference/model-and-reasoning-routing`
- Update through iwiki MCP: `plugin-and-hook-wiring`

- [ ] **Step 1: Write failing documentation-contract tests**

Extend `tests/test_workflow_boundaries.sh` to require these distinctions:

```text
orchestrated profile path uses committed docs/profiles policy and handoff
valid orchestrated evidence replaces manual /status confirmation
ordinary interactive path retains manual /model and /status gate
hook validates but never selects or changes a model
registry changes and matrix expansion require user approval
portable bundle transport remains user-owned
```

Extend help assertions for all four profile commands.

- [ ] **Step 2: Run documentation tests and confirm red state**

```bash
bash tests/test_workflow_boundaries.sh
bash tests/test_smoke.sh
```

Expected: new assertions fail before documentation edits.

- [ ] **Step 3: Update durable workflow guidance**

Edit `.codex-isolated/AGENTS.md` so the Task Transition Gate has two explicit branches:

```text
Orchestrated: validate committed approved manifest + correlated handoff; do not request
manual /status when that evidence is current.

Interactive: retain current classification, /model request, /status confirmation,
downgrade, escalation, and critical-migration rules.
```

Update `docs/README.ru.md` and CLI help with command examples, approval lifecycle,
fail-closed messages, state location, export permissions, and external transport
responsibility. Do not describe the planned behavior as verified until focused tests
pass.

- [ ] **Step 4: Run focused integration checks**

```bash
bash tests/test_profile_policy.sh
bash tests/test_profile_state.sh
bash tests/test_profile_hook.sh
bash tests/test_profile_wiring.sh
bash tests/test_profile_runner.sh
bash tests/test_profile_bundle.sh
bash tests/test_args.sh
bash tests/test_smoke.sh
bash tests/test_workflow_boundaries.sh
bash tests/test_idd_wiring.sh
```

Expected: every test exits 0 and reports `FAIL=0`.

- [ ] **Step 5: Update iwiki after behavior is stable**

Use `wiki_update_page` for `reference/model-and-reasoning-routing` and
`plugin-and-hook-wiring`. Document verified command semantics, tracked/runtime boundary,
hook composition, interactive fallback, and portable transfer. Then run `wiki_lint`.

Expected: no broken links, orphans, missing sources, stale pages, legacy links, missing
frontmatter, or tag drift caused by this change.

- [ ] **Step 6: Run the full repository suite**

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: exit 0; every test file completes without a failure.

- [ ] **Step 7: Review result scope and commit closeout docs**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Verify every changed path maps to R1–R9 and no runtime state, bundle, auth file, binary,
or secret is tracked. Then commit:

```bash
git add .codex-isolated/AGENTS.md docs/README.ru.md lib/command/args.sh tests/test_workflow_boundaries.sh tests/test_smoke.sh
git commit -m "docs(profile): document orchestrated routing"
```

- [ ] **Step 8: Run chain result reconciliation**

Run `$check-chain result docs/superpowers/plans/2026-07-29-profile-recheck-at-task-transition.md`.
Expected: `OK`, no missing commitments, no excess implementation paths, matching plan
hash, and the topic row closed as `done` with `Result: OK`.

- [ ] **Step 9: Commit machine-readable result closeout**

```bash
git add docs/superpowers/plans/2026-07-29-profile-recheck-at-task-transition.md docs/TODO.md
git commit -m "docs(result): close profile transition orchestration"
```

Expected: the commit contains the matching `result_check` state and closed topic row.
