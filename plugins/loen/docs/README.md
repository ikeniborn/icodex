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
