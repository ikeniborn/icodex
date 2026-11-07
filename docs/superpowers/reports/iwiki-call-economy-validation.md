# iwiki call economy validation

## Scope

Reduce repeated iwiki calls while preserving durable project evidence. Restore an explicit execution strategy before implementation. Recommend direct and chain routes; preserve existing explicitly requested LoEn workflows.

## Independent behavioral test

Two isolated agent contexts evaluated the same fixture before and after the instruction changes. This is an instruction simulation, not a live MCP end-to-end test.

Fixture: an existing task has a verified hosted session, unchanged scope and policy, and previously retrieved knowledge. The user requests a supplied-text explanation, resumes a one-line prose correction, and closes the task.

The baseline found conflicting startup requirements and no general implementation-executor choice. The updated instructions passed: the explanation needs no wiki calls; continuation reuses binding and knowledge; writes retain fresh revision checks; closure retains evidence, empty-spool and lint gates.

Negative scenarios passed: reconnect, defaulted binding, changed configuration, CAS conflicts, pending spool, new project conclusions, and code graph maintenance. The chain/full execution choice remains gated by the approved checked plan.

## Focused checks

All commands exited with status 0 after the changes.

| Check | Assertions passed |
|---|---:|
| `bash tests/test_iwiki_call_economy.sh` | 19 |
| `bash tests/test_iwiki_agent_contract.sh` | 161 |
| `bash tests/test_workflow_boundaries.sh` | 111 |
| `bash tests/test_task_ledger.sh` | 87 |
| `bash tests/test_iwiki_remote_scope.sh` | 50 |

The new economy check failed with 13 expected assertions before implementation. Bash syntax and whitespace checks passed. Final integration evidence is recorded in the iwiki task `reference/tasks/iwiki-call-economy`.
