# Interface Design Pilot

Use this optional reference during accepted `chain/full` brainstorming, before checked-spec approval.
Apply it only to a named unresolved decision about caller obligations or module ownership.
For `direct`, `chain/execute`, or implementation of an approved design, continue the existing workflow without this pilot.

## Compare the Existing Alternatives

Describe the interface as everything a caller must know, including ordering, configuration, failure semantics, and resource ownership.
Keep the project's existing terms.

1. Identify the caller obligations in each alternative already under discussion.
2. Identify which module owns each obligation and its observable result.
3. Ask whether removing a wrapper removes complexity or distributes that complexity among callers.
4. Compare where a likely change would require edits and verification.
5. Recommend the smallest interface that satisfies the approved intent and the actual callers.

A smaller method count alone does not prove a better interface.
Keep separate operations when callers need their independent behavior.
Prefer internal composition when callers only need the combined result.
Do not add adapters or extension points for hypothetical consumers.

## Carry the Decision into the Existing Spec

In the existing design discussion, summarize the selected alternative, caller obligations, failure behavior, and verification boundary.
Include a concrete failure case when the approved contract includes failure guarantees.
Record the accepted decision in the existing spec before its normal validation and approval.
Use the existing acceptance criteria and test strategy; create no separate design artifact or approval gate.

When an interface changes, retain regression checks until replacement tests demonstrate equivalent coverage of the relevant behavior.
A passing happy-path test does not replace checks for failure, ordering, or resource cleanup.

## Scope

Preserve the approved intent and the existing spec, plan, and result gates.
If the comparison conflicts with an approved decision, return the conflict to its existing approval gate.
This reference authorizes no delegation, code changes, commits, tracker publication, or task-lifecycle changes.

## Source

Inspired by Matt Pocock's [codebase-design](https://github.com/mattpocock/skills/blob/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/codebase-design/SKILL.md).
This pilot adapts the interface-cost questions to icodex's existing workflow.
