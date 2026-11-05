# Hook Refusals and Recovery

The shared icodex hooks inspect tool requests before execution. Exit 0 allows a request; exit 2 blocks it. A refusal names its hook and a reason category. Hook diagnostics omit command bodies, secret values, and raw candidate paths. The host may independently display the submitted command.

## Literal Heredoc Writes

The path hook permits one complete literal-data write using `cat`, `/bin/cat`, or `/usr/bin/cat`, one output redirection, and one wholly quoted identifier delimiter. These forms are supported:

```bash
cat >> notes.md <<'END'
/tmp/check.pyPASSneverprintssecret/body is ordinary prose.
END
```

```bash
cat <<"END" > "note file.md"
Literal text, including dollar signs and backticks.
END
```

The destination is still checked for protected-path rules, including relative paths. The separate `redact-secrets.py` hook scans all original content, including the literal body.

The destination may contain letters, digits, `_`, `-`, `.`, and `/`. Quoted destinations may also contain spaces. The delimiter must match `[A-Za-z_][A-Za-z0-9_]*`. The first complete matching line ends the body. Only whitespace may follow it.

## Diagnostic Interpreter Heredocs

One complete quoted heredoc can feed `python3`, `/usr/bin/python3`, `bash`, or `/bin/bash`. Python accepts an optional `-`; Bash accepts `--noprofile` and `--norc`. The hook analyzes the body without running it or reading its files.

```bash
python3 <<'END'
from pathlib import Path
text = Path('README.md').read_text()
print(len(text.splitlines()))
END
```

```bash
bash <<'END'
wc -l README.md
printf '%s\n' 'diagnostic complete'
END
```

Python supports literal paths, path joins, read-only Path methods, primitive/container data processing, and a restricted set of builtins. Supported imports are pathlib, json, and collections.Counter. Both branches and loop bodies are inspected. Unknown calls, reflection, callable aliases, subprocesses, environment reads, and unresolved paths produce `indeterminate_access`. Generator bodies cannot rely on mutable current path bindings. See the [approved subset](superpowers/specs/2026-11-04-secret-access-hook-diagnostics-design.md#r2-python-diagnostic-subset) for exact operations.

Bash supports simple literal commands separated by newlines or semicolons: echo, printf, pwd, cat, head, tail, wc, and ls, including their /bin and /usr/bin paths. Filesystem commands accept only the documented short flags. Expansions, globbing, assignments (including printf -v), redirections, unknown commands, and pipelines remain indeterminate. Quoted literal text is distinguished from executable syntax.

Resolved protected accesses receive `protected_path`. A path derived from file contents receives `indeterminate_access`. Printing a literal path name alone is not filesystem access. The independent content hook continues to scan the entire submitted body.

## Unsupported Heredoc Forms

Unquoted or mixed delimiters, `<<-`, multiple bodies, descriptor overrides, wrappers, pipelines, and executable suffixes do not qualify for interpreter analysis. Unsupported interpreter envelopes receive `indeterminate_access`. The existing literal-cat exemption remains unchanged; a suffix after its first terminator receives `ambiguous_heredoc`. A recognized envelope without its closing delimiter receives `unterminated_heredoc`.

Use explicit static paths and supported diagnostic operations when analysis is indeterminate. Move unsupported executable code into an ordinary reviewed script when appropriate. Do not disable the hooks to force a request through.

Quoted/commented `<<` text and arithmetic shifts are not heredoc operators. Here-strings (`<<<`) retain the previous path and content checks; they receive no literal-data exemption.

## Reason Categories

| Hook | Category | Recovery |
|---|---|---|
| `block-secrets.py` | `protected_path` | Inspect the rule and numeric source locator locally; choose a non-sensitive target |
| `block-secrets.py` | `ambiguous_heredoc` | Use the supported single-cat form for data, or a reviewed script for executable input |
| `block-secrets.py` | `indeterminate_access` | Use explicit paths and supported diagnostic operations; this category does not claim a secret was found |
| `block-secrets.py` | `unterminated_heredoc` | Close the quoted delimiter on its own line |
| `redact-secrets.py` | `secret_content` | Remove secret values from the tool input |
| `chain-gate.py` | `invalid_workdir` | Supply an absolute existing directory in the named field or leading directory command |
| `chain-gate.py` | `missing_hash` | Run the applicable `check-chain` stage to produce its canonical hash field |
| `chain-gate.py` | `invalid_hash` | Correct the field through the applicable validation stage; it must be a lowercase 16-character hex string |
| `chain-gate.py` | `stale_hash` | Revalidate the changed artifact before the next transition |
| `chain-gate.py` | `phase_not_passed`, `open_critical`, `result_not_passed` | Resolve the validation findings and rerun the corresponding stage |

Malformed review blocks, phases, findings, or frontmatter retain their validation denials. `body_sha256` is not an alias for `plan_hash`. The canonical body-hash algorithm is unchanged.

## IDD Working Directory

Before ownership recording, artifact selection, and post-write nudges, the gate chooses the highest-priority supplied directory:

1. `tool_input.workdir`.
2. Event `cwd`.
3. Process working directory when neither field is present.

A supplied null, empty, relative, nonexistent, or non-directory value is invalid. An invalid selected field does not fall back to another checkout. An ignored lower-priority field cannot override a valid selected directory.

For a gated skill load in Bash, a simple leading `cd /absolute/directory &&` or `cd -- '/absolute/path with spaces' &&` selects that command's checkout after base-directory validation. Relative or dynamic leading directories are rejected for gated transitions. The hook does not interpret arbitrary shell scripts to infer directory changes.

Ownership and candidate rules apply within the selected checkout. This fixes cross-checkout selection; it does not introduce topic-based selection among multiple plans in one checkout.

## Resolve an Artifact Locator

IDD denials and nudges expose the stage and `artifact_path_sha256`. This is SHA-256 of the filesystem-encoded absolute candidate path after entering the checkout. It is a locator, not a body hash or validation approval.

Run this read-only Python recipe locally. Enter the same checkout selected by the hook. It prints only a matching path and reads no artifact content.

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

Entering a directory symlink follows process-cwd semantics. A candidate-file symlink is not resolved for the locator. Use the matched artifact with the `check-chain` stage named in the refusal.

## Security Boundary

The hooks are lexical request guards, not a complete shell sandbox. Existing assumptions about trusted executable resolution, external program behavior, and filesystem aliases remain unchanged. Classification never executes submitted commands or reads secret files. Unsupported syntax stays blocked rather than silently receiving a data exemption.
