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
