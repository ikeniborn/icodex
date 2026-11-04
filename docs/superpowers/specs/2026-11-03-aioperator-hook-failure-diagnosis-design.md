---
topic: aioperator-hook-failure-diagnosis
status: approved
review:
  spec_hash: a8691920584d4f13
  last_run: '2026-11-03'
  phases:
    structure: {status: passed}
    coverage: {status: passed}
    clarity: {status: passed}
    consistency: {status: passed}
  findings:
    - id: F-001
      phase: coverage
      severity: CRITICAL
      section: 'R2: Unsupported Heredoc Forms and Security Preservation'
      section_hash: 5e3ad1391b62c135
      fragment: 'arithmetic contexts'
      text: The initial scanner contract did not distinguish arithmetic shifts from heredoc operators.
      fix: Define arithmetic-region handling and negative false-positive fixtures while inspecting nested executable substitutions.
      verdict: fixed
      verdict_at: '2026-11-03'
    - id: F-002
      phase: clarity
      severity: WARNING
      section: 'R1: Bounded Literal Heredoc Writes'
      section_hash: 5af48a478b50bd5f
      fragment: 'first complete line'
      text: Terminator selection was not explicitly restricted to the first exact matching line.
      fix: Select the first match and test executable suffixes followed by repeated delimiters.
      verdict: fixed
      verdict_at: '2026-11-03'
    - id: F-003
      phase: clarity
      severity: WARNING
      section: 'R4: Explainable and Secret-Safe Refusals'
      section_hash: 1d4f49a910a9ef9d
      fragment: 'artifact_path_sha256'
      text: The initial artifact index was not reproducible or locally resolvable.
      fix: Define the exact path digest and require a documented local lookup recipe.
      verdict: fixed
      verdict_at: '2026-11-03'
    - id: F-004
      phase: clarity
      severity: WARNING
      section: 'R2: Unsupported Heredoc Forms and Security Preservation'
      section_hash: 5e3ad1391b62c135
      fragment: 'here-string alone'
      text: Here-string refusal semantics were ambiguous.
      fix: Preserve existing checks without an automatic heredoc denial or warning.
      verdict: fixed
      verdict_at: '2026-11-03'
chain:
  intent: docs/superpowers/intents/2026-11-03-aioperator-hook-failure-diagnosis-intent.md
---
# Design: Explainable Hook Refusals

**Status:** approved
**Intent:** [Approved intent](../intents/2026-11-03-aioperator-hook-failure-diagnosis-intent.md)

## Scope and Decisions

Correct the demonstrated literal-heredoc false positive, wrong-checkout IDD selection, and misleading refusal messages. Keep the existing hook interfaces and protected-path rules.

The selected approach is a bounded literal-data exemption. A general shell parser adds an unapproved dependency. Removing every heredoc body from inspection would hide executable input. The bounded approach requires no new dependency and denies unsupported heredoc forms explicitly.

This security policy intentionally restricts heredoc commands outside the supported literal-write form. It does not promise general Bash interpretation. Existing non-heredoc handling remains in scope only for the diagnostic and working-directory changes below.

## Acceptance (from intent)

- O1: A literal quoted heredoc appended to an ordinary note passes when its harmless prose contains a slash-prefixed token with the substring `secret`.
- O2: Direct access to protected paths remains blocked. Heredoc handling does not exempt executable expansions or interpreter input from protection.
- O3: When the event working directory or an explicit command working directory identifies the task checkout, IDD evaluates that checkout's applicable artifact. A valid task plan passes despite an unrelated stale plan in another checkout. An applicable stale plan remains blocked.
- O4: A refusal identifies the hook and distinguishes a protected path, ambiguous command analysis, invalid working directory, missing required hash field, and mismatching hash. Diagnostics provide a safe locator or redacted context without reproducing secret values or entire command bodies.
- O5: If command analysis cannot distinguish literal data from executable input confidently, the hook retains the block and explains that uncertainty.
- Done when: O1 through O5 have recorded allow/deny and diagnostic evidence, all required regressions pass, and documentation matches the resulting behavior.
- Done when: result reconciliation passes, the task ledger contains final evidence, and task-page lint has no new finding.

## Components and Data Flow

Keep the changes in the existing hooks and focused tests. Do not introduce a shared parser framework.

| Component | Responsibility | Requirement |
|---|---|---|
| `block-secrets.py` | Classify the bounded literal-write form; inspect the destination; deny unsupported heredoc forms; emit safe diagnostics | R1, R2, R4 |
| `redact-secrets.py` | Continue scanning complete input for secret-looking content; identify itself in denials | R2, R4 |
| `chain-gate.py` | Resolve the effective directory before ownership and validation; distinguish validation reasons | R3, R4, R5 |
| `tests/test_codex_hooks.sh` | Exercise literal writes, unsafe forms, destinations, content checks, and diagnostic non-disclosure | R1, R2, R4 |
| `tests/test_idd_gate.sh` | Exercise competing checkout fixtures, directory precedence, and hash reasons | R3, R4, R5 |
| Repository docs and iwiki | Describe the supported form and the restrictions as shipped | R6 |

For path checking, classify the shell input before extracting path candidates. For the supported literal-write form, inspect the destination and omit only the data body from path extraction. The content hook continues receiving the original payload. No input is rewritten for execution.

## R1: Bounded Literal Heredoc Writes

Permit only an entire command consisting of one literal-write statement and its complete heredoc. This satisfies O1 without exempting arbitrary script input.

The supported statement uses `cat`, `/bin/cat`, or `/usr/bin/cat` with no options, arguments, assignments, wrappers, or additional commands. It has exactly one output redirection (`>` or `>>`) and one input heredoc (`<<`). Accept either redirection order.

The destination is one literal path token. Accept an unquoted token containing only letters, digits, `_`, `-`, `.`, and `/`, or a single/double-quoted token containing those characters plus spaces. Reject expansion syntax, escapes, controls, and shell operators in the destination. Check the destination directly with the existing sensitive-path predicate, including relative destinations that do not start with `/` or `.`.

The delimiter is a nonempty ASCII identifier matching `[A-Za-z_][A-Za-z0-9_]*`, wholly enclosed in single or double quotes. The body starts after the header newline. Its terminator is the first complete line matching the delimiter exactly. Permit only whitespace after that first terminator; never search for a later match to absorb executable suffix text. Do not accept `<<-`, multiple heredocs, descriptor overrides, pipelines, compound commands, or line continuations in this exemption.

The body is literal data because the delimiter is quoted. Shell-like text, including dollar signs and backticks, remains data in this one accepted form. The separate content hook can still reject secret-looking values in that data.

Acceptance: a synthetic reproduction of the recorded note append passes path checking. Both redirection orders and both delimiter quote styles pass. A protected destination is denied. A command after the terminator is denied rather than hidden, including when another matching delimiter appears after that command.

## R2: Unsupported Heredoc Forms and Security Preservation

Block heredoc forms outside R1 with an explicit analysis reason. This satisfies O2 and O5.

Do not execute shell input for classification. Use a bounded lexical scan that tracks single quotes, double quotes, escapes, comments, and arithmetic contexts to identify heredoc operators. Quoted or commented `<<` text alone is not an operator. Recognize the distinct `<<<` token as a here-string: apply existing path/content checks without a heredoc exemption. A here-string alone does not cause an `ambiguous_heredoc` refusal or warning; the existing checks determine exit 0 or 2.

Recognize balanced arithmetic expansion `$((...))` and arithmetic command `((...))` regions. Treat `<<` and `<<=` inside the arithmetic expression as arithmetic operators, not redirections. Track nested parentheses and quoted text without evaluating them. Executable command substitutions nested inside arithmetic still require shell-region inspection; never discard them with the enclosing arithmetic text. If nested executable syntax containing a potential heredoc cannot be classified, deny ambiguous analysis. Plain arithmetic expressions continue through existing path/content checks.

If quoting is malformed in a command containing a potential heredoc operator, deny ambiguous analysis. If a recognized operator has no matching terminator, deny unterminated heredoc. Once a genuine unsupported heredoc operator is found, deny before any data-body exemption.

In particular, deny unquoted delimiters, interpreter consumers such as `bash` and `python3`, command substitutions enclosing a heredoc, multiple statements, and executable suffixes. A quotation inside executable command substitution must not cause the scanner to treat that executable region as literal data; uncertain nested syntax must be denied.

Retain all protected-path and token-file patterns. Retain secret-content scanning over the complete original command, including accepted literal data. This change does not make existing lexical hooks a complete shell sandbox; aliases, external executable behavior, and filesystem alias resolution remain outside the existing contract.

Acceptance: negative fixtures for unquoted expansion, quoted interpreter input, pipeline consumers, multiple heredocs, missing terminators, and suffix commands all exit 2. Literal `<<` text, shell comments, `echo $((1 << 2))`, and `((value <<= 1))` do not trigger a heredoc refusal by themselves. Safe here-strings preserve exit 0; protected-path here-string fixtures preserve exit 2. A heredoc inside command substitution nested in arithmetic must not be exempted. Existing secret-content fixtures still exit 2.

## R3: Effective Working Directory for IDD

Resolve the directory before recording ownership, choosing an artifact, validating it, or running post-write nudges. This satisfies O3.

Select the base directory in this order: a present `tool_input.workdir`, a present event `cwd`, then the hook process directory when both fields are absent. A supplied field must be a nonempty string naming an absolute existing directory. If it is invalid, deny; do not fall back to a different checkout. Catch directory-change errors and deny with the same safe category.

Preserve the existing bounded leading-directory support: for Bash input beginning with a simple literal `cd ABSOLUTE_DIRECTORY &&`, optionally using `cd --`, use that directory for subsequent skill detection and artifact selection. Accept shell quoting around the literal absolute directory. Apply this command-local change after base-directory selection. Relative or dynamic leading directories must produce an explicit unsupported-directory refusal when a gated skill transition depends on them. Do not interpret arbitrary shell scripts to infer directory changes.

The existing ownership and candidate rules operate within the selected directory. Do not use another checkout as a fallback or modify another task's plan. This fix does not replace same-checkout ownership selection with a new topic registry.

Acceptance: two checkout fixtures contain a valid task plan and a newer unrelated stale plan. Event `cwd` alone and explicit `workdir` each select the valid checkout. Explicit `workdir` overrides conflicting event `cwd`. A leading supported `cd` selects its target. Applicable stale plans still exit 2. Invalid supplied directories exit 2 without modifying the ownership ledger.

## R4: Explainable and Secret-Safe Refusals

Every changed refusal message identifies its hook and a stable reason category. This satisfies O4 and O5.

| Hook | Category | Safe information and remediation |
|---|---|---|
| `block-secrets.py` | `protected_path` | Matched static rule, destination/input-field locator, and instruction to use a non-sensitive target |
| `block-secrets.py` | `ambiguous_heredoc` | Unsupported syntax category and instruction to use the documented literal-write form |
| `block-secrets.py` | `unterminated_heredoc` | Header/body line locator and instruction to close the delimiter |
| `redact-secrets.py` | `secret_content` | Existing static secret-type label and instruction to remove secret values from tool input |
| `chain-gate.py` | `invalid_workdir` | Field name or leading-cd source and instruction to supply an absolute existing directory |
| `chain-gate.py` | `missing_hash`, `invalid_hash`, `stale_hash` | Required field name, validation stage, and instruction to rerun the corresponding check-chain stage |

Use static labels and numeric line/token locations instead of echoing arbitrary command fragments, path strings, phase values, or finding text. For IDD artifact identification, emit its stage and `artifact_path_sha256`: the full lowercase SHA-256 of `os.fsencode(os.path.abspath(candidate))` after directory selection. Do not resolve symlinks for this identifier. Document a read-only local lookup recipe that enumerates that stage's artifact paths and calculates the same identifier. The user can resolve the identifier locally without the hook emitting filenames or metadata. The identifier locates a path; it is not the artifact body hash or proof of validation.

Keep stderr and the existing JSON `reason` output where already supported. Keep exit codes 0 and 2. Do not introduce a new stdout protocol or change payloads. The host may independently display the submitted command; tests and non-disclosure guarantees apply to hook-produced output.

Acceptance: each denial contains its hook name and category. Synthetic secret markers embedded in paths, metadata, and heredoc bodies appear in neither hook stdout nor stderr. Hook messages include a corrective action and a safe source locator.

## R5: Hash Diagnostics Without Compatibility Changes

Keep the canonical body-hash algorithm and field names. This satisfies O3 and O4.

Check for the required hash key before comparing its value. An absent key produces `missing_hash`. A present value that is not a 16-character lowercase hexadecimal string produces `invalid_hash`. A well-formed value unequal to the computed hash produces `stale_hash`.

Do not treat `body_sha256` as an alias or recompute approval metadata automatically. Preserve missing-block, malformed-frontmatter, failed-phase, open-finding, and result-verdict gates. Give those existing reasons the hook identifier and safe static descriptions under R4.

Acceptance: missing `plan_hash` alongside `body_sha256`, malformed `plan_hash`, and valid-but-stale `plan_hash` all exit 2 with distinct categories. The canonical valid fixture exits 0. Unrelated external artifacts remain unchanged.

## R6: Verification and Documentation

Use synthetic payloads and temporary checkout/home fixtures. Never execute payload commands or read real secrets. This covers all intent health metrics and completion criteria.

During implementation, run syntax validation and focused hook tests. Run related IDD nudge/wiring and profile integrations if their shared assumptions are affected. Run the full Bash suite once on the final stable implementation state. Record command, exit status, source fingerprint, and repository revision in the task ledger.

Add explicit regression assertions for every R1 through R5 acceptance case. Use literal expected exit codes and diagnostic categories. Check that hooks do not execute a fixture payload by including a harmless would-create marker command and asserting that its marker is absent.

Update repository hook documentation and the iwiki hook-wiring page after implementation. Document the narrowed heredoc form and unsupported-form denials, directory precedence, and hash categories. Declare applicable Given-When-Then scenarios with implementation and verification bindings under the project specification policy. Preserve existing scenario IDs and validate graph bindings when a fresh graph is available.

Acceptance: all required focused and regression checks pass; all outcomes have observable evidence; documentation matches implementation; result reconciliation passes. A required test failure prevents completion.

## Risks and Review Boundaries

The primary risk is silently exempting executable input. R1 accepts a complete bounded command; R2 denies unsupported forms; negative tests must cover command substitutions and trailing execution.

The operational trade-off is intentional denial of complex heredoc commands, including common interpreter invocations. The checked-spec approval explicitly covers this restriction. Supporting more forms later requires a new reviewed extension rather than widening the exemption during implementation.

The pre-existing workdir patch is part of the implementation input. Preserve its known-good explicit-workdir case while revising precedence and error handling. Its original SHA-256 is recorded in the task ledger.

Do not change the approved intent, remove security patterns, or add dependencies during implementation. Return contract drift to the relevant approval gate. Spec approval precedes plan creation; checked-plan approval precedes implementation.
