---
review:
  spec_hash: f96e8bd7a95a9449
  last_run: 2026-11-06
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-11-06-proxy-security-and-failover-intent.md
---
# Design: proxy-security-and-failover

**Date:** 2026-11-06
**Status:** approved

## Purpose and scope

Use one owned stunnel child per icodex invocation that selects an HTTPS proxy.
Select the first working proxy from a comma-separated list at startup.
Install missing stunnel only on Linux and only after explicit consent.
Require explicit consent before direct fallback.

The user approved this process model. A system service needs shared lifecycle management.
An external gateway introduces an unnecessary deployment dependency. Neither alternative is selected.
Live failover, proxy balancing, remote server provisioning, and automatic macOS installation are outside scope.

## Acceptance (from intent)

- O1: An HTTP proxy works without starting stunnel.
- O2: An HTTPS proxy works through an icodex-managed local stunnel process, with upstream certificate and identity verification.
- O3: Both `--proxy` and `ICODEX_PROXY` accept comma-separated proxy URLs in priority order. A single URL remains valid.
- O4: Launch uses the first candidate whose actual route passes proxy authentication, CONNECT, and an HTTPS target probe.
- O5: If stunnel is missing on Linux, the user receives one installation offer per invocation before the first HTTPS attempt.
- O6: Accepted installation enables HTTPS attempts. Refusal, installation failure, or unavailable installation support skips HTTPS candidates that require the missing dependency.
- O7: After all candidates fail, the user chooses whether to launch without a proxy. Only explicit affirmative input permits direct fallback.
- O8: Without an interactive terminal, installation is not attempted. Exhausted candidates stop launch rather than silently connecting directly.
- O9: Rejected candidate tunnels are stopped. The selected tunnel remains available during the Codex session and is cleaned up on normal exit or handled termination.

- Done when: controlled HTTP, HTTPS, mixed-priority, failed-authentication, rejected-certificate, installation-consent, all-failed, and non-interactive scenarios produce O1 through O9 outcomes.
- Done when: a real local TLS proxy fixture carries a request through the managed tunnel and rejects an untrusted or mismatched certificate.
- Done when: focused and regression evidence passes, required documentation and wiki updates are delivered, and result reconciliation reports no missing outcome.

## Current behavior and integration boundaries

`lib/proxy/proxy.sh` validates one URL, probes through curl, and exports proxy environment variables.
`icodex.sh` currently installs dependencies before calling `proxy_ensure`.
`lib/binary/install.sh` passes `ICODEX_PROXY` directly to curl and wget.
`lib/launcher/launch.sh` supports direct exec, PII proxy launches, and telemetry-supervised launches.
Direct exec loses wrapper cleanup ownership. Existing PII traps can overwrite other cleanup handlers.
Profile dispatch also needs the selected route until its runner exits.

The graph snapshot is stale. These boundaries were inspected in repository source.
The README and wiki describe current behavior. Implementation will update them after this design is approved.

## Configuration contract

R1 covers O1 and O3.

1. Accept a single URL or comma-separated URLs through existing `--proxy` and `ICODEX_PROXY` inputs.
2. Trim spaces around each candidate. Preserve URL credentials and percent encoding.
3. Reject empty candidates, control characters, embedded whitespace, unsupported schemes, and invalid authorities before saving CLI settings.
4. Treat literal commas as separators. Require `%2C` for commas inside credentials.
5. Preserve the existing supported schemes. Default schemeless candidates to HTTP.
6. Validate the complete list before network checks. Do not overwrite saved configuration after validation failure.
7. Preserve the original list in persistent settings. Keep the selected effective URL in runtime state only.
8. Preserve `--no-proxy` precedence and existing host-bypass semantics.

Existing SOCKS schemes remain accepted and use their existing probe path. This change does not promise new Codex SOCKS compatibility.
List parsing must not silently discard malformed entries or trailing delimiters.

## Sequential selection and launch ordering

R2 covers O4, O7, and O8.

1. Resolve CLI overrides and validate the list after local CA setup.
2. Select a route before wrapper network downloads, including install and update commands.
3. Skip route selection for local-only help, version, clear, and status commands.
4. For each candidate, construct its effective transport and run the existing authenticated HTTPS probe.
5. For HTTP, use the original candidate directly. For HTTPS, use its local stunnel endpoint.
6. For SOCKS, retain the existing SOCKS probe semantics without requiring an HTTP CONNECT status.
7. Keep the existing three-second connection timeout and eight-second total probe deadline.
8. Require CONNECT success for HTTP-family candidates and target HTTP 2xx or expected unauthenticated 401.
9. On failure, release candidate resources before trying the next candidate.
10. On success, export one selected route and stop checking candidates.
11. If all candidates fail, prompt once with default No. Accept only explicit `y` or `yes`, ignoring case.
12. On refusal, empty input, EOF, or no TTY, stop with a nonzero status.
13. On affirmative consent, clear inherited proxy routing variables and proceed directly.

No account token is sent by the probe. Probes ignore bypass lists; launched clients retain configured bypass semantics.
Never pass the complete list as one proxy URL to curl, wget, Codex, or a package manager.
Explicitly propagate a failed selection from `main`; do not rely on incidental `set -e` behavior.
Without a configured proxy list, preserve existing launch behavior.

## HTTPS transport

R3 covers O2, O4, and O9.

Use a new focused `lib/proxy/stunnel.sh` module for dependency detection, configuration, startup, and cleanup.
Keep list parsing and selection in `lib/proxy/proxy.sh`.

- Locate `stunnel` or `stunnel4` using executable discovery.
- Start stunnel in foreground mode as the current user. Retain the child PID in this invocation.
- Use a private temporary directory with mode 0700 and configuration files with mode 0600.
- Bind the local listener to `127.0.0.1` on an unprivileged port.
- Use a bounded allocation attempt and retry at most three times after a bind collision.
- Require the owned foreground child to remain alive and emit its successful bind event into its private startup log.
- Match that event to this invocation's configured loopback address and port before sending credentials.
- Use a controlled locale and verify the event format against the supported stunnel binary in the real fixture.
- Treat an absent or unrecognized bind event as readiness failure. An arbitrary listening port is not proof of ownership.
- Limit each startup attempt to three seconds. Fail the candidate if the child exits or readiness times out.
- Configure the upstream host and port from validated URL components.
- Enable `verifyChain`. Use `checkHost` and SNI for DNS names. Use `checkIP` for literal IP addresses.
- Select the first configured CA source in this order: `ICODEX_CA_BUNDLE`, `SSL_CERT_FILE`, `CURL_CA_BUNDLE`, then `_ca_default_bundle`.
- Honor the filtered CA bundle exported by `ensure_ca_trust` through those environment variables.
- Reject an invalid explicit CA path rather than silently changing its trust source.
- Reject startup if the installed stunnel cannot enforce required verification options.
- Never replace an HTTPS candidate with a remote plaintext connection.

Construct the effective URL as `http://<original-userinfo>@127.0.0.1:<port>`, omitting userinfo when absent.
Keep original userinfo byte-for-byte for proxy authentication. stunnel carries raw CONNECT bytes inside upstream TLS.
Do not configure stunnel's HTTP CONNECT protocol handler; the local client already performs CONNECT.
Do not put credentials in stunnel configuration, process arguments, or logs.

Use credential-safe probe input through curl configuration on stdin.
Pass selected downloader credentials through protected input or environment rather than command arguments.
Disable system logging for this owned process. Keep only private operational diagnostics and remove them during cleanup.

Technical reference: https://www.stunnel.org/manual.html (foreground, accept, connect, CAfile, verifyChain, checkHost, checkIP, SNI).

## Missing dependency and installation

R4 covers O5, O6, and O8.

Offer installation only when an HTTPS candidate first needs a missing executable.
Do not ask when HTTP succeeds before any HTTPS attempt.
Remember refusal or attempted installation for this invocation; never prompt repeatedly for later HTTPS candidates.

Detect Linux distribution identity before choosing a package manager. Use a fixed command table; do not evaluate user-provided commands.

| Linux family | Manager | Package |
|---|---|---|
| Debian and Ubuntu | apt-get | stunnel4 |
| ALT Linux | apt-get | stunnel |
| Fedora and RHEL derivatives with dnf | dnf | stunnel |
| Arch Linux | pacman | stunnel |
| openSUSE | zypper | stunnel |
| Alpine | apk | stunnel |

This is the initial installation command mapping, not a guarantee that every release has the package in its enabled repositories.
A missing package is an installation failure; never add a repository to compensate.
An unsupported distribution or missing manager leaves HTTPS candidates unavailable and reports manual installation guidance.
A preinstalled compatible executable does not require this installation table.

Show the package, manager, and need for administrator privileges before requesting consent.
Use the current user when root; otherwise request sudo only after affirmative consent.
Use native package installation. Do not add repositories, execute downloaded installers, upgrade unrelated packages, or change a system stunnel configuration.
Run the application tunnel as the original user after installation. Do not enable a system stunnel service.
Package maintainer behavior remains part of the native package transaction and must be explained in the prompt.

Package installation uses the host package manager's configured repository route. It does not inherit an unselected comma-separated list.
This is a bootstrap boundary: an HTTPS-only network may require stunnel to be installed manually beforehand.
Consent authorizes that package transaction only, not direct application fallback.
After installation, rediscover the executable. If installation fails or yields no compatible executable, continue candidate selection.
Without a TTY or outside Linux, do not attempt automatic installation.

## Resource ownership and launcher behavior

R5 covers O9 and the process health metrics.

Register idempotent cleanup immediately after acquiring owned resources.
Integrate cleanup with existing PII, telemetry, and `lib/profile/profile.sh` lifecycle handlers.
Do not replace traps without composing their actions.

| Launch case | Required ownership |
|---|---|
| HTTP without owned helpers | Preserve existing exec path |
| Selected HTTPS | Retain parent until Codex or profile runner exits |
| HTTPS with PII or telemetry | Share one cleanup path for all invocation-owned resources |
| Failed setup after tunnel selection | Stop tunnel before returning failure |
| Install/update command | Keep tunnel until command completion, then clean up |

Preserve terminal input, output, and exit status. A supervised interactive child must retain its intended stdin.
Forward INT and TERM to the managed application child. Allow five seconds for termination, then send TERM if needed.
After two more seconds, send KILL to the still-owned child, reap it, and clean up the tunnel.
Test a child that ignores TERM. Preserve the initiating signal status even when escalation is needed.
Retain existing signal status conventions, including 130 and 143.
Allow the owned stunnel child two seconds after TERM, then KILL and reap it if still running.
For stunnel, never stop processes discovered by executable name or shared PID files.
Existing PII PID storage remains outside this change. Preserve its current behavior while composing cleanup; do not claim new PII concurrency guarantees.
Use per-invocation directories and PIDs so concurrent launches cannot stop each other's tunnels.
Do not promise cleanup after SIGKILL or host failure.
A tunnel failure during a session must not cause automatic direct fallback or selection of another candidate.

## Diagnostics and security boundaries

R6 covers all health metrics and preserves the original security objective.

Report candidate index and protocol, failure stage, selection, installation outcome, and direct-fallback decision.
Do not print complete proxy URLs, passwords, or generated credential-bearing environment values.
A successful probe proves the selected route at that instant, not all future Codex connections.
The TLS tunnel protects the remote client-to-proxy hop. Loopback transport remains plaintext on the same host.
Do not claim isolation from other processes running as the same user or a privileged local attacker.

## Verification and requirement coverage

Use local HTTP CONNECT and TLS-wrapped CONNECT fixtures with disposable certificates.
Drive the real stunnel binary for transport acceptance. Stubs alone cannot prove R3.
Use stub package managers for installation consent tests; tests must not install packages or request administrator privileges.
Use a pseudo-terminal for consent and interactive signal checks.

| Check | Expected observation | Coverage |
|---|---|---|
| Single HTTP | Selected without any stunnel process | O1, R1 |
| Single HTTPS | Request crosses a real owned TLS tunnel | O2, R3 |
| Two comma-separated URLs, first unavailable | Second selected; target receives request | O3, O4, R1, R2 |
| First working, second trap endpoint | Second endpoint receives no probe | O4, R2 |
| Rejected credentials | Next candidate tried; secrets absent from output | O4, R6 |
| Untrusted, expired, or wrong-identity certificate | HTTPS candidate rejected; no plaintext downgrade | O2, R3 |
| Missing stunnel, accept installation | One offer; rediscovery; HTTPS attempted | O5, O6, R4 |
| Missing stunnel, refuse or installation fails | HTTP candidate still works; no repeated offer | O6, R4 |
| All fail, affirmative consent | Direct launch with inherited proxy variables cleared | O7, R2 |
| All fail, No, empty input, EOF, or no TTY | No application launch | O7, O8, R2 |
| Normal exit, INT, TERM, failed later setup | Owned tunnel and files removed; exit semantics preserved | O9, R5 |
| Two concurrent invocations without PII | Independent stunnel listener ports and cleanup | O9, R5 |
| Occupied chosen port | Owned bind failure; no credential probe to foreign listener | R3 |
| Conflicting CA overrides | Declared precedence; selected invalid path fails closed | R3 |
| Download, update, PII, telemetry, profile dispatch | One effective URL; correct resource lifetime | R2, R5 |
| Malformed list and encoded comma | Invalid save refused; encoded credentials preserved | O3, R1 |
| Existing bypass and disable cases | Existing explicit bypass behavior preserved | R1 |

Run syntax checks and focused tests during implementation.
Run relevant launcher, installer, proxy, PII, and telemetry regressions, then the full Bash suite once on the final stable state.
Record command, exit code, and code-state fingerprint in the task ledger.
If no real stunnel binary is available in the verification environment, retain incomplete outcome evidence rather than reporting a stubbed transport as verified.

## Specification and documentation maintenance

Preserve the existing authentication-failure scenario ID when extending its executable coverage.
Its reported contract already includes credential-safe failure and clearing inherited variables on direct fallback.
Add scenarios for ordered selection, managed HTTPS transport, installation consent, and explicit fallback consent.
Read scenario context before modifications and keep declared selectors when the graph is unavailable.
Publish scenario bindings with executable implementation and test evidence during implementation; do not invent resolved symbol IDs now.

Update README.md, docs/README.ru.md, .codex_config.example, CLI help, and the wiki proxy handling section after implementation.
Explain the new list syntax, installation table, first-success selection, TLS verification, and changed default-No fallback.
Current documentation remains valid for the current runtime until implementation lands.

## Approval and completion boundaries

This document specifies future behavior; no runtime change is claimed.
The user has selected per-invocation child ownership and requested completion with real HTTPS and two-candidate verification.
The checked specification approval gate precedes the implementation plan stage.
At runtime, installation consent and direct-fallback consent remain separate human decisions.
Implementation completion requires the approved intent outcomes and result reconciliation, not specification approval alone.
