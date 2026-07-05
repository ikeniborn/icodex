# LoEn Plugin Source

LoEn is an editable Codex plugin source tree for Loop Engineering workflows.
This layer contains source assets only: manifest, skills, hook scripts, agent
definitions, templates, and plugin-local documentation.

## Directories

- `.codex-plugin/plugin.json` identifies the plugin and source asset paths.
- `skills/` contains the user-facing loop workflow skills.
- `hooks/` contains deterministic hook assets that remain inert until an
  integration layer installs and enables the plugin.
- `agents/` contains role-specific agent asset definitions.
- `assets/templates/` contains source templates for later runtime artifacts.

## Artifact Boundary

Active task artifacts are written under `docs/loen/<topic>/`. The plugin source
tree does not write installed cache files and does not depend on icodex runtime
wiring.

## Runtime Artifacts

Each LoEn topic stores durable runtime state under `docs/loen/<topic>/`.
The topic directory contains numbered stage files from `1_goal.md` through
`7_result.md`, a machine-readable `loop.yaml`, append-only `attempts.jsonl`,
an `evidence/` directory, `handoff.md`, and a regenerated per-topic
`audit.html`.

`docs/TODO.md` remains the only global task registry. LoEn does not create a
global audit index.

## Enforcement Hooks

The enforcement layer turns the hook assets into deterministic local checks.
`LOEN_MODE=off` no-ops, `advisory` emits nudges without blocking, `enforce`
blocks missing loop state, stage-order violations, protected path edits, and
missing evidence, and `strict` adds tool, role, shell, network, and
worker/verifier separation checks.

Hook scripts read JSON events from stdin and repository-local loop state from
`LOEN_ARTIFACT_ROOT` plus `LOEN_TOPIC`. They do not call IDD, Superpowers,
chain-gate, or subjective review tools.

## Agent Isolation

LoEn role agents receive context capsules instead of the full main-thread
transcript. A capsule is generated from `docs/loen/<topic>/` artifacts and
contains only the topic, objective, loop mode, current stage, mutable scope,
protected scope, quality gates, relevant files, last evidence summary, and the
specific question or task for that agent.

Planner, verifier, reviewer, and researcher roles are read-only by default.
The worker role is the only default mutating role and must be bound to the
configured mutable scope. The verifier uses a WASM-first execution contract with
network off by default; external container and microVM adapters are outside this
source-layer plugin boundary.

## Automation Governance

LoEn supports optional governance metadata for later scheduled or background
runs. The source layer records the policy in `docs/loen/<topic>/loop.yaml`,
appends automated run records to `attempts.jsonl`, and renders governance state
in the per-topic `audit.html`.

Governance defaults are conservative: `auto_fix: false`, `auto_merge: false`,
`report_only_on_no_findings: true`, and first scheduled runs require human
review when `first_runs_require_human_review` is greater than zero. Automation
does not bypass `LOEN_MODE`, protected-scope checks, evidence gates, or
worker/verifier separation.
