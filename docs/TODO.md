# Task Log

| Topic | Status | Intent | Spec | Plan | Result | Opened | Closed | Notes |
|-------|--------|--------|------|------|--------|--------|--------|-------|
| icodex-idd-integration | done | n/a | ✓ | ✓ | OK | 2026-06-30 | 2026-06-30 | IDD→SDD port: 2 hooks + 4 validator skills + wiring; all IDD tests green |
| icodex-iwiki-mcp | done | n/a | ✓ | ✓ | OK | 2026-06-30 | 2026-07-01 | iwiki-mcp server wired into isolated Codex (+ per-project .iwiki.toml binding); check-result OK: 5/5 tasks DONE, 0 findings, full suite 31 files/0 FAIL, no secret leak, E2E verified |
| icodex-iwiki-path-config | done | n/a | ✓ | ✓ | OK | 2026-07-01 | 2026-07-01 | Externalize FULL IWIKI_* server surface (12 vars) to ICODEX_IWIKI_* in .codex_config; tiered — command auto-detect, 3 required (base/url/key) guarded warn+skip, 8 optional emit-if-set, PROJECT_DIR excluded; check-result OK: 4/4 tasks DONE, 0 findings, wiring test 28/0, full suite 31 files ALL GREEN, source de-hardcoded (SC#1 hit is inverse-defect test pattern) |
