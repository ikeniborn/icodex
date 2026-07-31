---
review:
  intent_hash: b8beeefc0274ae59
  last_run: 2026-07-31
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
workflow:
  route: chain
  continuation: execute
result_check:
  verdict: OK
  source: intent
  intent_hash: b8beeefc0274ae59
  last_run: 2026-07-31
  reviewed: true
  docs_checked: true
---

# Intent: direct-topic-profile

**Date:** 2026-07-31
**Status:** approved

## Objective

Give every direct task a durable topic profile so a user can switch to the required
model and reasoning effort, send the next task prompt, and continue work in the same
Codex session without repeating profile selection.

## Desired Outcomes

- A direct task accepts one canonical topic through `@topic <slug>` in the active session
  and creates its approved initial `engineering` profile.
- A direct topic has `docs/profiles/<topic>.yaml` as its durable profile authority.
- An unchanged, matching profile allows work without a switch.
- After the user switches to the required profile, the next user prompt continues
  protected work when the documented hook model matches.
- Full-chain topic-profile creation and App Server routing retain their existing behavior.

## Health Metrics

- `--run-task` and `--orchestrate` retain current policy validation, handoff, and exact
  `model` plus `effort` routing.
- The profile-wiring test confirms that secret, chain, LoEn, caveman, and iwiki hooks
  remain configured.
- Existing smoke and argument-parser tests pass for an ordinary launch without a direct topic.
- Git-ignore tests confirm that session logs, credentials, and local runtime state remain
  untracked.

## Strategic Context

- Interacts with: `icodex.sh`, command argument parsing, profile wiring and hooks,
  `docs/profiles/`, and Bash tests.
- Priority trade-off: trust > speed > cost.
- The user selects model and effort manually. Hooks must use documented payload data only.

## Constraints

### Steering

- `@topic <slug>` is the sole direct-topic authority and the user's explicit approval of
  the initial `engineering` profile; the thread title is a user-interface hint only.
- A new or resumed session uses the same `@topic <slug>` command.
- A direct topic profile lives at `docs/profiles/<topic>.yaml`.
- The first user prompt after a manual profile switch is the user's confirmation; its
  wording is not a protocol field.

### Hard

- Do not extract a topic from a transcript, thread title, SQLite database, or diagnostic logs.
- Do not change full-chain or App Server runner semantics.
- A hook may compare only the documented `model` field; it must not infer reasoning effort.
- Do not invoke App Server, `/model`, or a continuation loop from a hook.
- Do not track session logs, credentials, or mutable runtime state.

## Autonomy Zones

- Full autonomy: accept a valid `@topic <slug>`, persist a local `session_id` to topic
  mapping, and create its user-approved initial `engineering` profile.
- Guarded: compare the active model on the next user prompt and add concise hook context
  without parsing the prompt wording.
- Proposal-first: change the shared registry, approve a manifest automatically, or alter
  full-chain/App Server semantics.
- No autonomy: read transcripts, SQLite, or logs; change a model automatically; create a
  continuation loop.

## Stop Rules

- Halt if: topic is absent, profile authority is absent or invalid, or the active model differs.
- Escalate if: the design requires hook access to undocumented effort, title, transcript,
  SQLite, or logs.
- Done when: a direct topic is recorded in the active session and has a profile manifest;
  after a manual profile switch, any next user prompt permits continuation for a matching
  model; full-chain profile tests show no regression.
