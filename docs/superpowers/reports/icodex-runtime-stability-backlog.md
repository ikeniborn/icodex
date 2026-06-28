# icodex Runtime Stability Backlog

Date: 2026-06-28

This backlog captures known wrapper gaps that affect stable Codex operation,
especially when `icodex` is launched from repositories other than this wrapper
repository. Scores are intended for prioritization, not precision.

## Scoring

Scale:

- Criticality: 1 low impact, 5 severe data/security/availability impact.
- Functionality: 1 narrow convenience, 5 blocks core daily usage.
- Likelihood: 1 rare, 5 common in normal usage.
- Complexity: 1 easy, 5 difficult.

Priority score:

```text
score = ((criticality * 0.4) + (functionality * 0.3) + (likelihood * 0.2) + ((6 - complexity) * 0.1)) * 2
```

## Decision Table

| Rank | Gap | Criticality | Functionality | Likelihood | Complexity | Score | Priority |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | Runtime filesystem isolation is not strict when the active config uses `danger-full-access`. | 5 | 4 | 4 | 3 | 8.8 | P0 |
| 2 | All target projects share one wrapper-level `CODEX_HOME`, so state, sessions, memories, auth, and plugin cache are cross-project. | 4 | 5 | 5 | 3 | 8.6 | P0 |
| 3 | No preflight check validates auth, selected model availability, provider endpoint, or quota before launch. | 4 | 5 | 4 | 2 | 8.6 | P0 |
| 4 | No lock protects concurrent launches, updates, binary replacement, config rewrites, or persisted proxy/uv writes. | 4 | 3 | 4 | 2 | 7.8 | P1 |
| 5 | `--update` has no rollback path if the latest binary or rewritten lockfile breaks local usage. | 4 | 3 | 3 | 3 | 7.2 | P1 |
| 6 | Plugin cache and hook compatibility are not fully validated before launch. | 3 | 4 | 4 | 3 | 7.0 | P1 |
| 7 | Network, proxy, TLS CA, and GitHub rate-limit failures are handled only at the point of failure, without a targeted diagnostic. | 3 | 4 | 4 | 3 | 7.0 | P1 |
| 8 | Project trust is configured for only a few absolute paths, so new target repositories may need manual trust handling. | 3 | 3 | 4 | 2 | 7.0 | P2 |
| 9 | Proxy configuration is global to the wrapper, and `--clear` removes the whole `.codex_config` rather than only proxy settings. | 3 | 3 | 3 | 2 | 6.6 | P2 |
| 10 | The wrapper does not check target-project tools such as package managers, test runners, compilers, or `gh`. | 2 | 4 | 4 | 3 | 6.2 | P2 |
| 11 | Release asset detection supports only Linux/Darwin on `x86_64`/`aarch64`. | 2 | 2 | 2 | 3 | 4.6 | P3 |

## Recommended Work Order

1. P0: make runtime isolation explicit and safe by default.
2. P0: decide whether to keep a shared `CODEX_HOME` or introduce per-project homes.
3. P0: add `icodex doctor` or equivalent preflight checks for auth, model, provider, quota, binary, `uv`, proxy, and plugin readiness.
4. P1: add file locking around launch-time config rewrites, install/update, and persisted config writes.
5. P1: add update rollback or keep-last-known-good binary support.
6. P1: add targeted plugin and network diagnostics.
7. P2: improve trust/proxy ergonomics and optional target-project tool checks.

## Notes

- The highest-risk gaps are runtime isolation and shared state, not binary
  installation.
- The current wrapper intentionally keeps the implementation dependency-light;
  each fix should preserve that constraint unless a specific dependency is
  justified by reliability gains.
- Documentation-only changes do not require wiki regeneration.
