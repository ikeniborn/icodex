# Task Log

| Topic | Status | Intent | Spec | Plan | Result | Opened | Closed | Notes |
|-------|--------|--------|------|------|--------|--------|--------|-------|
| icodex-idd-integration | done | n/a | ✓ | ✓ | OK | 2026-06-30 | 2026-06-30 | IDD→SDD port: 2 hooks + 4 validator skills + wiring; all IDD tests green |
| icodex-iwiki-mcp | done | n/a | ✓ | ✓ | OK | 2026-06-30 | 2026-07-01 | iwiki-mcp server wired into isolated Codex (+ per-project .iwiki.toml binding); check-result OK: 5/5 tasks DONE, 0 findings, full suite 31 files/0 FAIL, no secret leak, E2E verified |
| icodex-iwiki-path-config | done | n/a | ✓ | ✓ | OK | 2026-07-01 | 2026-07-01 | Externalize FULL IWIKI_* server surface (12 vars) to ICODEX_IWIKI_* in .codex_config; tiered — command auto-detect, 3 required (base/url/key) guarded warn+skip, 8 optional emit-if-set, PROJECT_DIR excluded; check-result OK: 4/4 tasks DONE, 0 findings, wiring test 28/0, full suite 31 files ALL GREEN, source de-hardcoded (SC#1 hit is inverse-defect test pattern) |
| icodex-idd-unify | done | n/a | ✓ | ✓ | OK | 2026-07-01 | 2026-07-01 | Unify IDD chain: single chain-gate.py + check-chain + fix-intent (replaces split 2 hooks + 4 check-* + intent); 4 SDD tasks all review-Approved, full suite 30 files/444 PASS/0 FAIL; check-chain spec+plan+result OK; final whole-branch review READY TO MERGE (0 crit/0 imp, 3 minor: M1 fix-intent `lat`→iwiki upstream wart left as faithful port, M2 config.md hook refs fixed, M3 cosmetic) |
