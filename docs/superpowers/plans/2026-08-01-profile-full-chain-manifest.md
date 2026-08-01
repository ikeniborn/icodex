---
chain:
  intent: docs/superpowers/intents/2026-08-01-profile-full-chain-manifest-intent.md
  spec: docs/superpowers/specs/2026-08-01-profile-full-chain-manifest-design.md
review:
  plan_hash: 5ce5954794725d4e
  last_run: 2026-08-01
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
---

# Profile Full-Chain Manifest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate deterministic, complete profile manifests for approved direct and full workflows.

**Architecture:** Add one strict, dependency-free manifest helper under `lib/profile/` to own templates and atomic writes. The direct-topic hook and chain instructions invoke that helper; runner task sequencing remains the ordered `tasks` array it already reads.

**Tech Stack:** Python 3 standard library, Bash test harness, existing strict profile policy parser.

---

### Task 1: Add strict manifest helper and focused tests

**Closes:** Spec Sections 3, 4, and 6; deterministic templates, idempotence, and fail-closed writes.

**Files:**

- Create: `lib/profile/manifest.py`
- Create: `tests/test_profile_manifest.sh`

- [ ] **Step 1: Write failing helper tests for bootstrap and expansion.**

Create a temporary project and shared registry fixture. Assert `bootstrap` writes exactly
one `intent-profile-selection` task, `expand --route direct` appends `direct-work`, and
`expand --route full` produces this ordered list:

```bash
assert_eq "full task order" \
  $'intent-profile-selection\nspec-design\nplan-writing\nimplementation\nresult-reconciliation' \
  "$(task_ids "$manifest")"
assert_contains "spec uses synthesis" "$(task_profiles "$manifest" spec-design)" "synthesis"
assert_contains "implementation uses engineering" "$(task_profiles "$manifest" implementation)" "engineering"
```

- [ ] **Step 2: Run the focused test to prove it fails.**

Run:

```bash
bash tests/test_profile_manifest.sh
```

Expected: non-zero because `lib/profile/manifest.py` does not exist.

- [ ] **Step 3: Implement `lib/profile/manifest.py`.**

Define fixed task templates and use `policy.parse_yaml_subset` plus the existing strict
policy validation helpers for input parsing. Expose these CLI forms:

```text
python3 lib/profile/manifest.py bootstrap --project-root <root> --registry <path> --topic <slug> --intent <repo-relative-path> --status draft|approved
python3 lib/profile/manifest.py expand --project-root <root> --registry <path> --topic <slug> --route direct|full
```

Implement canonical templates with the existing requirements shape:

```python
TASK_ROUTES = {
    "direct": (("direct-work", "engineering"),),
    "full": (
        ("intent-profile-selection", "engineering"),
        ("spec-design", "synthesis"),
        ("plan-writing", "synthesis"),
        ("implementation", "engineering"),
        ("result-reconciliation", "engineering"),
    ),
}
```

Use one requirements factory with `strong/medium/medium/medium/medium`,
`live_remaining_context: false`, and a one-item `preferred_profiles` list. Validate
topic, manifest location, registry bytes, route, task uniqueness, and matching existing
canonical task contents before writing. Serialize only the project YAML subset and atomically
replace a changed manifest with mode `0644`; leave it untouched on any error. `bootstrap`
requires `--status draft|approved`, so the chain caller explicitly selects draft and the
direct hook explicitly selects approved.

- [ ] **Step 4: Extend tests for idempotence and rejection.**

Run expansion twice and assert a byte-identical SHA-256. Create a manifest containing
`implementation` with profile `deep`, then assert full expansion fails and its SHA-256
does not change. Add assertions for invalid route, non-kebab topic, missing registry,
and malformed manifest.

- [ ] **Step 5: Run helper test to verify it passes.**

Run:

```bash
bash tests/test_profile_manifest.sh
```

Expected: `FAIL=0`.

- [ ] **Step 6: Commit the helper task.**

```bash
git add lib/profile/manifest.py tests/test_profile_manifest.sh
git commit -m "feat(profile): expand workflow manifests"
```

### Task 2: Route direct topics through the shared helper

**Closes:** Spec Sections 4 and 5; direct manifest completeness without App Server orchestration.

**Files:**

- Modify: `.codex-isolated/hooks/direct-topic.py`
- Modify: `tests/test_direct_topic_hook.sh`

- [ ] **Step 1: Write a failing hook assertion.**

After the existing `@topic` fixture call, assert the profile has `direct-work` and no
full-chain-only task:

```bash
assert_contains "direct topic writes direct task" \
  "$(cat "$project/docs/profiles/direct-hook-test.yaml")" "id: direct-work"
assert_eq "direct topic excludes full implementation" "0" \
  "$(grep -c 'id: implementation' "$project/docs/profiles/direct-hook-test.yaml")"
```

- [ ] **Step 2: Run the hook test to prove it fails.**

Run:

```bash
bash tests/test_direct_topic_hook.sh
```

Expected: failure because the hook still writes its local single-task template.

- [ ] **Step 3: Replace local YAML generation with helper invocation.**

Keep `_registry_profile` for model/effort selection. Replace `_profile_text` and direct
atomic profile creation with a subprocess invocation using an absolute `ICODEX_ROOT`
path and an argument list, never a shell command:

```python
subprocess.run(
    [sys.executable, str(root / "lib/profile/manifest.py"), "expand", ...],
    check=True, text=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
)
```

For a missing topic manifest, invoke `bootstrap` first with `docs/profiles/README.md`
as context input, set approved status through the helper's explicit status option, then
invoke `expand --route direct`. Preserve local session mapping, model mismatch denial,
and hook output text. Convert helper errors to the current actionable block response.

- [ ] **Step 4: Run focused hook and helper tests.**

Run:

```bash
bash tests/test_direct_topic_hook.sh
bash tests/test_profile_manifest.sh
```

Expected: both report `FAIL=0`; existing direct model mismatch still denies protected work.

- [ ] **Step 5: Commit the direct route integration.**

```bash
git add .codex-isolated/hooks/direct-topic.py tests/test_direct_topic_hook.sh
git commit -m "feat(profile): expand direct topic manifest"
```

### Task 3: Expand full manifests after continuation selection

**Closes:** Spec Sections 4 and 5; approved full chain has every canonical task before spec/plan work.

**Files:**

- Modify: `.codex-isolated/skills/fix-intent/SKILL.md`
- Modify: `tests/test_idd_skills.sh`
- Modify: `tests/test_workflow_boundaries.sh`

- [ ] **Step 1: Add failing documentation-contract assertions.**

Assert the IDD instructions name `expand --route full`, the five canonical full task IDs,
and direct route expansion. Assert workflow-boundary guidance still says direct does not
enter full App Server orchestration.

- [ ] **Step 2: Run skill and boundary tests to prove failure.**

Run:

```bash
bash tests/test_idd_skills.sh
bash tests/test_workflow_boundaries.sh
```

Expected: new assertions fail until lifecycle instructions are updated.

- [ ] **Step 3: Update `fix-intent` lifecycle instructions.**

Replace inline YAML bootstrap ownership with the helper command from Task 1. Keep the
draft bootstrap before intent validation. In the approved-continuation section, instruct
the operator to invoke full expansion only after `workflow.continuation: full` is
recorded; execute continues without spec/plan tasks. State that the helper must not add
future context paths until their files exist.

- [ ] **Step 4: Run focused lifecycle tests.**

Run:

```bash
bash tests/test_idd_skills.sh
bash tests/test_workflow_boundaries.sh
```

Expected: `FAIL=0`, including existing execute/full continuation checks.

- [ ] **Step 5: Commit lifecycle policy changes.**

```bash
git add .codex-isolated/skills/fix-intent/SKILL.md tests/test_idd_skills.sh tests/test_workflow_boundaries.sh
git commit -m "docs(profile): expand full chain manifests"
```

### Task 4: Prove runner orchestration preserves manifest order

**Closes:** Spec Sections 5 and 7; full workflow requires no runner sequencing change.

**Files:**

- Modify: `tests/test_profile_runner.sh`

- [ ] **Step 1: Add a failing expanded-manifest fixture.**

Extend the fixture manifest builder to accept an ordered task list. Construct the five
full IDs from Task 1, drive the fake App Server with five `complete` transitions, and
assert the recorded `turn/start` requests name those task IDs in exact YAML order.

- [ ] **Step 2: Run the runner test to prove the fixture exposes missing coverage.**

Run:

```bash
bash tests/test_profile_runner.sh
```

Expected: the new assertion fails before the fixture supports an ordered task list.

- [ ] **Step 3: Implement the fixture-only generalization.**

Keep production `lib/profile/runner.py` unchanged. Make the test manifest builder emit
one complete valid task mapping per supplied `(task_id, profile)` tuple, and make the
record parser extract task names from the existing prompt text:

```python
"Execute routed task <task-id> for topic demo."
```

- [ ] **Step 4: Run runner and manifest tests.**

Run:

```bash
bash tests/test_profile_runner.sh
bash tests/test_profile_manifest.sh
```

Expected: both report `FAIL=0`; runner executes all full tasks in declaration order.

- [ ] **Step 5: Commit runner coverage.**

```bash
git add tests/test_profile_runner.sh
git commit -m "test(profile): cover full manifest order"
```

### Task 5: Update user documentation and verify the complete change

**Closes:** Spec Section 7 and all intent Health Metrics.

**Files:**

- Modify: `docs/profiles/README.md`
- Modify: `docs/README.ru.md`
- Modify: `docs/profiles/profile-full-chain-manifest.yaml`
- Modify: `docs/superpowers/specs/2026-08-01-profile-full-chain-manifest-design.md`
- Modify: `docs/superpowers/plans/2026-08-01-profile-full-chain-manifest.md`
- Modify: `docs/TODO.md`

- [ ] **Step 1: Document post-selection expansion.**

Explain that bootstrap is intentionally one task while draft, direct adds only
`direct-work`, and an approved full continuation expands to all five fixed task IDs.
Explain that profile requirements are reviewed manifest policy and no future context
artifact is referenced before it is tracked.

- [ ] **Step 2: Run focused regression checks.**

Run:

```bash
bash tests/test_profile_manifest.sh
bash tests/test_direct_topic_hook.sh
bash tests/test_idd_skills.sh
bash tests/test_workflow_boundaries.sh
bash tests/test_profile_runner.sh
bash tests/test_profile_policy.sh
```

Expected: every command exits 0 and reports `FAIL=0`.

- [ ] **Step 3: Run the full Bash suite and whitespace validation.**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
git diff --check
```

Expected: suite exits 0; whitespace validation is silent.

- [ ] **Step 4: Reconcile docs and update chain artifacts.**

Update the spec and this plan only if implementation decisions differ from their approved
text. Run `$check-chain result` against this plan after all verification; it must map the
helper, callers, tests, and docs to every plan task before the task-log row can close.

- [ ] **Step 5: Commit documentation and result metadata.**

```bash
git add docs/profiles/README.md docs/README.ru.md docs/profiles/profile-full-chain-manifest.yaml docs/superpowers/specs/2026-08-01-profile-full-chain-manifest-design.md docs/superpowers/plans/2026-08-01-profile-full-chain-manifest.md docs/TODO.md
git commit -m "docs(profile): document workflow manifest expansion"
```
