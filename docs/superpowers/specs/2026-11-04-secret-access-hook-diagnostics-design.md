---
topic: secret-access-hook-diagnostics
status: approved
review:
  spec_hash: 920649e437c07f66
  last_run: 2026-11-04
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-11-04-secret-access-hook-diagnostics-intent.md
---
# Design: Secret Access Checks for Diagnostic Heredocs

**Status:** approved
**Intent:** [Approved intent](../intents/2026-11-04-secret-access-hook-diagnostics-intent.md)

## Scope and Approach

Replace syntax-only rejection of safely analyzable Python and Bash heredocs with access checks.
Keep the existing literal-cat exemption, sensitive-path predicate, independent content hook, and exit protocol.
Do not claim complete analysis of arbitrary programs.

Three approaches were considered:

1. Inspect every heredoc body as shell path tokens. Reject this approach because it misses Python literals, aliases, and computed access.
2. Add general Python and shell execution analysis. Reject this approach because it adds a large language and dependency surface.
3. Analyze an explicit diagnostic subset statically. Select this approach because accepted commands have inspectable effects and uncertain cases remain denied.

## R1: Interpreter Envelope

Accept one complete heredoc consumed by `python3`, `/usr/bin/python3`, `bash`, or `/bin/bash`.
Allow an optional Python `-` stdin argument and Bash `--noprofile --norc` flags.
Require one wholly quoted identifier delimiter and no shell expansions in the header.
Permit whitespace after the first exact terminator line; reject executable suffixes.
Reject pipelines, wrappers, unquoted delimiters, descriptor overrides, multiple bodies, and tab-stripping forms.
Keep the existing literal-cat envelope unchanged.

Pass the body to the corresponding analyzer only after envelope validation.
Never execute the body or inspect filesystem contents during classification.
Use `unterminated_heredoc` when a recognized envelope has no terminator.
Use `indeterminate_access` when a heredoc cannot establish a supported execution envelope.

Acceptance: Safe complete Python/Bash examples reach their analyzer; malformed or compound envelopes return exit 2.

## R2: Python Diagnostic Subset

Use the standard-library `ast` parser.
Allow expressions, simple assignments, annotated assignments, `if`, `for`, and expression statements.
Allow literal containers, indexing, comprehensions, comparisons, boolean expressions, arithmetic, and formatted strings over diagnostic data.
Restrict assignment targets to local names and data-container items; reject attribute assignment.
Inspect both branches and every loop body without executing them.
Merge conflicting branch assignments into an unknown value; treat loop-dependent values as unknown.
Reject function/class definitions, exception handlers, context managers, asynchronous constructs, lambdas, and dynamic code execution.

Support `from pathlib import Path`, `import pathlib`, `import json`, and `from collections import Counter`.
Allow the `Path` constructor, `Path.read_text`, `Path.read_bytes`, `Path.exists`, `Path.is_file`, and `Path.is_dir`.
Allow `json.loads`, `json.dumps`, and `Counter` for data processing.
Allow these builtins: `print`, `len`, `str`, `int`, `float`, `bool`, `list`, `tuple`, `dict`, `set`, `sorted`, `enumerate`, `range`, `zip`, `sum`, `min`, `max`, `any`, and `all`.
Allow data methods needed for line processing: `split`, `splitlines`, `strip`, `lstrip`, `rstrip`, `startswith`, `endswith`, `lower`, `upper`, `replace`, `items`, `keys`, `values`, `get`, `append`, `add`, and `setdefault`.

Track static strings and paths through simple assignments, literal string concatenation, and literal path joins.
Keep file contents and derived data abstract; do not read files to determine values.
Require a static path at every supported filesystem operation and apply the unchanged sensitive-path predicate there.
Do not reject a string merely because it mentions a secret path when no access uses it.
Reject unknown imports, unknown calls, callable aliases, reflection, dunder access, subprocesses, environment reads, and calls on unverified receiver types.
Prevent assignment or deletion from rebinding trusted imports and allowed builtin names.
Treat values obtained from data processing as data, never as trusted modules or callables.
Reject callable/module objects used as ordinary data or passed as callbacks.
Return `indeterminate_access` for parser errors or unsupported AST nodes.

Acceptance: A Python heredoc can read `README.md`, count its lines, and print a count.
A static `.env` read returns `protected_path`.
A path derived from file contents returns `indeterminate_access`.
Dead branches that contain protected access remain blocked.

## R3: Bash Diagnostic Subset

Use standard-library shell tokenization for this restricted body grammar.
Accept simple commands separated by newlines or semicolons.
Allow `echo`, `printf`, `pwd`, `cat`, `head`, `tail`, `wc`, and `ls` with literal arguments.
Treat their arguments as static data; check path operands with the existing sensitive-path predicate.
Allow echo/printf literal data without treating secret-path mentions as filesystem access.
For filesystem commands, allow `--` and explicit short diagnostic flags only.
The supported flags are `cat -n/-b/-s/-E/-T/-v/-A`, `head/tail -n NUMBER/-c NUMBER`, `wc -l/-w/-c/-m/-L`, and `ls -l/-a/-A/-h/-d/-n/-i/-s/-t/-r/-1`.
Permit combined single-letter flags for `cat`, `wc`, and `ls`.
Reject other options, including indirect file-list or external-program options.

Reject expansions, substitutions, backticks, globbing, redirections, assignments, shell functions, control operators, and unknown executables.
Reject unknown syntax instead of assuming it is literal data.
Keep shell comments and quoted literal characters distinct from executable syntax where tokenization can establish that distinction.
Do not infer safety from an executable basename; allow only the named simple commands and explicitly supported standard absolute paths.
The supported absolute paths are `/bin/COMMAND` and `/usr/bin/COMMAND` for each listed command.

Acceptance: Bash can count lines in `README.md` and print a literal diagnostic message.
Reading `.env` returns `protected_path`.
Reading a variable-derived path, executing an unknown command, or hiding another command behind a pipeline returns `indeterminate_access`.

## Concrete Diagnostic Examples

The Python body below must pass without the hook reading `README.md` during classification:

```python
from pathlib import Path
text = Path('README.md').read_text()
print(len(text.splitlines()))
```

The Bash body below must pass:

```bash
wc -l README.md
printf '%s\n' 'diagnostic complete'
```

The following bodies define negative acceptance cases:

| Body | Required category |
|---|---|
| Python: `Path('.env').read_text()` after the supported Path import | `protected_path` |
| Python: `Path(Path('paths.txt').read_text()).read_text()` | `indeterminate_access` |
| Python: `reader = Path; reader('README.md')` after the supported Path import | `indeterminate_access` |
| Bash: `cat .env` | `protected_path` |
| Bash: `cat "$diagnostic_path"` | `indeterminate_access` |
| Bash: `wc -l README.md; unknown-reader README.md` | `indeterminate_access` |

Place every example inside the complete quoted interpreter envelope from R1 in subprocess fixtures.

## R4: Integration and Refusals

Keep `block-secrets.py` as the request entrypoint and owner of the sensitive-path predicate.
Place the restricted interpreter analyzers in a colocated helper if separation keeps the hook focused.
Pass the existing sensitive-path predicate into the analyzer; do not copy or weaken the policy.
If a helper is introduced, verify that project-home hook wiring exposes the helper beside the entrypoint.

Return exit 0 for accepted diagnostics and exit 2 for denied requests.
Preserve `protected_path` for resolved protected accesses.
Use `indeterminate_access` for unsupported effects or unresolved accesses.
Explain that the caller must use explicit paths and supported diagnostic operations.
Keep malformed-payload behavior and non-heredoc behavior unchanged.
Do not include submitted code, candidate path values, or secret contents in refusal text.
Preserve literal-data writes and independent scanning of the complete original content by `redact-secrets.py`.

Acceptance: Hook subprocess tests verify exit codes, JSON reason attribution, categories, and absence of secret markers.
No hook classification creates a submitted marker file.

## R5: Verification and Documentation

Add focused tests with literal safe paths, static path aliases/joins, secret reads, unknown receivers, branch/loop handling, and dynamic paths.
Cover trusted-name rebinding, callable aliases, unknown imports, reflection, shell expansions, unknown commands, and executable suffixes.
Update existing syntax-only expectations that this approved contract supersedes.
Preserve all existing protected-access and literal-cat regression cases.
Run Python syntax checks, focused interpreter tests, existing hook tests, and relevant hook-wiring regressions.
Run the full Bash test suite once on the final stable implementation fingerprint.
Run a separate final integration review of changed hook behavior and deployment wiring before creating the PR.

Update `docs/hook-refusals.md` with accepted examples and exact limits.
Update iwiki hook documentation and revise the existing blanket-denial scenario after `wiki_spec_context`.
Retire the old scenario ID when replacing its blanket-denial contract; preserve unchanged literal-write scenarios.
Add explicit scenarios for safe diagnostics and indeterminate-access refusal with implementation/test bindings.
Record commands, exit codes, repository revision, and relevant fingerprints in the task page.
Create a PR from `dev-secret-access-hook-diagnostics` into `master`; do not merge it without separate authorization.

Acceptance: Focused and full checks pass, updated documentation matches observed hook results, and a reviewable PR exists.

## Risks and Limits

This subset will still reject diagnostics using unsupported modules, subprocess calls, or computed paths.
The refusal must state that analysis is indeterminate rather than claiming a secret was found.
Python data analysis must not accidentally grant module or callable capabilities to unknown values.
Branch merging, receiver verification, and import-name rebinding are explicit security review points.
The request guard retains the existing trusted executable resolution, environment, and filesystem-alias assumptions.
It is not a general sandbox or proof of arbitrary program safety.

## Acceptance (from intent)

- Safe Python and Bash diagnostic heredocs pass the hook when their relevant accesses can be determined as safe.
- Commands that access known protected secret paths remain blocked, including accesses inside heredoc bodies.
- Commands with indeterminate relevant accesses remain blocked instead of receiving an unsafe exemption.
- Refusals distinguish protected secret access from indeterminate analysis and explain the next action without revealing secret values.
- Done when: Real hook invocations allow the agreed safe Python and Bash diagnostic fixtures and deny protected-path and indeterminate-access fixtures with exit 2.
- Done when: Focused security regressions and the required final full suite pass, and repository documentation and iwiki describe the verified behavior.
