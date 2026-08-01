---
chain:
  intent: docs/superpowers/intents/2026-08-01-profile-full-chain-manifest-intent.md
review:
  spec_hash: f7858f16e4939d00
  last_run: 2026-08-01
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
---

# Profile Full-Chain Manifest Design

## 1. Purpose

Topic manifests currently contain only their bootstrap task. This design adds a single
dependency-free manifest helper that expands a topic manifest for the workflow selected
by the user. The helper makes task routing deterministic without changing runner order,
registry policy, local state, or chain verdict semantics.

## 2. Acceptance (from intent)

- A direct workflow manifest contains all tasks required by the direct workflow.
- A full workflow manifest contains intent, spec, plan, implementation, and result
  tasks, and the orchestrator accepts them without manual additions.
- Existing manifests and `--run-task` remain compatible.
- Direct-session binding, chain-gate behavior, and rejection of unapproved or invalid
  policy remain unchanged.

## 3. Canonical Task Templates

`lib/profile/manifest.py` owns the only templates for generated tasks. It exposes a
small Python API and CLI operations for creating a bootstrap manifest and expanding an
existing manifest by route.

| Route | Ordered task IDs | Preferred profile |
|-------|------------------|-------------------|
| `direct` | `direct-work` | `engineering` |
| `full` | `intent-profile-selection`, `spec-design`, `plan-writing`, `implementation`, `result-reconciliation` | `engineering`, `synthesis`, `synthesis`, `engineering`, `engineering` |

Every generated task uses the existing manifest requirements shape. `implementation`
uses `engineering` by default. A later request to require `deep` is an explicit reviewed
manifest edit; the helper does not infer implementation complexity.

## 4. Manifest Operations

### R1: Bootstrap

The helper creates the current draft bootstrap manifest for a canonical topic when no
manifest exists. It records the supplied intent path in `context_inputs` and creates the
`intent-profile-selection` task. The helper reads the registry hash from the shared
registry path and writes the existing schema version and registry authority fields.

### R2: Route expansion

`expand --route direct|full <topic>` reads the repository manifest, validates its topic
and baseline shape, then appends the missing canonical tasks in template order. It does
not change `status`, registry fields, or existing task definitions. The direct route
adds only `direct-work`; the full route adds the five full-chain task IDs in Section 3.

Expansion is idempotent: a second matching invocation produces no file change. An
existing task with a canonical ID but different definition is a conflict and fails before
writing. An unknown route, malformed topic, missing registry, invalid manifest, or
conflict returns a non-zero actionable error.

### R3: Context inputs

Bootstrap records the intent path. Later workflow stages may append their own existing
spec or plan path to `context_inputs`; no operation adds a path that does not exist.
This preserves the profile policy validator's current file-existence contract.

## 5. Callers and Lifecycle

`fix-intent` invokes bootstrap before intent validation as it does today. Once the user
approves continuation `full`, it invokes full expansion after it records
`workflow.continuation: full` and approves the manifest.

The direct-topic hook invokes direct expansion before storing its session mapping. It
retains its current approved-status and model-binding behavior. Direct expansion never
starts App Server orchestration.

The runner remains unchanged: it continues to read ordered manifest tasks and launch
only an explicitly requested task or explicit `--orchestrate` sequence.

## 6. Compatibility and Failure Handling

No migration runs for existing manifests. Their task lists remain valid for
`--run-task`, and expansion only affects an explicitly selected topic. Existing strict
policy validation remains authoritative after helper writes. Failures leave the original
manifest unchanged through atomic replacement.

## 7. Verification

- Focused tests prove bootstrap, direct expansion, full expansion, task order and
  profile requirements.
- Focused tests prove idempotence and fail-closed rejection of invalid route, topic,
  registry, manifest, and conflicting canonical task.
- Hook tests prove direct expansion retains its session and model guard.
- Runner tests prove an expanded full manifest orchestrates in YAML order.
- The full Bash suite passes, and documentation describes the post-selection expansion.
