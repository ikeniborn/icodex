# LoEn Core Architecture

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
regenerates `audit.html` from repository artifacts and updates the matching
`docs/TODO.md` row without creating duplicate rows.
