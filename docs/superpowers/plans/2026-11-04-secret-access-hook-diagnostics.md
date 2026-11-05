---
topic: secret-access-hook-diagnostics
status: approved
review:
  plan_hash: 3eea71712a60abbe
  last_run: 2026-11-05
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings:
    - id: F-001
      phase: dependencies
      severity: CRITICAL
      section: 'Task 3: Documentation, Final Verification, Review, and PR'
      section_hash: 50b4584d28a93fa9
      fragment: 'Do not issue final `result: OK` or close the task while the PR requirement remains unfulfilled.'
      text: Final result reconciliation preceded the PR that the same plan requires for completion.
      fix: Perform pre-PR reconciliation, then final result after PR creation; commit and push result metadata and verify remote HEAD.
      verdict: fixed
      verdict_at: 2026-11-05
    - id: F-002
      phase: coverage
      severity: CRITICAL
      section: 'Task 1: Python Access Analysis and Interpreter Envelope'
      section_hash: 09197dcabdd1d01b
      fragment: 'Before analyzing a loop, invalidate names assigned anywhere in its body, including its target.'
      text: Generic loop and alias coverage did not prevent stale safe values across iterations or mutable aliases.
      fix: Specify pre-loop invalidation, zero-iteration merging, comprehension scope, and conservative alias handling with concrete denial fixtures.
      verdict: fixed
      verdict_at: 2026-11-05
    - id: F-003
      phase: verifiability
      severity: WARNING
      section: 'Task 2: Bash Static Commands and Shared Hook Regressions'
      section_hash: 720bda0ea78f3e59
      fragment: 'The current isolated fixture contains only `hooks/example.py`.'
      text: The deployment check did not specify installing the actual entrypoint and helper in the temporary test fixture.
      fix: Copy both files into the fixture and invoke allowed and denied payloads through the project-home symlink.
      verdict: fixed
      verdict_at: 2026-11-05
    - id: F-004
      phase: clarity
      severity: WARNING
      section: 'Task 2: Bash Static Commands and Shared Hook Regressions'
      section_hash: 720bda0ea78f3e59
      fragment: 'Retain lexical quote/escape provenance before shlex removes it.'
      text: Shell tokenization lacked explicit handling of lost quote provenance and printf variable assignment.
      fix: Preserve lexical provenance, distinguish separators from data, and test expansions, escapes, comments, and printf -v rejection.
      verdict: fixed
      verdict_at: 2026-11-05
    - id: F-005
      phase: coverage
      severity: WARNING
      section: 'Requirement Coverage and Evidence'
      section_hash: c3369cd3a64d6d76
      fragment: 'Every allowed command/flag family; quote-aware separators and literal data; expansion/unknown-command denials'
      text: Broad test lists left allowed-operation coverage, legacy paths, content scanning, and no-read evidence implicit.
      fix: Add requirement-to-evidence mapping, exhaustive operation tables, non-heredoc regressions, no-read instrumentation, and interpreter content-hook checks.
      verdict: fixed
      verdict_at: 2026-11-05
chain:
  intent: docs/superpowers/intents/2026-11-04-secret-access-hook-diagnostics-intent.md
  spec: docs/superpowers/specs/2026-11-04-secret-access-hook-diagnostics-design.md
result_check:
  verdict: OK
  source: plan
  plan_hash: 3eea71712a60abbe
  last_run: 2026-11-05
  reviewed: true
  docs_checked: true
---
# Secret Access Hook Diagnostics Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for inline execution. Keep parent ownership of code, verification, and iwiki writes.

**Goal:** Allow the approved safe Python/Bash diagnostic subset while denying protected and indeterminate accesses, then create a tested PR into master.

**Architecture:** Keep the path policy in `block-secrets.py`. Add a colocated static analyzer helper for the restricted Python/Bash bodies. Validate the interpreter envelope before analyzing effects; preserve independent secret-content checks.

**Tech Stack:** Existing Bash launcher/tests and Python standard library, including ast, shlex, json, unittest, and subprocess fixtures.

**Spec:** [Approved design](../specs/2026-11-04-secret-access-hook-diagnostics-design.md)

## Global Constraints

- Never execute the body or inspect filesystem contents during classification.
- Keep the existing literal-cat envelope unchanged.
- Pass the existing sensitive-path predicate into the analyzer; do not copy or weaken the policy.
- Keep malformed-payload behavior and non-heredoc behavior unchanged.
- Do not include submitted code, candidate path values, or secret contents in refusal text.
- Preserve literal-data writes and independent scanning of the complete original content by `redact-secrets.py`.
- Run the full Bash test suite once on the final stable implementation fingerprint.
- Create a PR from `dev-secret-access-hook-diagnostics` into `master`; do not merge it without separate authorization.

## Task 1: Python Access Analysis and Interpreter Envelope

Closes intent safe-Python acceptance, protected-access refusal, and indeterminate-access refusal; implements R1, R2, and the Python part of R4.

**Files:**
- Create: `.codex-isolated/hooks/_diagnostic_heredoc.py`.
- Create: `tests/test_diagnostic_heredocs.py` and `tests/test_diagnostic_heredocs.sh`.
- Modify: `.codex-isolated/hooks/block-secrets.py`.

**Interfaces:**
- Consume `is_sensitive_path(path) -> (bool, rule)` from the entrypoint.
- Produce `analyze_python(body, sensitive_path) -> (category_or_none, rule_or_none, body_line)`.
- Preserve the existing `classify_heredoc(command)` interface for literal-cat and unsupported envelopes.
- Integrate interpreter analysis before the existing fallback heredoc refusal.
- Use a helper exception carrying category, static rule, and numeric body line; catch it at the analyzer boundary.
- Define `AccessRefusal(category, rule, line)` in the helper. Return `(None, None, 1)` on acceptance.
- Convert body-relative lines to command lines once at the entrypoint by adding the header line.
- Return immediately from path classification after an accepted interpreter body; do not rescan it with shell path-token extraction.

- [ ] Step 1: Add subprocess fixtures for safe Python, protected reads, computed paths, and no-execution evidence.

```python
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / '.codex-isolated/hooks/block-secrets.py'

def invoke_body(language, body):
    command = language + " <<'DIAG'\n" + body + "\nDIAG"
    payload = {"tool_name": "Bash", "tool_input": {"command": command}}
    clean_env = {key: os.environ[key] for key in ('PATH', 'LANG') if key in os.environ}
    return subprocess.run([sys.executable, str(HOOK)], input=json.dumps(payload),
                          cwd=ROOT, env=clean_env, timeout=10,
                          capture_output=True, text=True, check=False)

def test_python_line_count(self):
    result = invoke_body("python3", "from pathlib import Path\ntext = Path('README.md').read_text()\nprint(len(text.splitlines()))")
    self.assertEqual(result.returncode, 0)

def test_python_protected_read(self):
    result = invoke_body("python3", "from pathlib import Path\nPath('.env').read_text()")
    self.assertEqual(result.returncode, 2)
    self.assertIn("protected_path", result.stderr)
```

Use unittest classes `PythonDiagnosticTests` and `BashDiagnosticTests` for focused execution. Make the Bash wrapper execute the Python test file from its repository root. Do not execute the submitted bodies in hook-classification tests.

- [ ] Step 2: Run the Python class and record the expected safe-command failure before implementation.

```bash
python3 tests/test_diagnostic_heredocs.py PythonDiagnosticTests
```

Expected: safe Python diagnostics fail under the original blanket denial.

- [ ] Step 3: Add a quoted interpreter envelope parser and the Python analyzer.

Use the first exact terminator and reject a non-whitespace suffix. Accept only R1 executable names and flags. Keep literal-cat matching first and retain its existing behavior. Translate unsupported interpreter envelopes into `indeterminate_access`; preserve `unterminated_heredoc` for recognized incomplete envelopes.

Implement abstract values for static strings, static paths, primitive/container data, and unknown values. Keep trusted callable/module symbols separate from ordinary data. Use explicit AST-node handlers; refuse every unhandled node. Resolve literal path joins and concatenation without executing expressions.

```python
blocked, rule = sensitive_path(static_path)
if blocked:
    raise AccessRefusal("protected_path", rule, node.lineno)
```

At a filesystem sink, reject unknown paths before invoking the predicate. Validate receivers and arguments before allowing R2 calls. Reject trusted-name rebinding and capability values stored in containers or passed as callbacks. Analyze both branches and loop bodies; merge inconsistent values into unknown rather than retaining a convenient branch value.

Before analyzing a loop, invalidate names assigned anywhere in its body, including its target. A single optimistic traversal is insufficient for later iterations. Include the zero-iteration state when merging after the loop. Keep comprehension targets scoped; do not overwrite an outer binding. Inspect expressions inside keyword arguments, annotations, f-strings, subscripts, and every conditional branch. Refuse unsupported argument shapes instead of ignoring them.

Do not retain static container elements after mutation through an alias. Either propagate mutation through shared abstract identity or conservatively treat container-derived paths as unknown. Keep ordinary container data processing available. Reject module/callable values at every container insertion and assignment path.

Add `indeterminate_access` to the entrypoint's reason map before any analyzer can return it. Handle AST parsing failures at the analyzer boundary without echoing source or raising a traceback. Keep literal-cat denial semantics intact; change only the interpreter/unsupported-envelope expectations required by R1/R4.

- [ ] Step 4: Extend Python fixtures across the exact R2 grammar and denial cases.

Cover static aliases and joins; data line processing; json/Counter; loops and comprehensions; protected access in dead branches; conflicting branch paths; aliasing callables; reassigned builtin/import names; reflection; unknown imports; subprocesses; environment reads; unsupported statements; parser failures; protected-path mention without access; and no marker-file creation.

Add explicit denial fixtures for both bodies below. They must not receive exit 0:

```python
from pathlib import Path
p = Path('README.md')
for n in range(2):
    p.read_text()
    p = Path('.env')
```

```python
from pathlib import Path
paths = ['README.md']
alias = paths
alias[0] = '.env'
Path(paths[0]).read_text()
```

Use table-driven positive cases for every R2 builtin, data method, import form, filesystem method, and supported statement/expression family. Add negative cases for attribute assignment, callbacks hidden in containers, trusted-name rebinding through loop/comprehension targets, and accesses inside keyword arguments or annotations. Test protected-path mentions as data alongside actual protected accesses, so acceptance cannot result from removing all body checks.

- [ ] Step 5: Verify Python syntax and focused cases, then commit the independently tested Python behavior.

```bash
python3 -m py_compile .codex-isolated/hooks/block-secrets.py .codex-isolated/hooks/_diagnostic_heredoc.py tests/test_diagnostic_heredocs.py
python3 tests/test_diagnostic_heredocs.py PythonDiagnosticTests
git diff --check
```

Expected: exit 0, safe examples accepted, protected and unknown accesses denied with the specified categories.

## Task 2: Bash Static Commands and Shared Hook Regressions

Closes intent safe-Bash acceptance and shared refusal behavior; implements R3 and completes R1/R4.

**Files:**
- Modify: `.codex-isolated/hooks/_diagnostic_heredoc.py`, `.codex-isolated/hooks/block-secrets.py`, `tests/test_diagnostic_heredocs.py`, `tests/test_codex_hooks.sh`, and `tests/test_isolated.sh`.

**Interfaces:**
- Consume the same sensitive-path predicate and refusal representation as Task 1.
- Produce `analyze_bash(body, sensitive_path) -> (category_or_none, rule_or_none, body_line)`.
- Keep the entrypoint's JSON reason and exit-code protocol unchanged.

- [ ] Step 1: Add failing Bash diagnostic and protected-path fixtures.

```python
def test_bash_line_count(self):
    result = invoke_body("bash", "wc -l README.md\nprintf '%s\\n' 'diagnostic complete'")
    self.assertEqual(result.returncode, 0)

def test_bash_dynamic_path(self):
    result = invoke_body("bash", 'cat "$diagnostic_path"')
    self.assertEqual(result.returncode, 2)
    self.assertIn("indeterminate_access", result.stderr)
```

```bash
python3 tests/test_diagnostic_heredocs.py BashDiagnosticTests
```

Expected: at least the safe Bash case fails before the Bash analyzer exists.

- [ ] Step 2: Implement the R3 simple-command tokenizer and argument validation.

Track quoting/comments so syntax is not mistaken for literal data. Reject executable expansions, redirects, unknown control operators, assignments, and globbing. Accept only the documented bare commands and their `/bin/` and `/usr/bin/` forms. Validate command-specific short flags and numeric head/tail arguments. Check every filesystem operand; do not treat echo/printf literal text as a file access.

Retain lexical quote/escape provenance before shlex removes it. Plain `shlex.split` output alone cannot distinguish a quoted semicolon from a command separator or a literal dollar sign from expansion. Treat newline and semicolon as separators only outside quotes/comments. Reject printf's `-v` variable-assignment option under the no-assignment rule. Exercise escaped newlines, quote concatenation, empty quoted words, and comments following an existing word.

```python
if command_name not in allowed_commands:
    raise AccessRefusal("indeterminate_access", None, line)
for operand in filesystem_operands:
    blocked, rule = sensitive_path(operand)
    if blocked:
        raise AccessRefusal("protected_path", rule, line)
```

- [ ] Step 3: Expand Bash/envelope tests and update old syntax-only expectations.

Cover every allowed executable and flag family; quoted literal metacharacters; semicolons and comments; relative/absolute secret paths; joined quotes in filenames; `--`; unsupported options; substituted executable names; unquoted delimiters; wrappers; pipelines; multiple bodies; suffixes; tab stripping; descriptors; missing terminators; and repeated delimiter lines.

In `tests/test_codex_hooks.sh`, replace only expectations superseded by the approved contract. Keep old protected-access and literal-cat cases. Assert the static reason category and no submitted marker leakage.

- [ ] Step 4: Verify independent secret-content scanning and helper deployment.

Use the shared hooks symlink created by `setup_codex_home`. Extend `tests/test_isolated.sh` to confirm the helper can be imported through a project-home hook path. Submit a literal-data heredoc containing a synthetic token to both hooks; path classification may allow it, but redact-secrets must deny it without echoing its marker.

The current isolated fixture contains only `hooks/example.py`. Copy the actual entrypoint and helper into its temporary shared hooks directory before setup. Invoke the entrypoint through the resulting project-home symlink with a safe diagnostic payload and a denied payload. Merely checking symlink existence does not verify helper loading. Also verify Python and Bash interpreter bodies still reach independent secret-content scanning.

Retain tests for malformed hook payloads, non-heredoc commands, Read/Edit/Write/apply_patch path checks, and safe-template exceptions. Use synthetic paths and markers only. Verify missing safe files can be classified without opening them; instrument filesystem reads during direct analyzer tests and assert none occur. Preserve the existing no-execution marker test.

- [ ] Step 5: Run focused and related regressions, then commit the complete runtime change.

```bash
bash -n tests/test_diagnostic_heredocs.sh tests/test_codex_hooks.sh tests/test_isolated.sh
bash tests/test_diagnostic_heredocs.sh
bash tests/test_codex_hooks.sh
bash tests/test_isolated.sh
git diff --check
```

Expected: all commands exit 0. Each accepted and denied outcome is exercised through the actual hook subprocess.

## Task 3: Documentation, Final Verification, Review, and PR

Closes all intent completion criteria and implements R5. This task depends on Tasks 1 and 2.

**Files:**
- Modify: `docs/hook-refusals.md`.
- Update through MCP: `icodex/plugin-and-hook-wiring`, `icodex/specification/explainable-hook-refusals`, the task page, and its linked history.
- Maintain: chain review frontmatter and `docs/profiles/secret-access-hook-diagnostics.yaml` context paths after artifacts exist.

**Interfaces:**
- Consume the verified hook outcomes and unchanged source fingerprint from Tasks 1/2.
- Produce current user documentation, GWT contracts, chain result evidence, final integration review, and a PR targeting master.

- [ ] Step 1: Document the exact supported diagnostic subset and category-specific recovery.

Include the safe examples from the spec. Explain that `indeterminate_access` means the request cannot be analyzed, not that a secret was detected. Preserve the literal-cat explanation and independent scanning rule.

- [ ] Step 2: Update the existing wiki contract with compare-and-swap protection.

Call `wiki_spec_context` before replacing the blanket-denial scenario. Retire its old ID and create new safe-diagnostic and indeterminate-access scenarios. Preserve unchanged literal-write IDs. Use explicit implementation/test file bindings. Read current pages/revisions before every mutation. Run wiki lint after the last write.

After symbol changes, request indexing through an available local checkout-capable server. Track any returned job to terminal state and verify publication separately. If no such server is available, record that limitation. If the resulting graph is ready and fresh, resolve bindings. Otherwise preserve declared selectors, use repository search/tests, and record `graph_unavailable`. Do not claim hosted source indexing succeeded. Refresh stale wiki links after the final wiki write only when an active ready snapshot supports it.

- [ ] Step 3: Record the final relevant code-state fingerprint and run the full suite once.

```bash
python3 -m py_compile .codex-isolated/hooks/block-secrets.py .codex-isolated/hooks/_diagnostic_heredoc.py tests/test_diagnostic_heredocs.py
git diff --check
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: every Bash test script exits 0. Record the executed script count, command, exit status, repository revision, and fingerprint. Reuse matching evidence across result review and PR creation. If a failure occurs, diagnose narrowly and rerun only invalidated checks before another required final full-suite run.

- [ ] Step 4: Perform the final integration review and intent outcome audit.

Review changed hook/parser code separately from implementation, including interpreter envelopes, branch/loop state, callable capabilities, dynamic paths, flags, and project-home helper import. Check every R1-R5 acceptance item against direct subprocess evidence. Fix confirmed defects and rerun the relevant checks. Do not waive this review.

- [ ] Step 5: Perform pre-PR reconciliation against the complete branch diff.

Reconcile implemented outcomes, documentation, reviewed paths, and test evidence before publishing. Record PR delivery as pending. Do not issue final `result: OK` or close the task while the PR requirement remains unfulfilled. Use the task ledger for execution progress; preserve the approved plan body and its hash.

- [ ] Step 6: Commit remaining reviewed changes, push the development branch, and create the PR.

```bash
git status --short
git push -u origin dev-secret-access-hook-diagnostics
gh pr create --base master --head dev-secret-access-hook-diagnostics --title "fix(hooks): allow statically checked diagnostic heredocs" --body-file /tmp/icodex-secret-access-hook-diagnostics-pr.md
gh pr view --json url,baseRefName,headRefName,state
```

Write the PR body to the indicated temporary file with actual behavior and verification results. Follow the repository PR template if present. Never include secret values or raw diagnostic credentials.

- [ ] Step 7: Run final result reconciliation after the PR exists.

Run `$check-chain result docs/superpowers/plans/2026-11-04-secret-access-hook-diagnostics.md --since=origin/master` against the full branch diff. Verify the PR URL, base/head branches, open state, and actual remote head revision. Only now can all delivery commitments receive final `OK`.

Persist result frontmatter, commit the reviewed metadata, and push it to the same PR. Confirm the PR head matches local HEAD. Reuse full-suite evidence when only documentation/review metadata changed. Record the PR URL and final evidence in iwiki, run task-page lint, verify an empty spool, and close the task.

Expected: clean working tree, open PR into master, successful result reconciliation, matching full-suite evidence, and durable task lifecycle done. Report any pending remote CI separately from completed local checks. Do not merge the PR.

## Requirement Coverage and Evidence

| Source | Deliverable | Required evidence |
|---|---|---|
| R1 interpreter envelope | Task 1 parser and Task 2 envelope regressions | Every permitted executable/flag form accepts; incomplete, compound, and suffixed forms deny |
| R2 Python subset | Task 1 analyzer | Positive cases for every listed operation; negative branch, loop, alias, capability, and dynamic-path cases |
| R3 Bash subset | Task 2 analyzer | Every allowed command/flag family; quote-aware separators and literal data; expansion/unknown-command denials |
| R4 policy and protocol | Tasks 1/2 entrypoint integration | Unchanged predicate, exit codes, attributed JSON reasons, numeric line mapping, no source/marker leakage |
| R4 deployment and independent scanning | Task 2 project-home fixtures | Real helper import through shared hook symlink; content hook denies synthetic secret in accepted body |
| R5 verification | Tasks 1/2 focused checks and Task 3 final review | Syntax and focused passes; separately recorded review; one full-suite pass for final fingerprint |
| R5 documentation and GWT | Task 3 steps 1/2 | Updated repository/wiki docs, context before scenario changes, lint, graph evidence or explicit limitation |
| R5 PR delivery and intent completion | Task 3 steps 6/7 | Open PR into master at pushed HEAD; final result OK; clean worktree; empty spool and durable done |

## Approval and Execution

HUMAN CHECKPOINT: Obtain approval of this checked implementation plan before runtime edits.
After approval, execute inline in this session; user authorization already covers completion, tests, and PR creation.
Escalate only scope/security-policy changes or an unresolved contradiction with the approved intent/spec.
