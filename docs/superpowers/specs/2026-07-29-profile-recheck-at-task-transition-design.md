---
review:
  spec_hash: 758333e9e0791cd0
  last_run: 2026-07-29
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-29-profile-recheck-at-task-transition-intent.md
---

# Profile Recheck at Task Transition Design

**Date:** 2026-07-29
**Status:** approved

## 1. Scope and Principles

This design adds an explicit profile-routed execution path at task boundaries. It keeps
ordinary interactive Codex launches and their manual `/model` and `/status` policy.

Policy and state have distinct authorities:

- `.codex-isolated/profiles/registry.yaml` is the single shared capacity registry for
  every project launched by this icodex installation.
- `<target-repository>/docs/profiles/<topic>.yaml` is the authoritative project manifest.
- `$CODEX_HOME/state/profile-routing/` contains only machine-local handoffs, session
  decisions, and current-run progress.

The launcher exposes the shared registry through `$CODEX_HOME/profiles`, but the home
path is a convenience, not a second policy authority. The runner reads the project
manifest directly from the target repository. It never copies or symlinks a manifest
into the project home.

Trust has priority over speed and cost. Unknown policy blocks protected execution.
Session history and routing progress are not portable and never enter Git.

## 2. Acceptance (from intent)

### Desired Outcomes

- Every launched project home uses one shared, user-approved registry of model and
  reasoning-effort capacity tiers.
- Each project has a distinct authoritative manifest under its target repository's
  `docs/profiles/` directory; no home copy or manifest symlink is required.
- The manifest's approved source and hash survive cross-machine work through a reviewed,
  secret-free Git artifact.
- A hook detects an active model-slug change per Codex session before protected work.
- A shared, versioned capacity registry evaluates capability, context-window, latency,
  cost, and throughput tiers without claiming live measurements.
- At each task boundary, an orchestrator starts the next Codex turn with a sufficient
  profile from the approved matrix, without requiring a manual profile change.
- LoEn iterations continue without repeated profile evaluation while the topic,
  requirement, registry version, and selected profile remain unchanged.
- A missing registry entry, task requirement, approved profile, or sufficient capacity
  blocks protected work with an actionable reason.
- A newly discovered risk, increased complexity, or critical failure blocks automatic
  selection when it requires a profile outside the approved matrix.
- The hook never invokes `/model` or creates an automatic continuation loop.

### Done When

- Done when two project homes on different machines can use the same reviewed registry,
  validate and use the same approved project manifest from `docs/profiles/`, and
  select/start a sufficient profile without a manual switch while session history and
  routing state stay machine-local; missing state produces an explicit new cold start,
  unknown policy blocks with a precise remediation, and focused tests pass without
  weakening existing hooks.

## 3. Requirements

### R1: Shared Versioned Capacity Registry

`.codex-isolated/profiles/registry.yaml` defines the ordered vocabulary, comparator, and
qualitative capacities for every approved exact `model` and `effort` pair. Capability,
catalogued context capacity, and throughput use `gte`; latency and cost use `lte`.

The registry is a curated policy, not a measurement service. It performs no network
request, contains no live remaining-context value, and derives no effort modifier.
`.gitignore` must whitelist only the curated `.codex-isolated/profiles/` content while
continuing to exclude secrets and runtime state elsewhere in `.codex-isolated/`.

Acceptance criteria:

- The registry is tracked at the exact canonical shared-store path and its worktree
  bytes equal its pinned icodex HEAD blob.
- Every profile has a unique stable ID and exact model/effort pair.
- Unknown dimensions, tiers, comparators, keys, or duplicate pairs fail validation.
- A registry content change produces a new SHA-256 and invalidates every manifest that
  pins the previous bytes.

### R2: Project-Local Topic Manifest

Each routed topic has `<target-repository>/docs/profiles/<topic>.yaml`. The manifest
contains the canonical topic, schema version, `status: approved`, ordered tasks, tracked
context inputs, and this shared-registry reference:

```yaml
registry:
  authority: icodex-shared
  path: profiles/registry.yaml
  sha256: <64 lowercase hex characters>
```

`authority` is a logical authority ID. `path` is resolved under `$CODEX_HOME` and must
resolve exactly to `$ICODEX_SHARED_DIR/profiles/registry.yaml`. Absolute paths, alternate
authorities, path traversal, and another symlink target fail closed.

The manifest remains in the target Git repository. Runtime reads it directly and never
creates a home manifest. The target repository supplies the immutable manifest and
context-input blobs; the icodex repository independently supplies the immutable registry
blob.

Acceptance criteria:

- The manifest path is exactly `docs/profiles/<canonical-topic>.yaml` in the target root.
- Manifest and context-input worktree bytes equal regular blobs at one immutable target
  HEAD commit during runtime validation.
- A dirty, untracked, unapproved, malformed, or registry-mismatched manifest blocks with
  one concrete recovery action.
- A new or changed manifest cannot run before explicit user approval and a target-repo
  commit.
- No manifest copy or manifest symlink exists under `.codex-homes/`.

### R3: Split Git Authority Validation

The policy API receives explicit target root, shared-store root, manifest path, and
registry path. It resolves one immutable commit OID for each Git repository before
reading any policy bytes. It reads each relevant worktree file once and compares those
bytes with the corresponding committed blob from the already pinned repository commit.

Registry validation cannot use the target repository HEAD. Manifest and context
validation cannot use the icodex HEAD. Selection reuses the validated registry/manifest
pair and performs no policy reread.

The validated snapshot records:

- registry commit OID, registry SHA-256, and registry version;
- target commit OID and manifest SHA-256;
- canonical target root, topic, and task ID.

Acceptance criteria:

- Moving either HEAD during validation cannot combine bytes from different commits.
- A symlink, Git pathspec, alternate repository, dirty byte change, or non-regular blob
  cannot substitute another authority path.
- Equal registry, manifest, availability, and task inputs produce the same candidate
  order on different machines.

### R4: Shared Profile Home Wiring

`setup_codex_home` ensures `$CODEX_HOME/profiles` is an exact symlink to
`$ICODEX_SHARED_DIR/profiles`. The managed-link helper verifies the link target rather
than accepting any symlink. A missing or incorrect managed link is repaired
idempotently during launcher setup.

The shared profile directory contains registry policy and its documentation only. It
contains no per-project manifest, session state, auth data, cache, or downloaded binary.

Acceptance criteria:

- New and existing homes resolve `profiles/registry.yaml` to the same shared file.
- A second launcher run leaves a correct link byte-for-byte unchanged.
- An incorrect profiles link is repaired to the exact shared target.
- `.codex-homes/` remains fully Git-ignored.

### R5: Deterministic Profile Selection

The runner obtains current model availability and supported efforts from App Server
`model/list`. It scans the task's `preferred_profiles` in manifest order and selects the
first entry that is both available and sufficient for every requirement.

Sufficiency is evaluated independently for each dimension. The selector never combines
dimensions into a score, infers missing values, chooses an App Server default, or uses a
profile outside the approved list. A task that requires confirmed live remaining context
blocks because the shared registry describes only catalogued context capacity.

Acceptance criteria:

- An unavailable or insufficient candidate falls through to the next approved candidate.
- Missing effort metadata, requirement data, or a sufficient candidate blocks with
  evidence naming the failed source or dimension.
- Duplicate or ambiguous `model/list` entries fail closed.

### R6: App Server Task Runner

The wrapper exposes:

```text
icodex --run-task <topic> <task-id>
icodex --orchestrate <topic>
```

Both commands run after normal home, permission, hook, binary, and proxy setup. The
runner validates split policy, calls `model/list`, selects a profile, creates a
correlated one-time handoff, and sends explicit `model`, `effort`, `cwd`, and strict
transition `outputSchema` fields through `turn/start`.

Only structured `transition: complete` advances orchestration. `needs_input`, `blocked`,
malformed output, interruption, or App Server failure stops without advancing.

Acceptance criteria:

- One-shot mode starts exactly the requested task and never another task.
- Orchestration advances exactly once per valid `complete` result.
- Ordinary interactive launch remains on the existing path.
- The hook never invokes `/model` and never creates a stop-driven continuation loop.

### R7: Machine-Local State and Hook Enforcement

Before `turn/start`, the runner atomically creates a one-time handoff under
`$CODEX_HOME/state/profile-routing/`. The handoff includes run ID, sequence, topic, task,
both commit OIDs, registry and manifest hashes, selected profile, exact model/effort,
and App Server request correlation.

At the first protected action, the profile hook binds the handoff to the documented hook
`session_id`, compares the payload model, and persists a local decision. Effort evidence
comes from the exact correlated `turn/start` request, not inference from the hook payload.

Protected work includes mutating tools and execution skills. A closed read-only discovery
allowlist may run before authorization; unknown tool or skill events are protected.

Within one local LoEn run, the runner may reuse a validated selection without another
profile evaluation only when this complete cache tuple is unchanged: canonical target
root, topic, task ID, requirement fingerprint, registry commit/version/hash, manifest
commit/hash, selected profile, exact model, and exact effort. Reuse also requires the
same local run namespace and an authorized session decision whose observed model still
matches. The cache is state, not policy.

Any tuple change, task transition, model mismatch, run change, missing state, invalidated
decision, or newly required supported confirmation forces full policy validation,
`model/list`, and a new handoff. A cold start never reconstructs the LoEn cache from Git.

Acceptance criteria:

- State files use restrictive permissions, atomic replace, and single-use consumption.
- Replay, cross-run, cross-task, hash, model, or sequence mismatch blocks.
- Concurrent runners cannot consume each other's handoffs.
- Hooks read no transcript, make no network request, and do not modify policy or model.
- An exact LoEn cache tuple reuses the prior selection without a second `model/list`
  request; changing any tuple field forces reevaluation before protected work.

### R8: Explicit Cold Starts

Missing `$CODEX_HOME/state/profile-routing/` is a valid cold start. Policy is fully
revalidated and a new run ID is created. No completed task, prior selection, history,
or continuation point is inferred from another machine.

`--run-task` starts the explicit task on a cold home. `--orchestrate` reports that it is
starting a new run from the first declared task. Deleting local routing state is a
recoverable reset, not a policy change.

Acceptance criteria:

- A new home can run an explicit task using the same shared registry and committed
  project manifest.
- A cold orchestrator never claims to resume a previous-machine run.
- Missing state does not bypass manifest, registry, model availability, or hook checks.

### R9: Documentation and Scope Boundary

`.codex-isolated/AGENTS.md` distinguishes two branches:

- orchestrated work uses validated split policy plus correlated local handoff evidence;
- ordinary interactive work retains manual `/model` and `/status` confirmation.

Repository docs describe shared registry placement, project manifest placement, home
symlink wiring, cold starts, and recovery actions. Portable history export/import, Git
tracking of `.codex-homes/`, session synchronization, retention, and transport are
explicit non-goals.

Acceptance criteria:

- No profile export/import command or portable bundle schema is added.
- Tests prove `.codex-homes/`, auth paths, raw sessions, SQLite, caches, and temp files
  remain untracked.
- iwiki documents implemented behavior and passes lint before result closure.
- Stale project-local registry or portable-history artifacts cannot be cited as approved
  evidence by the revised runner, plan, or result reconciliation.

## 4. Components and Boundaries

### 4.1 Home Wiring

`lib/config/isolated.sh` owns shared profile symlink creation. It does not validate YAML
or create routing state. `tests/test_isolated.sh` owns observable wiring coverage.

### 4.2 Policy Library

`lib/profile/policy.py` owns strict YAML parsing, schema checks, split Git snapshots,
canonical path checks, hashing, and deterministic selection. It accepts explicit roots
and returns a validated immutable policy object. It does not start App Server, write
runtime state, or update Git policy.

### 4.3 Runtime State

`lib/profile/state.py` owns restrictive atomic files, one-time handoffs, session
decisions, cache tuples, invalidation, and cold-start detection. It treats absence as
empty local state and never reconstructs progress from policy.

### 4.4 Runner and App Server

`lib/profile/app_server.py` owns synchronous JSON-RPC process lifecycle and documented
method adapters. `lib/profile/runner.py` owns policy resolution, selection, handoff
sequencing, one-shot/orchestration behavior, and structured completion.

### 4.5 Hook and Wrapper

`.codex-isolated/hooks/profile-transition.py` enforces local evidence at protected
actions. `lib/profile/wiring.sh` composes it with existing hooks. `lib/profile/profile.sh`,
`lib/command/args.sh`, and `icodex.sh` expose and dispatch explicit runner commands.

## 5. Data Flow

1. Launcher resolves target root and per-project home, then repairs the shared profiles
   symlink.
2. Runner resolves the manifest from target `docs/profiles/` and registry through the
   home symlink.
3. Policy validation pins icodex and target HEAD independently, reads exact bytes once,
   and validates the manifest registry pin.
4. Runner calls `model/list` and selects the first available sufficient approved profile.
5. Runner allocates an App Server request ID, atomically writes the correlated handoff,
   then sends `turn/start`.
6. Hook consumes the handoff at first protected action and stores the session decision.
7. A valid structured `complete` advances; every other terminal result stops.
8. Missing local state on another machine returns to step 3 with a new run.

## 6. Failure Semantics

| Failure | Result | Recovery |
|---|---|---|
| Shared profiles link missing or wrong | Launcher repairs exact managed link | Relaunch |
| Registry or manifest dirty/untracked | Block before selection | Review and commit exact bytes |
| Registry SHA mismatch | Block before selection | Reapprove and repin manifest |
| Authority/path/symlink mismatch | Block | Restore canonical path and managed link |
| No available sufficient candidate | Block task | Update availability or approve policy change |
| State missing | Explicit cold start | Run explicit task or new orchestration |
| State stale/malformed/replayed | Block or explicit invalidate | Delete local routing state and restart |
| Payload model mismatch | Block protected action | Restart through runner |
| Structured result not `complete` | Stop orchestration | Resolve result and rerun explicitly |

No failure path silently selects another authority, imports previous-machine progress,
or weakens existing hooks.

## 7. Verification Strategy

Focused tests must prove:

- shared profile directory tracking and correct/idempotent/wrong-link home wiring;
- split registry and manifest Git repositories with two immutable HEAD snapshots;
- dirty, untracked, symlink, pathspec, alternate-authority, and hash mismatch rejection;
- absence of a home manifest and direct target-repo manifest reads;
- exact dimension comparators and ordered availability fallback;
- atomic permissions, replay rejection, concurrent-run isolation, and deletion recovery;
- cold one-shot task selection and cold orchestration from the first task;
- App Server request correlation and strict structured completion;
- composition with secret, caveman, IDD, LoEn, and iwiki hooks;
- absence of portable-history commands and tracked home/session artifacts.

Required verification includes focused policy, isolated-home, state, hook, runner,
argument, workflow-boundary, smoke, and full Bash test suites plus `wiki_lint`.

## 8. Human Checkpoints

- Exact registry capacity bytes require explicit user approval before commit.
- Every new or changed project manifest, task requirement, candidate order, and registry
  pin requires explicit user approval before target-repo commit.
- Tracking or synchronizing home/session state is no-go and requires a new intent rather
  than an implementation exception.

## 9. Migration from the Stale Design

The previous design and local implementation assumed registry and manifest both lived
under one target repository's `docs/profiles/`. Local, unpushed commits `5d8c622` and
`1e74dcc` created stale migration artifacts: `docs/profiles/registry.yaml`, a manifest
that pins that path and enables portable history, and a production test that treats the
pair as current. They are not valid policy for this revised design even though the stale
manifest body says `status: approved`. No routing command may use them as authority.

The revised implementation plan must begin by reconciling those commits without history
rewrites: replace or remove stale files through normal commits, then establish the new
authorities and tests. It must:

- move the approved registry bytes to `.codex-isolated/profiles/registry.yaml`;
- keep only project manifest policy and project-facing documentation under
  `docs/profiles/`;
- replace single-repository path checks in `lib/profile/policy.py` with split authority;
- add shared profile home wiring;
- remove every portable-history requirement and planned command;
- reconcile or revert stale local commits before result closure.

Implementation cannot proceed past policy migration while any test or runtime path still
accepts `docs/profiles/registry.yaml`, a manifest without registry authority
`icodex-shared`, or a portable-history task. Result reconciliation cannot return `OK`
until the stale registry is absent, the shared registry is tracked, the project manifest
matches R2, and focused tests prove the revised paths.

## 10. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Shared registry change invalidates many projects | Hash pin and explicit manifest reapproval |
| Wrong home symlink redirects policy | Exact target validation and idempotent repair |
| Mixed commits create an unreviewed pair | One immutable commit per authority and one read per blob |
| Cold start duplicates prior-machine work | Explicit new-run message and no resume claim |
| Concurrent runs consume wrong evidence | Run namespace, sequence, request correlation, atomic consumption |
| Runtime state leaks into Git | Keep `.codex-homes/` ignored and test secret/runtime exclusions |
| Hook weakens existing enforcement | Idempotent composition and full existing-hook regression suite |

No further user decision is required before implementation planning once this checked
spec is approved.
