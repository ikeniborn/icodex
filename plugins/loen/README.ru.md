# Плагин LoEn

LoEn — plugin source для Loop Engineering внутри icodex. Он добавляет навыки
Codex, hooks, agents и шаблоны для рабочих циклов, где состояние задачи хранится
в файлах репозитория, а не в истории чата.

## Что добавляет LoEn

- Навыки `loen:loop-start`, `loen:loop-plan`, `loen:loop-act`,
  `loen:loop-check`, `loen:loop-reflect`, `loen:loop-status`,
  `loen:loop-repair`, `loen:loop-research`, `loen:loop-review` и
  `loen:loop-governance`.
- Hooks для контроля active loop state, mutable/protected scope, role/tool
  policy, shell/network policy и обязательных evidence перед финальным
  результатом.
- Agent definitions для planner, worker, verifier, reviewer и researcher.
- Шаблоны durable loop artifacts в `docs/loen/<topic>/`.

## Включение в icodex

icodex подключает LoEn в каждый isolated Codex home при обычном запуске.
Команды install/update остаются binary-only и LoEn не настраивают.

Поведение управляется переменной `ICODEX_LOEN_MODE`:

| Режим | Поведение |
|---|---|
| `off` | Отключить LoEn wiring и hooks. |
| `advisory` | Включить skills и неблокирующие hook-подсказки. Режим по умолчанию. |
| `enforce` | Блокировать отсутствие loop state, нарушения порядка стадий, protected paths и отсутствие evidence. |
| `strict` | Добавить проверки ролей, tools, shell/network и разделения worker/verifier. |

Пример:

```bash
ICODEX_LOEN_MODE=advisory ./icodex.sh
```

## Работа с loop

Начинай с `loen:loop-start`, чтобы создать topic directory:

```text
docs/loen/<topic>/
```

В topic directory хранятся:

- numbered stage files от `1_goal.md` до `7_result.md`;
- `loop.yaml` со scope, mode, verifier, budget, stop rules и governance;
- `attempts.jsonl` с записями запусков;
- `evidence/` для check/verifier output;
- `handoff.md`;
- regenerated `audit.html`.

Для просмотра состояния используй `loen:loop-status`. Для одного bounded pass
через loop используй `loen:loop-plan`, `loen:loop-act`, `loen:loop-check` и
`loen:loop-reflect`.

## Vendoring для Codex

Редактируй plugin source в этой директории. Чтобы пересобрать committed Codex
cache, который использует icodex launch wiring, запусти:

```bash
./scripts/vendor-loen.sh
```

Скрипт копирует source tree в:

```text
.codex-isolated/plugins/cache/icodex-local/loen/<version>/
```

Он проверяет обязательные assets и удаляет generated files вроде `__pycache__`
и `*.pyc`.

## Границы

LoEn самодостаточен и не зависит от других workflow plugins. Он пишет loop state
только в `docs/loen/<topic>/` и обновляет `docs/TODO.md` как global task index.
LoEn не делает auto-merge, не переписывает protected files и не обходит
`LOEN_MODE`.

Внутренние детали plugin source описаны в `docs/README.md` и
`docs/architecture.md`.
