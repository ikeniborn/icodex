# Hook Refusals and Recovery

The shared icodex hooks inspect tool requests before execution. Exit 0 allows a request; exit 2 blocks it. A refusal names its hook and a reason category. Hook diagnostics omit command bodies, secret values, and raw candidate paths. The host may independently display the submitted command.

## Retired Path Guard

`block-secrets.py` and its diagnostic heredoc analyzer were retired on 2026-11-05. The hook no longer restricts filesystem paths or diagnostic interpreter syntax. Registrations and dedicated tests were removed. A no-op entrypoint remains for cached registrations until existing sessions restart.

`redact-secrets.py` was also retired on 2026-11-05. Its registrations and content-guard tests were removed. A no-op entrypoint remains for cached sessions. Tool input is no longer scanned for secret patterns by this hook. The chain and GWT gates remain active.

## Reason Categories

| Hook | Category | Recovery |
|---|---|---|
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

The remaining hooks inspect workflow state. They do not enforce filesystem access restrictions or validate arbitrary shell and Python syntax. The retired path guard no longer blocks unsupported diagnostic syntax.
