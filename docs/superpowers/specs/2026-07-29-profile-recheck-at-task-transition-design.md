---
review:
  spec_hash: 0611bd346a430c74
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

# Design: Profile Recheck at Task Transition

**Date:** 2026-07-29
**Status:** approved

## 1. Scope and Design Principles

This design adds an explicit, manifest-driven execution path that selects an approved
Codex model and reasoning-effort profile at task boundaries. It preserves ordinary
interactive Codex launches and their manual model-transition policy.

The system has two independent authorities:

- tracked policy under `docs/profiles/` defines approved profiles, task requirements,
  and deterministic preference order;
- runtime state under `$CODEX_HOME/state/profile-routing/` records an orchestrator
  request and the hook decision for one local session.

Runtime state is never policy. Losing it requires a new handoff but does not weaken or
change the committed routing decision. The hook is a guardrail: it validates the
orchestrator's selection and active model but never selects a model, changes Codex
configuration, calls `/model`, parses a transcript, or starts another turn.

In this design, protected profile-routed work means mutation or execution performed by
a runner process carrying a valid profile run ID. An ordinary interactive session is
not represented as profile-routed work and remains governed by the manual transition
policy.

## 2. Requirements

### R1: Versioned Capacity Registry

`docs/profiles/registry.yaml` must define one entry for each exact `model` and `effort`
pair that may be referenced by a topic. Each entry has a stable profile ID and
qualitative tiers for capability, context capacity, latency, cost, and throughput.

The registry defines the ordered vocabulary and comparator for every dimension.
Capability, context, and throughput use `gte`; latency and cost use `lte`. It contains
curated qualitative classifications and provenance notes, not live measurements.
The context tier describes catalogued model context-window capacity, not live remaining
context in a session. A task that requires confirmed remaining context must block unless
a separately documented supported source provides that confirmation.

Acceptance criteria:

- Each profile resolves to exactly one model slug and one supported effort value.
- Every capacity value belongs to the ordered vocabulary for its dimension.
- Registry validation rejects duplicate profile IDs, unknown dimensions, unknown
  tiers, and missing comparators.
- No registry reader makes a network request or derives effort modifiers.

### R2: Committed Topic Profile Manifest

Each routed topic must have `docs/profiles/<topic>.yaml`. The manifest contains the
canonical topic, schema version, `status: approved`, registry path and full SHA-256,
ordered tasks, tracked context inputs, and portable-history policy.

Each task contains a stable task ID, requirement tiers for all enforced dimensions,
and an ordered `preferred_profiles` list. It references registry profile IDs and never
duplicates model or capacity data.

User approval and commit are separate workflow steps. The user approves the exact
manifest contents before commit. Runtime accepts a manifest only when it is tracked,
its worktree bytes equal the `HEAD` blob, its status is approved, and its pinned
registry hash matches the committed registry. Git provides the durable review trail;
the manifest does not claim cryptographic proof of user identity.

Acceptance criteria:

- A dirty, untracked, unapproved, malformed, or registry-mismatched manifest blocks
  routed execution with one concrete recovery action.
- Changing either committed file invalidates every handoff made from the prior hashes.
- A new or changed manifest cannot become runnable before explicit user approval and a
  commit.
- The same committed registry and topic manifest produce the same ordered candidate
  set on different machines.

### R3: Deterministic Profile Selection

The selector must obtain current model availability and supported efforts from App
Server `model/list`. It scans `preferred_profiles` in order and selects the first entry
that is both available and sufficient for every task requirement.

Sufficiency is evaluated per dimension using the registry comparator. The selector
must not combine dimensions into a score, infer missing values, use an App Server
default, or choose a profile outside the task list.

Acceptance criteria:

- An unavailable preferred profile falls through to the next approved candidate.
- An insufficient profile is skipped even when its model is available.
- Missing requirements, unknown registry data, unavailable model metadata, or no
  sufficient candidate blocks the task with the failing dimension or missing source.
- Equal inputs produce the same selected profile and explanation.

### R4: Explicit App Server Orchestration

The wrapper must expose two explicit modes:

- `icodex --run-task <topic> <task-id>` starts one declared task and exits after its
  terminal result;
- `icodex --orchestrate <topic>` runs the declared sequence and may start the next task
  only after the current task reports completion.

Both modes use documented App Server methods. The runner starts or resumes a thread,
passes exact `model` and `effort` overrides to `turn/start`, and supplies an
`outputSchema` whose transition is `complete`, `needs_input`, or `blocked`.
`turn/completed` alone never advances the sequence. `needs_input`, `blocked`, malformed
structured output, interruption, or App Server failure stops the runner.

Acceptance criteria:

- One-shot mode never starts a second task.
- Orchestration mode advances exactly once after a valid `complete` result.
- Every started task records its selected profile, requirement evidence, App Server
  request ID, and manifest hashes.
- Ordinary interactive `icodex` launches continue to use the existing CLI path.

### R5: One-Time Handoff and Hook Enforcement

Before `turn/start`, the runner must atomically create a one-time handoff containing a
process-scoped run ID, sequence, topic, task ID, registry hash, manifest hash, selected
profile, exact model, exact effort, and App Server request correlation data. The App
Server child process receives the run ID through its environment; hook subprocesses
inherit that value.

At the first protected action, `.codex-isolated/hooks/profile-transition.py` binds the
handoff to the documented hook payload `session_id`, compares the payload `model` with
the selected model, and persists the decision under
`$CODEX_HOME/state/profile-routing/<session_id>/`. The effort confirmation is the exact
value written to the correlated `turn/start` request; the hook must not claim an
independent observation of active effort.

On every later protected hook event, the hook compares the current payload `model` with
the persisted selected model before reusing the decision. A model-slug change therefore
invalidates the cached authorization before protected work continues.

Protected actions include file mutation, execution skills, arbitrary shell commands,
and unknown tools. Direct reads, searches, and a closed allowlist of read-only commands
may run before selection. Unknown commands fail closed as protected.

Acceptance criteria:

- Missing, stale, replayed, cross-run, cross-task, or hash-mismatched handoffs block a
  protected action.
- A payload model mismatch blocks even when every manifest check passes.
- A mid-session payload model change is detected on the next protected hook event.
- A consumed handoff cannot authorize a second session or sequence.
- The hook reads no `transcript_path`, makes no network request, changes no model
  setting, and starts no continuation loop.
- Existing hook entries remain enabled and wiring remains idempotent.

### R6: Runtime Cache and LoEn Re-evaluation

Runtime decisions are keyed by session ID and the tuple of topic, task requirement,
registry hash, manifest hash, and selected profile. Repeated LoEn iterations may reuse
the decision only while the entire tuple is unchanged. The runner may still issue
another documented turn request, but it must not recompute profile sufficiency for an
unchanged tuple.

Any task boundary, requirement change, selected-profile change, registry change,
manifest change, or newly discovered risk that exceeds the approved matrix invalidates
the cache. A requirement outside the approved matrix blocks for user clarification and
a newly approved manifest; it is never silently downgraded or escalated.

Acceptance criteria:

- An unchanged LoEn tuple reuses the recorded selection.
- Changing any tuple member forces validation and selection before protected work.
- Deleted local state is recoverable from committed policy through a fresh handoff.
- Cache recovery never infers approval or completion from missing data.

### R7: Portable Cross-Machine History

The runner must support an explicit portable export/import path based only on documented
App Server data. Export reads model-visible history through `thread/read`, retains only
items accepted by `thread/inject_items`, and adds completed task IDs, the last sequence,
topic identity, and pinned registry/manifest hashes.

The bundle is written only on an explicit export command, to a user-selected path, with
file mode `0600`. It must not contain Codex authentication files, the internal state
database, or raw transcript files. Transport and storage between machines are supplied
by the user; icodex performs no upload or remote synchronization.

Import creates or resumes a supported thread, injects compatible items through
`thread/inject_items`, and restores progress only after topic and policy hashes match.
Unsupported item types or incomplete history fail export or import explicitly rather
than producing a partial silent reconstruction.

Acceptance criteria:

- A valid bundle round-trips model-visible history and task progress without copying
  `$CODEX_HOME` internals.
- Topic, schema, sequence, registry, or manifest mismatch blocks import.
- Export and import never parse `transcript_path`.
- The bundle is never added to Git by the feature.

### R8: Policy and User Documentation

`.codex-isolated/AGENTS.md` must describe the profile workflow as a first-class task
transition path. For an orchestrated task, a valid approved manifest and correlated
handoff replace the manual `/status` confirmation. For ordinary interactive Codex, the
current manual `/status` and `/model` gate remains in effect.

CLI help, `docs/README.ru.md`, schema documentation under `docs/profiles/`, and the
bound iwiki model-routing and hook pages must describe the two commands, approval
lifecycle, failure recovery, portable transfer boundary, and the distinction between
tracked policy and runtime state.

Acceptance criteria:

- The documented workflow never implies that a hook chooses or changes a model.
- Interactive and orchestrated paths have distinct, non-contradictory rules.
- Examples use committed approved manifests and omit secrets, live metrics, and
  internal Codex state.
- `wiki_lint` reports no broken, orphan, missing-source, or stale page caused by this
  change.

### R9: Verification Coverage

Focused dependency-free tests must cover schema validation, Git approval state,
multi-dimensional sufficiency, ordered availability fallback, one-time handoffs, hook
blocking, structured transitions, LoEn cache reuse and invalidation, portable bundle
round-trips, and hook composition.

Acceptance criteria:

- Mocked App Server JSON-RPC tests prove exact `model`, `effort`, and `outputSchema`
  fields without network access.
- Negative tests cover every fail-closed condition named in R2, R3, R5, and R7.
- Existing secret guard, caveman, IDD, LoEn, and iwiki hook wiring tests remain green.
- The full Bash test suite exits successfully.

## 3. Components and Boundaries

### 3.1 Profile Policy Files

`docs/profiles/registry.yaml` owns tier definitions and exact profile capacities.
`docs/profiles/<topic>.yaml` owns topic tasks, requirements, approved candidates, order,
and the registry pin. Neither file stores runtime decisions or session history.

### 3.2 Profile Library

`lib/profile/` owns strict YAML loading, schema validation, canonical hashing, Git blob
checks, sufficiency comparison, selection, state serialization, and portable bundle
validation. It accepts a documented, project-owned YAML subset and introduces no
package-manager or runtime dependency. Shell entrypoints consume stable command results
instead of duplicating policy logic.

### 3.3 App Server Runner

The runner owns App Server process lifecycle, JSON-RPC request correlation,
`model/list`, thread start/resume/read/injection, `turn/start`, structured completion,
task sequencing, and portable export/import. It may select only through the profile
library.

### 3.4 Transition Hook

The hook owns enforcement at protected tool boundaries. It validates and consumes an
existing selection; it does not own registry policy, selection, App Server lifecycle,
or task progression.

### 3.5 Runtime State

`$CODEX_HOME/state/profile-routing/` contains atomic handoffs and session decisions.
State files use restrictive permissions and are scoped by run and session identifiers.
They are disposable caches, not portable policy or approval records.

## 4. Data Flow

1. The user approves and commits the registry and topic manifest.
2. The runner validates both committed blobs and the registry pin.
3. The runner calls `model/list` and deterministically selects the first available and
   sufficient approved profile.
4. The runner atomically writes a one-time handoff and starts the App Server process with
   the run ID in its environment.
5. The runner starts the declared task with exact model/effort overrides and the task
   transition output schema.
6. The first protected action invokes the transition hook. The hook binds the handoff to
   the payload session ID, verifies the active model, and records the decision.
7. Later protected actions reuse the decision while its complete cache tuple matches.
8. The runner accepts only valid structured terminal output. One-shot mode exits;
   orchestration mode advances only on `complete`.
9. Explicit export packages compatible model-visible history and routing progress.
   Explicit import validates policy pins before reconstructing a thread with documented
   App Server methods.

## 5. Error Handling and Recovery

| Failure | Required behavior | Recovery |
|---|---|---|
| Manifest is dirty, untracked, or unapproved | Block before selection | Approve exact contents and commit them. |
| Registry hash differs | Block before selection | Review the registry change and approve a repinned manifest. |
| No available sufficient profile | Block with candidate and dimension evidence | Change availability or approve a revised matrix. |
| Handoff is missing, stale, or replayed | Block protected action | Restart the task to create a fresh handoff. |
| Payload model differs | Block protected action | Stop the mismatched session and restart through the runner. |
| App Server or structured result fails | Do not advance task sequence | Fix the reported failure and rerun the same task. |
| Local state is lost | Do not infer completion | Recreate a handoff from committed policy. |
| Portable bundle hashes differ | Reject import without injection | Checkout matching policy or create a new approved routing decision. |
| New risk exceeds approved matrix | Block automatic selection | Obtain user clarification and approve a revised manifest. |

Ordinary interactive launches do not carry a runner run ID, so the profile hook does
not claim orchestrated authorization for them. Their task-transition decisions remain
governed by the manual policy in `.codex-isolated/AGENTS.md`.

## 6. Compatibility and Migration

The feature is opt-in through the two explicit runner commands. Existing `icodex`
passthrough behavior, configuration, hooks, and interactive sessions remain available.
No existing topic is routed automatically merely because a registry exists.

The launcher adds the new hook idempotently without replacing secret guards, caveman,
IDD, LoEn, or iwiki entries. Existing model-routing guidance is revised only where the
orchestrated path supersedes manual confirmation; its interactive fallback remains.

Registry and topic schema versions are strict. Unsupported versions block with an
upgrade instruction; the runtime performs no silent migration of approved policy.

## 7. Testing Strategy

Focused tests use temporary repositories and a deterministic fake App Server. They
verify:

- valid and invalid registry/topic schemas;
- rejection of unsupported YAML constructs without an external YAML dependency;
- committed-versus-dirty approval state and exact hash pinning;
- both comparator directions and ordered availability fallback;
- selection failure diagnostics;
- atomic handoff creation, consumption, replay rejection, and session binding;
- model mismatch and unknown protected-command behavior;
- exact JSON-RPC model, effort, output schema, and transition sequencing;
- one-shot versus orchestration mode;
- LoEn cache reuse for an unchanged tuple and re-evaluation for each changed member;
- portable history round-trip, restrictive permissions, and mismatch rejection;
- idempotent hook composition with all existing hook families.

The final verification runs the focused profile tests, existing workflow and hook tests,
and every `tests/test_*.sh` file. Tests use no network and no real Codex account.

## 8. Documentation and Human Checkpoints

The implementation updates `.codex-isolated/AGENTS.md`, CLI help, `docs/README.ru.md`, and
the schema/examples in `docs/profiles/`. It then updates the bound iwiki pages for model
routing and hook wiring and runs `wiki_lint`.

Human checkpoints remain:

- approve exact registry changes before they can affect any topic;
- approve exact topic manifests before commit;
- approve any matrix expansion caused by a new risk or missing sufficient profile;
- choose and operate the external transport for portable history bundles.

No further design choice is required before implementation planning.

## 9. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Qualitative capacity data becomes stale | Version registry changes, pin its hash, and require topic reapproval. |
| Hook cannot observe active effort | Correlate the exact `turn/start.effort` request and state that this is request evidence, not independent observation. |
| Concurrent runners consume the wrong handoff | Scope handoffs by inherited run ID, task sequence, and single-use atomic consumption. |
| Shell classification permits mutation | Use a closed read-only allowlist; treat unknown commands as protected. |
| Automatic runner advances after an incomplete turn | Require valid structured `complete`; never equate `turn/completed` with task completion. |
| Portable history exposes sensitive context | Make export explicit, use mode `0600`, avoid internal/auth files, and leave transport to the user. |
| App Server schema changes | Use documented methods and fields, strict response validation, and mocked compatibility tests. |
| New hook weakens existing enforcement | Merge idempotently and test composition with every existing hook family. |

## 10. Definition of Done

The design is implemented when an approved task can select and start the first available
sufficient profile through either explicit runner mode; the hook blocks mismatched or
unknown protected execution; an unchanged LoEn tuple avoids repeated selection; a
portable bundle reconstructs supported model-visible history on another machine; and
focused plus full tests pass without weakening existing interactive launches or hook
composition. Repository docs and the bound iwiki domain describe the verified behavior
and pass lint.
