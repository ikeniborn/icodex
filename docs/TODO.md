# Task Log

| Topic | Status | Intent | Spec | Plan | Result | Opened | Closed | Notes |
|-------|--------|--------|------|------|--------|--------|--------|-------|
| icodex-idd-integration | done | n/a | ✓ | ✓ | OK | 2026-06-30 | 2026-06-30 | IDD→SDD port: 2 hooks + 4 validator skills + wiring; all IDD tests green |
| icodex-iwiki-mcp | done | n/a | ✓ | ✓ | OK | 2026-06-30 | 2026-07-01 | iwiki-mcp server wired into isolated Codex (+ per-project .iwiki.toml binding); check-result OK: 5/5 tasks DONE, 0 findings, full suite 31 files/0 FAIL, no secret leak, E2E verified |
| icodex-iwiki-path-config | in-progress | n/a | ✓ | – | – | 2026-07-01 |  | De-hardcode iwiki command + IWIKI_BASE_DIR; hybrid (PATH auto-detect + required ICODEX_IWIKI_BASE_DIR), warn+skip guard; check-spec OK |
