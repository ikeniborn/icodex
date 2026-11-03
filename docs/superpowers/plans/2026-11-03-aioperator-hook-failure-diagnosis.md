---
topic: aioperator-hook-failure-diagnosis
status: approved
result_check:
  verdict: OK
  source: plan
  plan_hash: 31d04a9fe2e56b83
  last_run: '2026-11-03'
  reviewed: true
  docs_checked: true
review:
  plan_hash: 31d04a9fe2e56b83
  last_run: '2026-11-03'
  phases:
    structure: {status: passed}
    coverage: {status: passed}
    dependencies: {status: passed}
    verifiability: {status: passed}
    consistency: {status: passed}
  findings:
    - id: F-001
      phase: verifiability
      severity: CRITICAL
      section: 'Task 3: Integrate Documentation, GWT Evidence, and Final Verification'
      section_hash: 2e51f2ba2d25575d
      fragment: 'os.chdir(root)'
      text: The initial lookup recipe preserved checkout symlink spelling instead of matching hook cwd semantics.
      fix: Enter the checkout before computing candidate paths and verify real and symlinked checkout cases.
      verdict: fixed
      verdict_at: '2026-11-03'
    - id: F-002
      phase: consistency
      severity: WARNING
      section: 'Task 1: Literal Data Classification and Secret-Safe Refusals'
      section_hash: 13635144d978f4ac
      fragment: 'Match overlapping prefixes longest-first'
      text: Overlapping lexer prefixes had no explicit precedence.
      fix: Match arithmetic expansion before command substitution and here-string before heredoc.
      verdict: fixed
      verdict_at: '2026-11-03'
chain:
  intent: docs/superpowers/intents/2026-11-03-aioperator-hook-failure-diagnosis-intent.md
  spec: docs/superpowers/specs/2026-11-03-aioperator-hook-failure-diagnosis-design.md
---
# Explainable Hook Refusals Implementation Plan

> **For agentic workers:** Use `superpowers:executing-plans` for sequential execution in this session after checked-plan approval. Steps use checkboxes. The parent owns all wiki writes.

**Goal:** Permit the demonstrated safe note write while preserving secret protection, selecting the correct IDD checkout, and explaining every affected refusal safely.

**Architecture:** Keep bounded command classification inside `block-secrets.py`. Keep working-directory selection and artifact validation inside `chain-gate.py`. Preserve full-input secret-content checks in `redact-secrets.py` and the existing hook payload/exit-code contract.

**Tech Stack:** Python standard library, existing PyYAML dependency in the IDD hook, Bash tests, iwiki MCP.

**Spec:** [Approved design](../specs/2026-11-03-aioperator-hook-failure-diagnosis-design.md), approval hash `a8691920584d4f13`.

## Global Constraints

- Keep the changes in the existing hooks and focused tests. Do not introduce a shared parser framework.
- Do not execute shell input for classification.
- Retain all protected-path and token-file patterns.
- Retain secret-content scanning over the complete original command, including accepted literal data.
- Keep exit codes 0 and 2.
- Do not introduce a new stdout protocol or change payloads.
- Do not treat `body_sha256` as an alias or recompute approval metadata automatically.
- Do not change the approved intent, remove security patterns, or add dependencies during implementation.
- Return contract drift to the relevant approval gate.
- Work on `dev-aioperator-hook-failure-diagnosis` in the current checkout. Preserve unrelated changes and never commit to `master`.

## Inputs, Ownership, and File Map

The branch already contains approved intent and spec commits. The result comparison baseline is `adf1fb4`, the approved-spec commit before implementation. The only pre-existing runtime edit is the workdir patch in `chain-gate.py`; its SHA-256 is `bddecac73bb4a020e7cd90d9ce7732875333a1e8661a62a1c3457b4ff2795df5`.

| File or surface | Responsibility | Owner task |
|---|---|---|
| `.codex-isolated/hooks/block-secrets.py` | Literal-write classifier and safe path/analysis denials | 1 |
| `.codex-isolated/hooks/redact-secrets.py` | Hook identity and static secret-content diagnostics | 1 |
| `tests/test_codex_hooks.sh` | Secret-hook regression fixtures | 1 |
| `.codex-isolated/hooks/chain-gate.py` | Directory resolution, hash categories, secret-safe artifact diagnostics | 2 |
| `tests/test_idd_gate.sh` | IDD behavior and diagnostic fixtures | 2 |
| `tests/test_idd_nudge.sh`, `tests/test_idd_wiring.sh`, `tests/test_profile_hook.sh`, `tests/test_direct_topic_hook.sh` | Existing integration assertions; change diagnostic expectations only if affected | 2 |
| `docs/hook-refusals.md` | Supported syntax, restrictions, diagnostics, local artifact lookup | 3 |
| `docs/README.ru.md` | Link to the new hook reference using the surrounding language | 3 |
| iwiki `icodex/plugin-and-hook-wiring` | Document shipped hook behavior in existing sections | 3 |
| Applicable iwiki specification pages | GWT contracts and implementation/test bindings | 3 |
| Task ledger and linked history | Commands, fingerprints, outcomes, review events | Parent throughout |

No new runtime module is required. Tasks execute in order 1, 2, 3. Task 2 does not import Task 1 internals; Task 3 integrates both behavior changes.

## Task 1: Literal Data Classification and Secret-Safe Refusals

**Closes:** R1, R2, the secret-hook portion of R4; O1, O2, O4, O5.

**Files:** Modify `block-secrets.py`, `redact-secrets.py`, and `tests/test_codex_hooks.sh` from the file map.

**Interfaces:** Preserve `main()`, tool aliases, payload field handling, and existing JSON `reason` output. Add a local classifier returning `(kind, destination, category, line)`, where kind is `none`, `literal_write`, or `deny`. Only `literal_write` supplies a destination. The classifier does not emit output or execute a command.

- [ ] **1.1 Record the baseline and add failing public-interface fixtures.** Reuse the shell test helpers. Run Python fixture assertions under `assert_exit` so failures contribute to the Bash suite result. Invoke hooks as subprocesses with JSON stdin; never execute the command strings.

Use this fixture pattern inside `tests/test_codex_hooks.sh`:

```python
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
hooks = root / '.codex-isolated/hooks'

def invoke(name, command):
    payload = {'tool_name': 'Bash', 'tool_input': {'command': command}}
    return subprocess.run(
        [sys.executable, str(hooks / name)],
        input=json.dumps(payload), text=True, capture_output=True, check=False,
    )

cases = [
    ('literal append', "cat >> note.md <<'EOF'\n/tmp/check.pyPASSneverprintssecret/body\nEOF", 0, None),
    ('literal overwrite', 'cat <<"EOF" > "note file.md"\n/secret is prose\nEOF', 0, None),
    ('protected destination', "cat > .env <<'EOF'\nplain\nEOF", 2, 'protected_path'),
    ('relative protected destination', "cat > config/credentials.txt <<'EOF'\nplain\nEOF", 2, 'protected_path'),
    ('unquoted delimiter', 'cat > note.md <<EOF\n$(cat /run/secrets/demo)\nEOF', 2, 'ambiguous_heredoc'),
    ('interpreter', "bash <<'EOF'\ncat /run/secrets/demo\nEOF", 2, 'ambiguous_heredoc'),
    ('python interpreter', "python3 <<'EOF'\nprint('ordinary input')\nEOF", 2, 'ambiguous_heredoc'),
    ('pipeline', "cat <<'EOF' | bash\necho hello\nEOF", 2, 'ambiguous_heredoc'),
    ('two bodies', "cat <<'A' <<'B'\na\nA\nb\nB", 2, 'ambiguous_heredoc'),
    ('missing terminator', "cat > note.md <<'EOF'\nplain", 2, 'unterminated_heredoc'),
    ('first terminator wins', "cat > note.md <<'EOF'\nplain\nEOF\necho suffix\nEOF", 2, 'ambiguous_heredoc'),
    ('quoted operator', "printf '%s' '<<EOF'", 0, None),
    ('comment operator', 'echo ok # <<EOF', 0, None),
    ('arithmetic expansion', 'echo $((1 << 2))', 0, None),
    ('arithmetic assignment', '((value <<= 1))', 0, None),
    ('safe here-string', 'cat <<< plain', 0, None),
    ('protected here-string', 'cat <<< /run/secrets/demo', 2, 'protected_path'),
]
for label, command, code, category in cases:
    result = invoke('block-secrets.py', command)
    assert result.returncode == code, (label, result.returncode, code)
    if category:
        assert 'block-secrets.py' in result.stderr, label
        assert category in result.stderr, label
        assert json.loads(result.stdout)['reason'], label
```

Extend this table with both redirection orders, all three allowed cat spellings, quoted destinations with spaces, escaped/mixed delimiters, `<<-`, descriptor overrides, trailing whitespace, and trailing executable commands. Include a heredoc inside command substitution and another inside command substitution nested in arithmetic; both must deny. Include a literal quoted body containing `$()` and backticks; it remains data.

Add diagnostics fixtures using the synthetic marker `DO_NOT_ECHO_7e42` inside protected paths and secret-containing input. Assert that neither stdout nor stderr contains the marker. Include a would-create marker command in the input and verify that no marker file appears in its temporary directory.

Run the focused baseline:

```bash
bash tests/test_codex_hooks.sh
```

Expected before implementation: new literal-data and hook-identity assertions fail; existing security assertions retain their previous results. Diagnose unexpected baseline failures separately.

- [ ] **1.2 Add the bounded classifier.** Use a left-to-right character scan, not a regular expression over the entire body. First attempt the complete R1 header/body grammar. If that fails, use lexical state to distinguish actual or uncertain heredoc syntax from ordinary text. Return `none` only after that scan establishes no heredoc operator requiring classification.

Implement the following transitions in local functions within `block-secrets.py`. Match overlapping prefixes longest-first: `$((` before `$(`, and `<<<` before `<<`. Interpret closing delimiters using the active lexical context, not a global substring search.

| State | Input | Required transition |
|---|---|---|
| Shell | Unquoted `#` at a shell word boundary | Skip to newline as a comment |
| Shell | Single quote | Read literal characters through the matching quote |
| Shell/double quote | Backslash | Consume escaped character with the applicable shell quote rule |
| Shell | Double quote | Enter quoted state; preserve recognition of executable substitutions |
| Shell/double quote/arithmetic | `$(` or backtick substitution | Inspect the executable region; never treat it as literal body data |
| Shell | `$((` or command-boundary `((` | Enter balanced arithmetic state |
| Arithmetic | `<<` or `<<=` | Treat as arithmetic operators; keep nested substitutions inspectable |
| Shell | `<<<` | Consume as a here-string operator; retain original path/content checks |
| Shell | `<<` or `<<-` | Record a genuine heredoc operator; unsupported complete form denies |
| Any applicable state | Unterminated quote or nested executable syntax with a potential heredoc | Return `deny`, `ambiguous_heredoc` |

For the R1 header, match only the complete approved grammar: allowed cat command, one output redirection, one wholly quoted identifier delimiter, and one literal destination. Preserve raw quote information before removing token quotes. Do not classify quoted operators by passing the header blindly through `shlex.split`.

After a valid header, search lines in order and stop at the first exact delimiter line. Missing delimiter returns `unterminated_heredoc`. Non-whitespace after the first delimiter returns `ambiguous_heredoc`. On success return the literal destination and its header line; never scan that body as filesystem paths.

Integrate classification into the existing path collection:

```python
kind, destination, category, line = classify_heredoc(command)
if kind == 'deny':
    deny(category, 'command line %d' % line)
if kind == 'literal_write':
    paths = [destination]
else:
    paths = command_path_tokens(command)
```

Keep classifier support limited to the approved syntax. If implementation needs more syntax, return to the spec gate instead of widening the exemption.

- [ ] **1.3 Make diagnostics static and keep content scanning intact.** Add `deny(category, locator, rule=None)` inside the path hook. It exits 2, writes a static message to stderr, and emits the same message through JSON `reason`. Use a path-field name or numeric token/line locator; never echo candidate path text.

Use messages shaped like:

```text
block-secrets.py: protected_path; source=command token 3; rule=secret. Use a non-sensitive target.
block-secrets.py: ambiguous_heredoc; source=command line 1. Use the documented single-cat literal-write form.
block-secrets.py: unterminated_heredoc; source=command line 1. Close the quoted delimiter on its own line.
redact-secrets.py: secret_content; kind=API key. Remove secret values from tool input.
```

Add only the static hook identifier/category/remediation to `redact-secrets.py`. Preserve all regexes and full-input collection. Do not interpolate an untrusted tool name. Use a synthetic API-key-shaped string in an otherwise accepted literal heredoc: the path hook permits it and the content hook denies it without echoing the value.

- [ ] **1.4 Verify and commit the independent deliverable.** Compile the two changed hooks with Python's `compile` built-in, using their source text. Run `bash -n` on the changed test and rerun the focused suite. Record command, exit, and source hashes.

```bash
python3 -c 'from pathlib import Path; [compile(p.read_text(), str(p), "exec") for p in map(Path, [".codex-isolated/hooks/block-secrets.py", ".codex-isolated/hooks/redact-secrets.py"])]'
bash -n tests/test_codex_hooks.sh
bash tests/test_codex_hooks.sh
git diff --check
git add .codex-isolated/hooks/block-secrets.py .codex-isolated/hooks/redact-secrets.py tests/test_codex_hooks.sh
git commit -m "fix(hooks): classify literal heredocs and explain secret refusals"
```

**DoD:** R1/R2 acceptance fixtures and secret-hook R4 fixtures pass; direct protected paths and content checks remain denied; submitted commands are never executed. A focused security review finds no executable-input exemption.

## Task 2: Correct IDD Context and Validation Diagnostics

**Closes:** R3, R5, the IDD portion of R4; O3 and O4.

**Files:** Modify `.codex-isolated/hooks/chain-gate.py` and `tests/test_idd_gate.sh`.

**Interfaces:** Add `resolve_workdir(data)` returning an absolute directory or a static error category/source. Add `artifact_locator(candidate)` returning the path SHA-256. Preserve `gate_reason(path, rule)` as a reason-or-None interface; make all reasons static categories and safe field labels.

- [ ] **2.1 Add failing two-checkout fixtures and diagnostic cases.** Extend the existing IDD shell test with a Python subprocess fixture using a temporary root and a separate temporary Codex home. Copy the process environment and set `CODEX_HOME` only in the subprocess environment dictionary. Do not repurpose the shell's `HOME` or `CODEX_HOME`.

Create plan fixtures with actual newlines and canonical hashes:

```python
import hashlib

def write_plan(directory, value):
    path = directory / 'docs/superpowers/plans/fixture.md'
    path.parent.mkdir(parents=True, exist_ok=True)
    body = '# Fixture\n'
    digest = hashlib.sha256(body.encode()).hexdigest()[:16]
    field = '  plan_hash: "' + (digest if value == 'valid' else value) + '"\n'
    path.write_text('---\nreview:\n' + field +
                    '  phases:\n    structure: {status: passed}\n'
                    '  findings: []\n---\n' + body)
    return path
```

Run the hook process from the foreign checkout. Use `Skill` payloads with `session_id` and `skill: executing-plans` so existing ownership claiming runs. Exercise this matrix, asserting expected exit and ledger ownership where applicable:

| Payload or fixture | Expected result |
|---|---|
| Only event `cwd` points to valid checkout | 0; owns valid plan only |
| `workdir` points to valid checkout, event `cwd` points elsewhere | 0; explicit workdir wins |
| Both directory fields absent | Existing process-cwd behavior |
| Explicit `workdir` is null, empty, relative, nonexistent, file, or non-string | 2 `invalid_workdir`; ledger bytes unchanged |
| Invalid event `cwd`, absent workdir | 2 `invalid_workdir`; no fallback |
| Valid explicit workdir and invalid event `cwd` | 0; ignored lower-priority field does not veto |
| Bash `cd /absolute/valid &&` followed by skill load | 0; command-local directory wins |
| Bash `cd -- '/absolute/path with spaces' &&` followed by skill load | 0 |
| Gated skill load after relative or dynamic leading `cd` | 2 `invalid_workdir`; no guessed directory |
| Selected plan has valid-format stale hash | 2 `stale_hash` |
| `plan_hash` absent, `body_sha256` present | 2 `missing_hash` |
| `plan_hash` is integer, null, uppercase, or wrong length | 2 `invalid_hash` |
| Canonical valid hash, phases passed | 0 |

Also verify explicit directory handling for the PostToolUse nudge and existing Write/apply_patch paths. Inject `os.chdir` failure through a local imported-module fixture, not by changing real filesystem permissions or running as another user. Assert exit 2 with a safe reason.

Place `DO_NOT_ECHO_7e42` in a candidate filename, invalid directory value, phase value, and finding ID. Assert absence in stdout/stderr. Assert that the emitted artifact digest equals the independent SHA-256 of the selected absolute path.

```bash
bash tests/test_idd_gate.sh
```

Expected baseline: the current patch passes explicit workdir but fails event-cwd selection and new reason/locator assertions. Preserve that passing explicit-workdir behavior.

- [ ] **2.2 Resolve directories before any ownership mutation.** Replace the current inline workdir block with the scoped helper. Distinguish a missing key from a present null value using dictionary membership. Select the highest-priority present field and validate only that field. Use the current process directory only when both keys are absent.

For the existing leading-cd extension, retain only an anchored simple literal absolute directory followed by `&&`. Preserve token quote information and reject expansion characters, redirects, separators, and substitutions in the directory word. Support the optional `--`. Apply this directory after base selection. When a gated skill transition contains an unsupported leading relative/dynamic `cd`, deny with `invalid_workdir` and a static `leading_cd` locator.

Call `os.chdir` inside a bounded `OSError` handler before `record_ownership`, `handle_skill`, `handle_write`, or `handle_nudge`. Do not fall through to the broad fail-open handler for invalid directory resolution. Preserve the existing broad fail-open policy for unrelated internal failures, but remove exception text that could disclose input values.

- [ ] **2.3 Separate hash reasons and add the reproducible locator.** Implement the required hash checks in this order:

```python
key = rule['hash_key']
if key not in block_data:
    return 'missing_hash: ' + rule['block'] + '.' + key
value = block_data[key]
if not isinstance(value, str) or not re.fullmatch(r'[0-9a-f]{16}', value):
    return 'invalid_hash: ' + rule['block'] + '.' + key
if value != body_hash(path):
    return 'stale_hash: ' + rule['block'] + '.' + key
```

Keep canonical hashing and phase/finding validation unchanged. Replace interpolated phase values, finding IDs, verdict values, and exception text with static reason categories. Generate the locator with:

```python
def artifact_locator(candidate):
    return hashlib.sha256(os.fsencode(os.path.abspath(candidate))).hexdigest()
```

Keep IDD's stderr-only denial interface. Include `chain-gate.py`, category, stage, and `artifact_path_sha256`. Remediation instructs the user to resolve the locator using the documented local recipe, then run the corresponding check-chain stage. Do not print raw candidate paths or metadata in denial or nudge messages.

- [ ] **2.4 Verify related integrations and commit.** Run focused syntax and IDD tests. Run nudge, wiring, profile, and direct-topic suites because directory selection runs before shared dispatch and diagnostics affect post-write output. Update diagnostic-string expectations only where required; preserve behavioral assertions.

```bash
python3 -c 'from pathlib import Path; p=Path(".codex-isolated/hooks/chain-gate.py"); compile(p.read_text(), str(p), "exec")'
bash -n tests/test_idd_gate.sh
bash tests/test_idd_gate.sh
bash tests/test_idd_nudge.sh
bash tests/test_idd_wiring.sh
bash tests/test_profile_hook.sh
bash tests/test_direct_topic_hook.sh
git diff --check
git add .codex-isolated/hooks/chain-gate.py tests/test_idd_gate.sh
git commit -m "fix(idd): resolve task directories and distinguish validation refusals"
```

If diagnostic expectations in the named related tests need changes, include only those changes in this commit. No test outcome may be weakened to force a pass.

**DoD:** R3/R5 and IDD R4 fixtures pass; invalid directories cannot claim a foreign artifact; stale or incompatible artifacts remain blocked; diagnostics contain no synthetic secret markers.

## Task 3: Integrate Documentation, GWT Evidence, and Final Verification

**Closes:** R6 and all intent completion criteria. Depends on Tasks 1 and 2.

**Files:** Create `docs/hook-refusals.md`; modify the documentation index and authorized wiki pages. Update related diagnostic expectations only if required by Task 2.

**Interfaces:** The document consumes the shipped categories, allowed grammar, directory precedence, and `artifact_path_sha256` algorithm. It introduces no runtime interface.

- [ ] **3.1 Write the operator reference and test the locator recipe.** Document accepted literal-write examples, denied interpreter/unquoted/compound examples, unchanged here-string/arithmetic behavior, directory precedence, and each refusal category. Explain that wrapper logs may independently echo submitted commands.

Include this read-only local lookup recipe, with user-supplied values entered as data:

```python
import hashlib
import os
from pathlib import Path

root = Path(input('Selected checkout: ')).absolute()
os.chdir(root)
root = Path(os.getcwd())
stage = input('Stage (intent/spec/plan/result): ').strip()
wanted = input('artifact_path_sha256: ').strip()
patterns = {'intent': ('intents', '*-intent.md'),
            'spec': ('specs', '*-design.md'),
            'plan': ('plans', '*.md'),
            'result': ('plans', '*.md')}
directory, pattern = patterns[stage]
for path in sorted((root / 'docs/superpowers' / directory).glob(pattern)):
    digest = hashlib.sha256(os.fsencode(os.path.abspath(path))).hexdigest()
    if digest == wanted:
        print(path)
```

Exercise the recipe with the temporary artifact path fixture, including a quoted filename and a symlinked checkout path. Enter the checkout with `os.chdir` before deriving the absolute candidate path, matching the hook's process-cwd semantics. Expect the same digest when selecting the checkout through its real path or a directory symlink. Do not resolve a symlink at the candidate-file level. Assert that the digest resolves the intended path without reading its contents. Link the reference from the repository documentation index.

- [ ] **3.2 Update wiki contracts through MCP.** Verify the existing binding before mutations. Read current hook-wiring sections and revisions. Update the IDD section and add a secret-hook section if absent. State the implemented syntax boundary and operational restriction explicitly.

Search existing specification scenarios before adding any. Read `wiki_spec_context` for each existing scenario changed. Preserve its ID if its contract is unchanged. For new contracts, use stable IDs for literal-note writes, ambiguous heredoc denial, task-directory selection, and distinct hash refusal categories. Bind actual implementation and test selectors from Tasks 1/2; do not invent selectors.

When the local server has the checkout, request a code graph rebuild and observe the same job's terminal result. When graph publication or freshness is unavailable, retain selectors, record `graph_unavailable`, and use repository/test evidence. Resolve specification bindings on a ready fresh graph. Run wiki lint after the last wiki mutation.

- [ ] **3.3 Run final security review and the full suite once.** Review the final diff for executable-data confusion, first-terminator handling, nested substitutions, directory fallback, secret leakage, and scope drift. Obtain an independent read-only review through the applicable code-review skill. Record dispatch and return in the task ledger. Resolve findings before the final full suite.

```bash
git diff --check
for t in tests/test_*.sh; do bash "$t" || exit 1; done
git rev-parse HEAD
git diff HEAD -- .codex-isolated/hooks tests | sha256sum
```

Capture the suite command, exit status, revision, changed-source fingerprint, and final fixture outcomes. Expected: full-suite exit 0 and all O1–O5 acceptance observations satisfied. If a check fails, diagnose the narrow failure; rerun only invalidated evidence. An unchanged full-suite pass is reused by result reconciliation.

- [ ] **3.4 Commit scoped docs and reconcile the result.** Stage only reviewed documentation and any scoped test expectation changes not already committed. Invoke `check-chain result` with this plan after implementation and verification. Reconcile every requirement and health metric against actual evidence; expected outcomes in this plan are not completion evidence.

```bash
git add docs/hook-refusals.md docs/README.ru.md
git commit -m "docs(hooks): explain supported commands and refusal recovery"
```

Result review must include changes since the pre-implementation baseline, even after the task commits. Use the selected plan with the skill's `--since` input when the working tree is clean. Update the task ledger and linked history, run final lint, and mark done only after result OK and all delivery gates pass. Offer optional HTML only at result, as required by check-chain.

**DoD:** Final suite passes once for the recorded state; all six requirements and five outcomes have evidence; documentation and GWT bindings reflect shipped behavior; result is OK; task-page lint has no new finding.

## Coverage and Checkpoints

| Requirement | Task | Expected evidence |
|---|---|---|
| R1 | 1 | Literal append/overwrite pass, destination/suffix denials |
| R2 | 1 | Unsafe forms deny; arithmetic, comments, quoted operators, and here-strings retain semantics |
| R3 | 2 | Directory matrix, correct ownership, unchanged ledger on invalid input |
| R4 | 1, 2, 3 | Hook identity/categories, no synthetic-marker leakage, working locator recipe |
| R5 | 2 | Missing/invalid/stale categories and valid canonical pass |
| R6 | 3 | Docs, GWT evidence, focused/regression/full-suite evidence, result reconciliation |

HUMAN CHECKPOINT: approve this checked plan before Task 1. Routine implementation choices within the approved contract remain autonomous. A new dependency, broader grammar, changed hash compatibility, or security-policy change returns to the spec/intent gate.

The existing hook patch must remain unchanged until Task 2 deliberately revises it. If its fingerprint changes concurrently, stop and reconcile ownership before proceeding.
