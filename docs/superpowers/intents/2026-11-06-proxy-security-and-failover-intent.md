---
review:
  intent_hash: 0f40ec6858fe12ac
  last_run: 2026-11-06
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
workflow:
  route: chain
  continuation: full
---
# Intent: proxy-security-and-failover

**Date:** 2026-11-06
**Status:** approved

## Objective

Protect the client-to-proxy connection without requiring users to run a tunnel separately.
Allow users to configure ordered proxy candidates and retain control over direct fallback.

## Desired Outcomes

- O1: An HTTP proxy works without starting stunnel.
- O2: An HTTPS proxy works through an icodex-managed local stunnel process, with upstream certificate and identity verification.
- O3: Both `--proxy` and `ICODEX_PROXY` accept comma-separated proxy URLs in priority order. A single URL remains valid.
- O4: Launch uses the first candidate whose actual route passes proxy authentication, CONNECT, and an HTTPS target probe.
- O5: If stunnel is missing on Linux, the user receives one installation offer per invocation before the first HTTPS attempt.
- O6: Accepted installation enables HTTPS attempts. Refusal, installation failure, or unavailable installation support skips HTTPS candidates that require the missing dependency.
- O7: After all candidates fail, the user chooses whether to launch without a proxy. Only explicit affirmative input permits direct fallback.
- O8: Without an interactive terminal, installation is not attempted. Exhausted candidates stop launch rather than silently connecting directly.
- O9: Rejected candidate tunnels are stopped. The selected tunnel remains available during the Codex session and is cleaned up on normal exit or handled termination.

## Health Metrics

- Existing single-HTTP-proxy, authentication, `--no-proxy`, and host-bypass regression cases continue to pass.
- TLS verification failures never select an HTTPS candidate.
- Diagnostics and installation prompts contain no proxy passwords or complete credential-bearing URLs.
- Controlled exit and termination checks leave no owned stunnel process or private runtime files behind.
- Every candidate probe has a finite deadline. Preserve the existing eight-second probe deadline unless approved design evidence requires a change.
- The final stable implementation passes focused tests and the full repository suite once for that code state.

## Strategic Context

- Interacts with: Bash argument parsing, persisted wrapper configuration, proxy probes, launcher process ownership, Linux package management, Codex HTTP and WebSocket clients.
- Priority trade-off: trust before speed. Explicit fallback consent and verified TLS take priority over unattended launch convenience.
- Existing documentation records HTTPS WebSocket limitations in Codex 0.166.0. A local HTTP endpoint hides the upstream TLS transport from Codex.
- Existing automatic direct fallback is intentionally replaced when configured candidates are exhausted.

## Constraints

### Steering (behavioral guidance)

- Keep selection sequential and preserve user-specified order.
- Reuse existing configuration and diagnostics where their contracts remain applicable.
- Explain installation refusal, unavailable package support, and candidate failure without exposing credentials.

### Hard (architectural enforcement)

- Limit automatic package installation to Linux.
- Obtain explicit runtime consent before installing a system package or requesting installation privileges.
- Never disable certificate-chain or upstream identity verification.
- Bind the local tunnel listener to loopback only.
- Never downgrade an HTTPS candidate to plaintext transport to the remote proxy.
- Keep HTTP candidates independent of stunnel availability.
- Never install packages or permit direct fallback on empty input, EOF, or absent interactive input.
- Select candidates at startup only. Live session migration is outside this change.
- Do not change unrelated settings or discard existing user modifications.

## Autonomy Zones

- Full autonomy (reversible, low risk): focused implementation, test fixtures, relevant documentation, and diagnostics within the approved contract.
- Guarded (record evidence): process ownership, tunnel cleanup, list parsing, credential handling, and TLS verification changes require focused failure-path evidence.
- Proposal-first (needs approval): new configuration contracts beyond the comma-separated list, changed acceptance criteria, and unresolved security or launcher architecture decisions.
- No autonomy (human only): consent to system package installation and consent to launch directly after proxy exhaustion. These are runtime user decisions.

## Stop Rules

- Halt if: the selected route cannot verify upstream TLS identity or would expose a non-loopback listener.
- Escalate if: launcher ownership prevents reliable cleanup or package installation requires a mechanism outside the approved Linux scope.
- Done when: controlled HTTP, HTTPS, mixed-priority, failed-authentication, rejected-certificate, installation-consent, all-failed, and non-interactive scenarios produce O1 through O9 outcomes.
- Done when: a real local TLS proxy fixture carries a request through the managed tunnel and rejects an untrusted or mismatched certificate.
- Done when: focused and regression evidence passes, required documentation and wiki updates are delivered, and result reconciliation reports no missing outcome.
