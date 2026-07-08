# Отчет по smoke-проверке LoEn loop

## Контекст

Проверка запускалась после обновления LoEn loop-flow: `loop-start` собирает требования, режим и план, затем утвержденный контракт передается в `loop-run`. Дальше выбранный режим должен сам довести цепочку до пользовательской приемки: `7_result.md` для успешного результата или `handoff.md`, если продолжать нельзя.

Цель smoke-набора - проверить не бизнес-результат конкретной задачи, а контракт выполнения: режим, subtype, preflight, verifier, evidence, result/handoff и audit trail.

## Итог

- Проверено 5 кейсов.
- Положительные delivery/governance кейсы завершились ожидаемым `result`.
- Негативный governance `merge-release` кейс завершился ожидаемым `handoff`.
- Analyzer failures: `0`.
- Базовое качество цепочки приемлемое: контракт читаемый, preflight работает, evidence сохраняется, terminal-state совпадает с ожиданиями.

## Матрица кейсов

| Кейс | Режим | Subtype | Ожидание | Факт | Что доказано |
|---|---|---|---|---|---|
| `smoke-delivery-pass` | `delivery` | `null` | `result` | `result` | Обычная задача проходит по утвержденному плану, сохраняет evidence и результат. |
| `smoke-governance-report-only` | `governance` | `report-only` | `result` | `result` | Governance может выполнить проверку и отчет без изменения product-файлов. |
| `smoke-governance-auto-fix` | `governance` | `auto-fix` | `result` | `result` | Governance может выполнить ограниченное исправление внутри разрешенной области и подтвердить verifier. |
| `smoke-governance-merge-release` | `governance` | `merge-release` | `result` | `result` | Merge/release сценарий проходит проверку политики и dry-run evidence-flow. |
| `smoke-governance-negative-policy` | `governance` | `merge-release` | `handoff` | `handoff` | Неполная merge/release policy блокируется до действия и переводится в handoff. |

## Пояснения по режимам

### Delivery

`delivery` моделирует обычную задачу: есть цель, план, область изменения, verifier и ожидаемый результат. В smoke-кейсе важно, что `loop-run` не требует ручного продолжения после plan approval и доходит до `7_result.md`.

### Governance report-only

`report-only` нужен для безопасных проверок, где система только собирает состояние и пишет отчет. Этот режим должен сохранять `auto_fix: false` и `auto_merge: false`, потому что он не имеет права менять файлы или делать release-действия.

### Governance auto-fix

`auto-fix` разрешает ограниченное исправление. В smoke-кейсе mutation была локальной и предсказуемой: изменялся только файл внутри topic-scope, затем verifier подтвердил состояние. Это проверяет, что автоматизация не просто пишет отчет, а может исправить найденную проблему при явном разрешении.

### Governance merge-release

`merge-release` должен поддерживать release-цепочку, но в smoke он выполнен как dry-run. Это осознанное ограничение: smoke не должен реально мержить ветки или публиковать релизы. Проверено, что policy достаточно полная для запуска и что evidence/release dry-run сохраняется.

### Negative policy

Негативный кейс проверяет защиту: если merge/release policy неполная, `loop-run` не должен начинать действия. Правильный результат здесь - не `result`, а `handoff` с причиной остановки.

## Оценка качества

Сильные стороны:

- `loop-start` формирует пригодный run contract: mode, subtype, approval, plan hash, scope, verifier, budget, rollback/recovery policy.
- `loop-run` явно различает успешный результат и остановку через handoff.
- Governance attempts видны в `attempts.jsonl`, audit и terminal artifacts.
- Preflight защищает опасный subtype `merge-release` от запуска при неполной policy.
- Smoke-набор покрывает не только happy path, но и отказ по политике.

Ограничения:

- `merge-release` проверен в dry-run, без реального merge, branch protection, tags, release notes и публикации релиза.
- Smoke не проверяет интерактивный UI выбора режима, только итоговый contract/artifact flow.
- Smoke-кейсы созданы как репозиторные артефакты анализа, а не как отдельный переиспользуемый CI-runner.
- Проверка качества contract выполнялась по текущим артефактам, а не через долгий production-loop с несколькими repair-итерациями.

## Где смотреть артефакты

- `docs/loen/smoke-case-analysis/case-matrix.md` - краткая матрица кейсов.
- `docs/loen/smoke-case-analysis/quality-report.md` - англоязычный технический отчет.
- `docs/loen/smoke-delivery-pass/` - delivery smoke.
- `docs/loen/smoke-governance-report-only/` - governance report-only.
- `docs/loen/smoke-governance-auto-fix/` - governance auto-fix.
- `docs/loen/smoke-governance-merge-release/` - governance merge-release dry-run.
- `docs/loen/smoke-governance-negative-policy/` - governance negative-policy handoff.

## Проверки

Во время smoke-работы были выполнены:

- `bash tests/test_loen_plugin_core.sh`
- `bash tests/test_loen_loop_run_contract.sh`
- `bash tests/test_loen_automation_governance.sh`
- `python3 -m py_compile plugins/loen/hooks/*.py .codex-isolated/plugins/cache/icodex-local/loen/0.1.0/hooks/*.py`
- `for t in tests/test_*.sh; do bash "$t" || exit 1; done`
- `git diff --check`

Все проверки прошли. Дополнительно smoke-analyzer показал `failure_count=0`.

## Вывод

LoEn loop после обновления выглядит пригодным для базового автоматизированного прогона: пользователь участвует на этапе intake/plan approval, после чего `loop-run` ведет цепочку до `7_result.md` или `handoff.md`. Главный оставшийся риск - реальная merge/release automation пока подтверждена только dry-run smoke-кейсом; для production-доверия нужен отдельный сценарий с тестовым репозиторием, защищенной веткой, тегом и release artifact.
