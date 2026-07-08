# LoEn Core Architecture

## System Map

LoEn has three boundaries: editable source assets, icodex vendored cache, and
runtime loop artifacts written by skills and hooks.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'background': '#1e1e2e', 'primaryColor': '#313244', 'primaryTextColor': '#cdd6f4', 'primaryBorderColor': '#89b4fa', 'lineColor': '#888888', 'secondaryColor': '#181825', 'tertiaryColor': '#45475a'}}}%%
flowchart LR
    subgraph src["Plugin source"]
        Manifest[".codex-plugin/plugin.json"]
        Skills["skills/*/SKILL.md"]
        Hooks["hooks/loen_*.py"]
        Templates["assets/templates/*"]
        Docs["README.md and docs/architecture.md"]
    end

    Vendor["scripts/vendor-loen.sh"]

    subgraph cache["Vendored cache"]
        CacheManifest["plugin.json"]
        CacheSkills["skills and hooks"]
        CacheDocs["user docs"]
    end

    subgraph runtime["Repository runtime state"]
        Topic["docs/loen/&lt;topic&gt;/"]
        TopicAudit["docs/loen/&lt;topic&gt;/audit.html"]
        Todo["docs/TODO.md"]
    end

    Manifest --> Vendor
    Skills --> Vendor
    Hooks --> Vendor
    Templates --> Vendor
    Docs --> Vendor
    Vendor --> CacheManifest
    Vendor --> CacheSkills
    Vendor --> CacheDocs
    CacheSkills --> Topic
    Topic --> TopicAudit
    CacheSkills --> Todo

    classDef source fill:#89b4fa,color:#1e1e2e,stroke:#74c7ec,stroke-width:2px
    classDef process fill:#f9e2af,color:#1e1e2e,stroke:#df8e1d
    classDef cache fill:#94e2d5,color:#1e1e2e,stroke:#179299
    classDef runtime fill:#a6e3a1,color:#1e1e2e,stroke:#40a02b
    class Manifest,Skills,Hooks,Templates,Docs source
    class Vendor process
    class CacheManifest,CacheSkills,CacheDocs cache
    class Topic,TopicAudit,Todo runtime
```

## Source Layer

The core layer establishes the editable plugin source tree. It is safe to
validate without installing the plugin into Codex because all assets are plain
JSON, Markdown, Python, TOML, YAML, and HTML files.

## Hook Assets

Hook scripts are deterministic and read only JSON tool events plus LoEn topic
artifacts such as `docs/loen/<topic>/loop.yaml`. They are source-layer plugin
assets until a later icodex integration layer installs and enables the plugin,
but their behavior is implemented and fixture-tested in this repository.

The enforcement layer owns loop-state gating, mutable/protected path checks,
tool and role policy, shell and network policy, final evidence checks, and
audit regeneration. The hooks do not depend on IDD->SDD, Superpowers, or
frontmatter review state.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'background': '#1e1e2e', 'primaryColor': '#313244', 'primaryTextColor': '#cdd6f4', 'primaryBorderColor': '#89b4fa', 'lineColor': '#888888', 'secondaryColor': '#181825', 'tertiaryColor': '#45475a'}}}%%
flowchart TD
    Event["Codex tool event"] --> ModeCheck{"LOEN_MODE active?"}
    ModeCheck -- "No" --> PassThrough["Allow event"]
    ModeCheck -- "Yes" --> TopicLoad["Load docs/loen/&lt;topic&gt;/loop.yaml"]
    TopicLoad --> ScopeCheck{"Path inside allowed scope?"}
    ScopeCheck -- "No" --> DenyScope["Deny with policy reason"]
    ScopeCheck -- "Yes" --> ToolCheck{"Tool and role allowed?"}
    ToolCheck -- "No" --> DenyTool["Deny with policy reason"]
    ToolCheck -- "Yes" --> EvidenceCheck{"Required evidence present?"}
    EvidenceCheck -- "No" --> DenyEvidence["Deny until evidence exists"]
    EvidenceCheck -- "Yes" --> AuditUpdate["Append evidence and refresh docs/loen/&lt;topic&gt;/audit.html"]
    AuditUpdate --> PassWithRecord["Allow with recorded audit trail"]

    classDef decision fill:#f9e2af,color:#1e1e2e,stroke:#df8e1d
    classDef allow fill:#a6e3a1,color:#1e1e2e,stroke:#40a02b
    classDef deny fill:#f38ba8,color:#1e1e2e,stroke:#d20f39
    classDef action fill:#89b4fa,color:#1e1e2e,stroke:#74c7ec
    class ModeCheck,ScopeCheck,ToolCheck,EvidenceCheck decision
    class PassThrough,PassWithRecord allow
    class DenyScope,DenyTool,DenyEvidence deny
    class Event,TopicLoad,AuditUpdate action
```

## Agent Assets

Agent definitions describe role names, default write posture, artifact root, and
allowed output files. Verifier, reviewer, and researcher roles are read-only by
default.

## Runtime Boundary

Installation, launch-time wiring, cache layout, and runtime enablement are owned
by later integration layers. This source tree is not an installed plugin cache.

## Runtime Artifact Boundary

Runtime topic artifacts are repository-local and live under
`docs/loen/<topic>/`. Hooks and skills read that directory as durable loop
state so the loop can continue across context compaction, new threads,
subagents, reviews, and later automation.

`loop.yaml` is the machine-readable contract for one topic. The audit writer
regenerates `docs/loen/<topic>/audit.html` from repository artifacts and updates
the matching `docs/TODO.md` row without creating duplicate rows.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'background': '#1e1e2e', 'primaryColor': '#313244', 'primaryTextColor': '#cdd6f4', 'primaryBorderColor': '#89b4fa', 'lineColor': '#888888', 'secondaryColor': '#181825', 'tertiaryColor': '#45475a'}}}%%
flowchart TD
    subgraph topic_dir["docs/loen/&lt;topic&gt;/"]
        Goal["1_goal.md"]
        Context["2_context.md"]
        Plan["3_plan.md"]
        Act["4_act.md"]
        Check["5_check.md"]
        Reflect["6_reflect.md"]
        Result["7_result.md"]
        LoopYaml["loop.yaml"]
        Attempts["attempts.jsonl"]
        Evidence["evidence/*"]
        GovernanceEvidence["evidence/* verifier output"]
        AuditHtml["docs/loen/&lt;topic&gt;/audit.html"]
        HumanReview["human review requirement"]
    end

    Goal --> Context
    Context --> Plan
    Plan --> Act
    Act --> Check
    Check --> Reflect
    Reflect --> Result
    LoopYaml --> Goal
    LoopYaml --> Plan
    LoopYaml --> Result
    LoopYaml --> GovernanceRun["loen:loop-governance"]
    GovernanceRun --> GovernancePolicy["governance policy"]
    GovernancePolicy --> LoopYaml
    GovernancePolicy --> Attempts
    Attempts --> AuditHtml
    GovernanceRun --> GovernanceEvidence
    GovernanceEvidence --> AuditHtml
    GovernancePolicy --> HumanReview
    HumanReview --> AuditHtml
    Evidence --> AuditHtml
    Result --> TodoRow["docs/TODO.md row"]
    AuditHtml --> TodoRow

    classDef artifact fill:#89b4fa,color:#1e1e2e,stroke:#74c7ec
    classDef contract fill:#f9e2af,color:#1e1e2e,stroke:#df8e1d
    classDef report fill:#a6e3a1,color:#1e1e2e,stroke:#40a02b
    classDef governance fill:#94e2d5,color:#1e1e2e,stroke:#179299
    class Goal,Context,Plan,Act,Check,Reflect,Result,Attempts,Evidence,GovernanceEvidence artifact
    class LoopYaml,GovernancePolicy,HumanReview contract
    class GovernanceRun governance
    class AuditHtml,TodoRow report
```

## Loop Runner

The guided runner path is:

```text
loop-start -> run contract in loop.yaml -> loop-run state machine -> result/handoff
```

`loop-start` chooses a safe topic slug, creates the topic artifacts, writes
`3_plan.md`, and waits for approval. After approval it records the runner
contract in `loop.yaml`:

- `run:` stores `mode`, `subtype`, `plan_approved`, `plan_hash`, state, pass
  budget, approval source, and approval time.
- `release_policy:` stores target branch, merge strategy, verifier requirement,
  evidence requirement, `scope_limit`, and recovery policy for merge-release.
- `governance:` stores owner, schedule, alert policy, `auto_fix`, and
  `auto_merge` for governance topics.

`loen:loop-run <topic>` validates the approved plan hash, mode, subtype, scope,
verifier, budget, and rollback or recovery policy before entering the
`prepare -> act -> check -> reflect` state machine. It stops with `handoff.md`
when approval, policy, verifier, protected scope, budget, or recovery checks fail.
It writes `7_result.md` only when terminal evidence supports completion.

Governance subtypes are `report-only`, `auto-fix`, and `merge-release`.
`report-only` records findings without product-file edits. `auto-fix` can change
only mutable scope when `governance.auto_fix: true`. `merge-release` also
requires `governance.auto_merge: true` and complete `release_policy:`.

Audit visibility stays topic-scoped: runner attempts append `attempts.jsonl`,
verifier output goes under `evidence/`, and `audit.html` is regenerated for
`docs/loen/<topic>/`. Manual `loop-plan`, `loop-act`, `loop-check`, and
`loop-reflect` remain compatible with existing topics and with users who want to
drive each stage directly.

## Agent Isolation Levels

LoEn separates role context and execution through five documented levels:

| Level | Mechanism | Purpose |
|---|---|---|
| L0 | Same session | Simple advisory use. |
| L1 | Codex subagent with context capsule | Context isolation and role separation. |
| L2 | Separate `CODEX_HOME`, worktree, and Codex profile | Stronger local split for worker and verifier runs. |
| L3 | WASM executor for deterministic tools and evals | Lightweight verifier execution isolation. |
| L4 | External heavy adapter | Future container or microVM adapter for workloads WASM cannot cover. |

The source plugin implements L1 capsule assets, L2 metadata, and a WASM-first
L3 verifier contract. It does not run container or microVM workloads in core.

## WASM-first verifier

Verifier capsules reject WASM execution configs that enable network access.
The default execution contract uses `isolation: wasm`, `executor: wasmtime`,
`network: off`, a read-only project mount, and a writable `/tmp/loen` mount for
ephemeral verifier output.

## Automation Governance

The automation-governance layer is a contract, not a scheduler. Future CI
triage, PR babysitting, dependency audit, eval governance, and cost/latency
governance integrations can call the same topic artifact APIs, but this
repository only stores deterministic policy and evidence.

Scheduled runs reuse `docs/loen/<topic>/`, append JSON records to
`attempts.jsonl`, preserve verifier evidence under `evidence/`, and regenerate
`docs/loen/<topic>/audit.html`. Existing hooks still enforce active-loop state,
protected scope, shell/network policy, evidence requirements, and `LOEN_MODE`;
automation payloads are treated as ordinary tool events with extra metadata.
