---
review:
  plan_hash: d6b074dbb6624289
  last_run: 2026-11-06
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
result_check:
  verdict: OK
  source: plan
  plan_hash: d6b074dbb6624289
  last_run: 2026-11-06
  reviewed: true
  docs_checked: true
chain:
  intent: docs/superpowers/intents/2026-11-06-proxy-security-and-failover-intent.md
  spec: docs/superpowers/specs/2026-11-06-proxy-security-and-failover-design.md
---
# Proxy Security and Failover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Launch through verified HTTPS using an owned stunnel child and select the first working comma-separated proxy candidate.

**Architecture:** Preserve the configured list separately from the selected runtime URL. A focused stunnel module owns the tunnel and Linux installation offer. Existing launch owners compose cleanup and preserve terminal behavior.

**Tech Stack:** Bash, curl, stunnel, Linux native package managers, Python standard-library test fixtures, OpenSSL test certificates.

**Spec:** `docs/superpowers/specs/2026-11-06-proxy-security-and-failover-design.md`

**Intent:** `docs/superpowers/intents/2026-11-06-proxy-security-and-failover-intent.md`

**Status:** approved

## Global Constraints

- Limit automatic package installation to Linux.
- Never downgrade an HTTPS candidate to plaintext transport to the remote proxy.
- Bind the local tunnel listener to loopback only.
- Keep HTTP candidates independent of stunnel availability.
- Select candidates at startup only. Live session migration is outside this change.
- Do not change unrelated settings or discard existing user modifications.
- Keep the existing three-second connection timeout and eight-second total probe deadline.
- Do not put credentials in stunnel configuration, process arguments, or logs.
- Without a TTY or outside Linux, do not attempt automatic installation.
- Preserve `--no-proxy` precedence and existing host-bypass semantics.

The existing `.codex-lockfile.json` modification is outside this task. Do not stage it.
Work on `dev-proxy-security-and-failover`. Execute tasks sequentially in this session.
The commands below specify future checks; none are claimed as completed implementation evidence.

## Files and ownership

| File | Responsibility |
|---|---|
| `lib/proxy/proxy.sh` | List validation, selection, consent, effective route |
| `lib/proxy/stunnel.sh` (new) | Dependency offer, private configuration, owned tunnel lifecycle |
| `icodex.sh` | Source module, select before network work, propagate failure |
| `lib/binary/install.sh` | Download through selected route without credential argv |
| `lib/launcher/launch.sh` | Retain wrapper ownership for HTTPS and preserve TTY/signals |
| `lib/profile/profile.sh` | Compose tunnel cleanup with profile runner lifecycle |
| `tests/test_proxy.sh`, `tests/test_proxy_diagnostics.py` | Existing behavior and changed fallback contract |
| `tests/test_proxy_stunnel.sh` (new) | Deterministic dependency, configuration, cleanup tests |
| `tests/test_proxy_transport.py` (new) | Real TLS/CONNECT and two-candidate fixture |
| `tests/test_proxy_transport.sh` (new) | Include real transport checks in Bash suite |
| `tests/test_install.sh`, `tests/test_pii_proxy_launch.sh`, `tests/test_telemetry_launch.sh` | Affected callers and launch regression coverage |
| `README.md`, `docs/README.ru.md`, `.codex_config.example`, `lib/command/args.sh` | User contract and examples |

## Task 1: Ordered list and explicit fallback

Closes R1 and R2; proves O1, O3, O4, O7, and O8 without requiring TLS initially.
Modify `lib/proxy/proxy.sh`, `tests/test_proxy.sh`, and `tests/test_proxy_diagnostics.py`.

**Interfaces:**
- `proxy_parse_list <list>` populates indexed Bash array `ICODEX_PROXY_CANDIDATES`; returns 0 or 1.
- `proxy_validate <url>` remains the single-candidate validator.
- `proxy_save <file> <list>` validates the whole list before persistence.
- `proxy_prepare_candidate <url>` sets `ICODEX_PROXY_ACTIVE`; returns 0 or 1. HTTPS calls the Task 2 interface when available.
- `_proxy_probe` reads the active URL, retaining single-value compatibility for isolated existing tests.
- `_proxy_probe_target` prints the existing fixed account-check URL. Tests may override this function for a loopback TLS target; do not add a public environment override.
- `proxy_ensure` selects, applies, or refuses launch. It never persists the selected URL.
- `proxy_cleanup` is idempotent and calls `proxy_stunnel_stop` when that helper exists.

- [ ] Step 1: Add failing assertions for parsing, unchanged saved state on invalid input, order, first-success short circuit, and explicit consent.

```bash
proxy_parse_list 'http://first:8080, https://second:443'
assert_eq 'two candidates' '2' "${#ICODEX_PROXY_CANDIDATES[@]}"
assert_exit 'empty candidate rejected' 1 proxy_parse_list 'http://first:8080,'
assert_eq 'empty consent refuses' 'exit' "$(_proxy_unreachable_action 1 '')"
assert_eq 'noninteractive refuses' 'exit' "$(_proxy_unreachable_action 0 '')"
assert_eq 'explicit consent permits' 'continue' "$(_proxy_unreachable_action 1 yes)"
```

Use a probe stub that appends the active URL to a temporary file and succeeds only for the second candidate.
Assert two probes, unchanged original list, and a single selected URL in all four HTTP proxy variables.
Use `%2C` in userinfo and verify its exact preservation. Reject a raw trailing comma and whitespace inside authority.

- [ ] Step 2: Run the focused failing tests. Record the expected behavior failures before implementation.

```bash
bash tests/test_proxy.sh
python3 tests/test_proxy_diagnostics.py
```

- [ ] Step 3: Implement parsing and selection with explicit status handling.

```bash
for candidate in "${ICODEX_PROXY_CANDIDATES[@]}"; do
  if proxy_prepare_candidate "$candidate" && _proxy_probe; then
    proxy_apply
    return 0
  fi
  proxy_cleanup
done
```

After the loop, require a TTY and an explicit case-insensitive `y` or `yes` before `proxy_disable` and success.
Do not interpret empty input or EOF as consent. Return failure to the caller rather than terminating a sourced test shell.
Trim only candidate-edge spaces. Reject control characters before trimming so newlines cannot become list separators.
Keep SOCKS behavior compatible without claiming new Codex support.

- [ ] Step 4: Run syntax and focused tests until all expected assertions pass.

```bash
bash -n lib/proxy/proxy.sh
bash tests/test_proxy.sh
python3 tests/test_proxy_diagnostics.py
```

**DoD:** Ordered two-candidate selection passes, malformed saves preserve prior settings, and no-TTY exhaustion returns nonzero.
Commit only Task 1 paths after review.

## Task 2: Managed stunnel and Linux installation offer

Closes R3 and R4; proves O2, O5, O6, and candidate cleanup in O9.
Create `lib/proxy/stunnel.sh` and `tests/test_proxy_stunnel.sh`.
Connect `proxy_prepare_candidate` to the new module without changing direct HTTP handling.

**Interfaces:**
- `proxy_stunnel_find` prints a compatible executable path or returns 1.
- `proxy_stunnel_require` discovers or offers installation once per invocation; returns 0 or 1.
- `proxy_stunnel_start <https-url>` sets `ICODEX_PROXY_ACTIVE`, `ICODEX_STUNNEL_PID`, and `ICODEX_STUNNEL_DIR`; returns 0 or 1.
- `proxy_stunnel_stop` terminates and reaps only the owned PID, removes its private directory, and clears runtime state.
- `_proxy_stunnel_install_command` populates a command array using the spec's distribution/package table.
- `_proxy_stunnel_ca_file` prints the selected readable CA file or returns 1 without falling through an invalid explicit source.

- [ ] Step 1: Add deterministic executable and package-manager stubs covering every installation-table row and each consent outcome.

```bash
assert_exit 'missing binary and no TTY refuses install' 1 proxy_stunnel_require
assert_eq 'installer not called' '0' "$(wc -l < "$install_calls")"
proxy_stunnel_stop
proxy_stunnel_stop
assert_eq 'cleanup clears PID' '' "${ICODEX_STUNNEL_PID:-}"
```

Run no system package manager in these tests. Use PATH stubs and pseudo-terminal input for affirmative and negative answers.
Check offer-once behavior across two HTTPS candidates, failure followed by HTTP success, and missing sudo.
Check explicit CA conflicts, invalid selected paths, DNS versus IP identity settings, and credential-free generated configuration.

- [ ] Step 2: Run the new test and confirm missing-interface or behavior failures.

```bash
bash tests/test_proxy_stunnel.sh
```

- [ ] Step 3: Implement the fixed package table, once-per-invocation consent, and foreground tunnel.

Use these configuration fields as the DNS-host template; substitute only validated values:

```ini
foreground = yes
syslog = no
pid =
[icodex-proxy]
client = yes
accept = 127.0.0.1:LOCAL_PORT
connect = UPSTREAM_HOST:UPSTREAM_PORT
verifyChain = yes
checkHost = UPSTREAM_HOST
sni = UPSTREAM_HOST
CAfile = SELECTED_CA_FILE
```

The uppercase template tokens above represent values assembled by the implementation, not literal generated configuration.
For literal IPs, use `checkIP` instead of DNS matching/SNI. Reject line breaks in every generated configuration value.
Use `mktemp -d`, umask 077, a random unprivileged port, and at most three bounded bind attempts.
Require a successful bind event for the configured listener from the still-running owned process before probing with credentials.
Capture private startup diagnostics in a controlled locale. Test the actual event against the real stunnel binary in Task 4.
Preserve original percent-encoded userinfo only in the runtime effective URL.
Stop failed candidates immediately; TERM stunnel, wait at most two seconds, then KILL and reap if required.

**HUMAN CHECKPOINT:** Native system installation and privilege elevation require explicit runtime consent. Refusal continues selection.
Use native package-manager routing for this bootstrap transaction; never pass a candidate list as proxy environment.
Do not add repositories, enable services, or change system stunnel configuration.

- [ ] Step 4: Run syntax and deterministic tests. Inspect generated file modes and process cleanup assertions.

```bash
bash -n lib/proxy/stunnel.sh
bash tests/test_proxy_stunnel.sh
bash tests/test_proxy.sh
```

**DoD:** All installation paths are stub-verified; no secret appears in configuration/argv/output; startup and cleanup deadlines are enforced.
Commit only Task 2 paths after review.

## Task 3: Launch ownership and network consumers

Closes R2 and R5, including O9 across ordinary, PII, telemetry, and profile launches.
Modify `icodex.sh`, `lib/binary/install.sh`, `lib/launcher/launch.sh`, and `lib/profile/profile.sh`.
Extend installer and launcher tests listed in the file table. Add profile lifecycle assertions to `tests/test_proxy_stunnel.sh` by sourcing `lib/profile/profile.sh` and stubbing its runner.

**Interfaces:** Consume `proxy_ensure`, `proxy_cleanup`, `ICODEX_PROXY_ACTIVE`, and `ICODEX_STUNNEL_PID` from Tasks 1 and 2.
Use one effective proxy URL for downstream tools; retain the original list only for persistence and diagnostics that do not expose values.

- [ ] Step 1: Add failing launch-order assertions and child-process fixtures.

The fixture records whether selection precedes a stubbed download. The application fixture reads one line from stdin and returns a chosen status.
A second fixture ignores TERM and records its PID. An occupied-listener fixture records any bytes received.
Assert no credential probe reaches the occupied foreign listener.
Assert exit code preservation, INT/TERM handling, later-setup failure cleanup, and profile-dispatch cleanup.

```python
assert selected_at < download_at
assert application_stdin == b"interactive-input\n"
assert launch_returncode == expected_returncode
assert not owned_stunnel_is_alive
assert not runtime_directory.exists()
```

These expressions name observations captured by the fixtures, not production APIs.

- [ ] Step 2: Implement source registration, early selection, and explicit failure propagation.

```bash
if (( ! ICODEX_DISABLE_PROXY )); then
  proxy_ensure || return 1
fi
```

Place selection after local configuration and CA setup but before network downloads for run/install/update flows.
Leave local-only commands free of selection and installation prompts.
Update download helpers to use only the effective URL. Move credential-bearing curl settings to stdin and wget proxy settings to child environment.
Preserve normal inherited-proxy behavior when no list is configured and preserve explicit disable/direct-fallback clearing.

- [ ] Step 3: Compose lifecycle handling rather than overwriting traps.

Retain the parent when a stunnel PID is active. Preserve the existing exec path for HTTP without owned helpers.
Give background interactive children an explicit copy of original stdin; verify using a pseudo-terminal.
Forward INT/TERM, allow five seconds, then TERM and two seconds, then KILL/reap if still owned.
Return the initiating signal status. Always clean up stunnel after application termination or later setup failure.
Integrate with PII, telemetry, and profile handlers. Preserve existing PII PID storage rather than expanding this change into PII concurrency repair.

- [ ] Step 4: Run syntax and affected regression tests.

```bash
bash -n icodex.sh lib/binary/install.sh lib/launcher/launch.sh lib/profile/profile.sh
bash tests/test_install.sh
bash tests/test_pii_proxy_launch.sh
bash tests/test_telemetry_launch.sh
bash tests/test_proxy_stunnel.sh
bash tests/test_proxy.sh
```

The profile lifecycle assertions run through `tests/test_proxy_stunnel.sh`; they must exercise `run_profile_dispatch`, including its existing traps.
**DoD:** Every listed launch mode keeps the tunnel alive until completion and removes it on controlled exits; interactive input and exit codes remain correct.
Commit only Task 3 paths after review.

## Task 4: Real transport acceptance

Closes R3, R5, and R6 with direct outcome evidence rather than stubs.
Create `tests/test_proxy_transport.py` and its Bash suite wrapper `tests/test_proxy_transport.sh`.

**Interfaces:** Use real `proxy_ensure` and `proxy_cleanup` from earlier tasks, real curl/stunnel, and Python standard-library socket/ssl servers.
Fixtures supply a local HTTPS target and HTTP/TLS CONNECT proxies. Override only `_proxy_probe_target`; do not bypass production selection or tunnel configuration.

- [ ] Step 1: Provide disposable CA, valid proxy/target certificates, and wrong-name/untrusted/expired certificate variants.
Generate fixture certificates with OpenSSL; use Python standard-library TLS servers and CONNECT relay threads.
Record ordered connection attempts and the target response marker. Keep all servers bound to loopback.

```python
assert observations["candidate_order"] == [1, 2]
assert observations["target_body"] == b"proxy-transport-ok"
assert observations["effective_scheme"] == "http"
assert observations["upstream_tls_connections"] >= 1
assert observations["plain_remote_attempts"] == 0
```

- [ ] Step 2: Verify real HTTPS alone, failed-first HTTP then HTTPS, and failed-first HTTPS then HTTP.
Verify first-success short circuit, rejected credentials, certificate rejection, and loopback-only listener binding.
Verify two concurrent invocations own separate ports and terminating one leaves the other functional.
Exercise application exit, INT, TERM, ignored TERM, and setup failure; assert no owned process or runtime file remains.

**HUMAN CHECKPOINT:** If real stunnel is absent, do not silently install a system package.
Prefer a distro package extracted into a private test directory without privileges when executable compatibility permits.
Otherwise request explicit installation consent and retain incomplete real-transport evidence until available.
Do not claim real HTTPS coverage from stub success or a skipped integration test.

- [ ] Step 3: Run integration checks and capture sanitized outcomes.

```bash
python3 tests/test_proxy_transport.py
bash tests/test_proxy_transport.sh
```

The Bash wrapper may report a clear unavailable-dependency skip in generic environments, but completion for this task requires a recorded real-binary pass.
**DoD:** Target marker crosses real upstream TLS, second-candidate fallback works, invalid certificates fail, and lifecycle checks pass.
Commit only Task 4 paths after review.

## Task 5: Documentation, specifications, and final verification

Closes R6 and all remaining acceptance obligations.
Update README.md, docs/README.ru.md, .codex_config.example, CLI help, and the wiki proxy handling section.

- [ ] Step 1: Document comma-separated syntax, `%2C`, per-invocation stunnel, installation support, explicit fallback consent, and startup-only selection.

```bash
./icodex.sh --proxy 'https://proxy-one.example:443,http://proxy-two.example:8080'
```

Use credential-free examples. Explain that system package routing is independent of application proxy selection.
Explain no-TTY refusal, certificate verification, finite probes, and the difference between probe success and ongoing model connectivity.

- [ ] Step 2: Update GWT scenarios through iwiki MCP after reading existing scenario context.
Preserve the authentication-failure ID when its existing contract remains unchanged.
Add ordered-selection, managed-HTTPS, installation-consent, and explicit-fallback scenarios with implementation/test file selectors.
Resolve against a fresh graph when available. Otherwise record `graph_unavailable`, preserve declared selectors, and use executable evidence.
Update ordinary wiki documentation before final result. Run wiki lint and address new task-specific findings.

- [ ] Step 3: Run syntax, focused checks invalidated by final edits, then the full Bash suite once for the stable state.

```bash
git diff --check
bash -n icodex.sh lib/proxy/proxy.sh lib/proxy/stunnel.sh lib/launcher/launch.sh lib/profile/profile.sh lib/binary/install.sh lib/command/args.sh
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Do not repeat a matching full-suite pass for documentation or ledger updates.
Record every command, scope, exit status, revision, and relevant working-tree fingerprint in the ledger.

- [ ] Step 4: Review the diff for credential leakage, child ownership, consent, TLS downgrade, and unrelated modifications.
Reconcile O1 through O9 and R1 through R6 against actual evidence. Run `check-chain result` against this plan.
Do not mark the goal complete until real HTTPS and two-candidate evidence exists and all required checks and documentation are complete.

**DoD:** Result reconciliation is OK, wiki evidence is delivered, no required outcome is missing, and the user's original objective is proven.
Commit scoped final changes after review. Do not commit the unrelated lockfile change or push directly to master.

## Coverage and execution order

| Requirement | Tasks | Required evidence |
|---|---|---|
| R1 / O1 / O3 | 1, 3, 5 | URL/list compatibility, invalid-save preservation, help examples |
| R2 / O4 / O7 / O8 | 1, 3, 4 | Ordered probes, second-candidate request, explicit consent/no-TTY refusal |
| R3 / O2 | 2, 4 | Real stunnel TLS, identity rejection, occupied-listener rejection |
| R4 / O5 / O6 | 2, 4 | Stub package transactions, one offer, refusal and failure continuation |
| R5 / O9 | 2, 3, 4 | Exit/signal/setup cleanup, TTY behavior, concurrent isolation |
| R6 / health metrics | 1–5 | Sanitized diagnostics, focused/regression evidence, complete docs |

Dependencies are sequential: Task 1 → Task 2 → Task 3 → Task 4 → Task 5.
Expected results above are acceptance criteria, not claims of completed implementation.
