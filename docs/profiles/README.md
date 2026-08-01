# Project Profile Manifests

This directory contains approved project manifests read directly from the target
repository. Each manifest names its task requirements and pins the exact byte hash of
the shared profile registry.

At chain start, `fix-intent` creates a draft manifest for the new topic. Bootstrap is
intentionally one task: `intent-profile-selection` covers intent review and routed-profile
selection. The manifest remains a draft until the user explicitly approves it with the
checked intent; the profile runner accepts only the resulting approved manifest.

After continuation selection, expansion is route-specific. The direct-topic hook's
missing-manifest bootstrap creates an approved direct-work-only manifest, which never
enters full-chain App Server orchestration. Generic `expand --route direct` instead adds
`direct-work` to an existing valid manifest. The `fix-intent` lifecycle expands an
approved chain manifest only after it records `workflow.continuation: full`; the helper
enforces explicit full authorization and an approved chain-manifest shape, rather than
reading intent frontmatter. The full route's fixed task order is
`intent-profile-selection`, `spec-design`, `plan-writing`, `implementation`, and
`result-reconciliation`; their profile requirements are reviewed manifest policy, not
runtime inference. Expansion does not reference a future spec or plan context artifact
until that artifact exists and is tracked.

For direct work, the user sends `@topic <kebab-case-topic>` in the active session. When
its direct-topic hook must bootstrap a missing manifest, that explicit command creates an
approved direct-work-only `engineering` manifest at
`docs/profiles/<topic>.yaml` and binds the topic only to the current local session.
The next user prompt is checked against that profile's model; its wording is not part of
the protocol. This interactive path does not change the full-chain App Server runner.

Never copy the shared registry or runtime routing state into this directory. Runtime
state is local and disposable; it does not alter approved policy.

`status: approved` requires explicit review before commit. A registry hash change
invalidates manifests and requires review plus a new pin. Unsupported YAML constructs
fail closed.
