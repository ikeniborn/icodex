---
name: context-awareness
description: Detect project language, framework, package manager, lint/test commands and locate CLAUDE.md / PRD docs at task start (Phase 0). Also detects iwiki documentation and code-graph availability/state. Use when starting any task, switching project, or before running syntax/test checks. NOT for deep wiki or code-graph queries — this skill only detects availability and quick context.
user-invocable: false
agent: Explore
# version: 1.7.2
# tags: context, detection, project, language, framework, lat
# dependencies: []
# files: templates: ./templates/*.json, shared: ../_shared/syntax-commands.json
---

# Context Awareness

## Subagent Routing

Agent: `project-explorer`

Use a subagent when file layout, docs skeleton, iwiki status, language/framework hints, or candidate syntax/test command discovery can be scanned read-only and summarized.

Stay in the main context for final project_context synthesis, task-specific documentation interpretation, and deep semantic wiki searches.

Return summary:
- decision: `OK`, `needs_work`, or `uncertain`
- evidence: file paths, detected signals, docs paths, iwiki signals, and command hints
- risks: contradictory project signals, missing docs, unavailable iwiki data, or uncertain test command choice
- next_action: the smallest main-context action required

Stop rule: contradictory project signals are reported as ambiguity; the main context decides or asks. Main context keeps final project_context synthesis, task-specific documentation interpretation, and deep semantic wiki searches.

Автоматическое определение языка, framework, наличия PRD и домена документации iwiki (MCP) для проекта.

## Когда использовать

- В начале КАЖДОЙ задачи (Phase 0)
- При переключении между проектами
- Когда нужно определить syntax check команду

## Алгоритм определения

### 1. Определение языка

```
Приоритет файлов:
1. package.json → JavaScript/TypeScript
2. requirements.txt, pyproject.toml → Python
3. go.mod → Go
4. Cargo.toml → Rust
5. *.sh в корне → Bash
```

### 2. Определение framework

```
Python:
- fastapi в dependencies → FastAPI
- django в dependencies → Django
- flask в dependencies → Flask

JavaScript:
- react в dependencies → React
- express в dependencies → Express
- next в dependencies → Next.js
```

### 3. Определение PRD

```
Пути для проверки:
- docs/prd/
- docs/PRD.md
- PRD.md
- docs/requirements/
```

### 4. Syntax Command Lookup

См. `@shared:syntax-commands.json` для mapping language → syntax check command.

### 5. iwiki Detection

Документационный граф проекта живёт в **MCP-сервере iwiki** (внешний central-store,
адресуется доменами). Единственный источник документационного контекста проекта.

```
1. Когда известны canonical topic и basename проекта, всегда проверить `$CODEX_HOME/state/iwiki-task-spool/<project>/<topic>.json`, even when iwiki is unavailable or the project domain is absent. Установить
   `task_delivery_pending: true when that queue file exists`; очередь не является
   durable status.

IF MCP-сервер iwiki подключён:
  2. For local stdio or remote HTTP: load and normalize the full `read`, `write`, and `primary` scope from project `.iwiki.toml`, then call `wiki_bind` with that full scope before `wiki_status`; never narrow to basename or substitute a primary. Hosted HTTP also passes project `[specifications].mode` as `specification_mode` when its callable schema accepts it. Under generated remote-scope instructions, missing, invalid, or rejected scope permits no mutation and retains `completion-pending`.
  3. wiki_status → storage, transport, список `domains`, текущая привязка read/write/primary. On hosted HTTP, trust status only when `binding_source == "session"` and requested primary remains unchanged; otherwise rebind and repeat once, or report `completion-pending`. Read the effective per-domain specification mode from `wiki_status`; never infer it from `.iwiki.toml`. `source: hosted_override` legitimately outranks project mode and is not a mismatch; `project_mode_suppressed: true` means the carried project value was refused and must be reported. If its callable schema lacks `specification_mode`, bind rejects it, or status reports an unaccepted mismatch, report it, make no mutating specification call, and retain `completion-pending`; ordinary non-specification Wiki work remains available.
  4. Если `primary` присутствует в `domains` и trusted binding is available:
       - wiki_summary ← wiki_read_page(primary, "overview") (если есть)
         либо wiki_search('ключевые компоненты и архитектура проекта')
     Добавить в project_context:
       wiki_initialized: true
       wiki_domain: "<primary>"
       wiki_summary: <обзор страницы overview или результат wiki_search>
       task_topic: <canonical topic or null>
       task_page_slug: "reference/tasks/<topic>" | null
       task_page_found: true|false
       task_lifecycle: "in-progress|blocked|completion-pending|done" | null
       task_delivery_pending: true|false
     Для Python, TypeScript, JavaScript, or Bash code-analysis вызвать read-only `wiki_code_status`:
       code_graph_available: true только когда state == "ready" and fresh == true;
         for hosted HTTP also require binding_source == "session"
       code_graph_domain: "<primary>"
       code_graph_state: <state либо стабильный error code>
       code_graph_fresh: <fresh when answered; otherwise null>
       code_graph_binding_source: <binding_source when answered; otherwise null>
     При ready предпочитать `wiki_code_search` / `wiki_code_context` для symbol lookup,
     relations и impact analysis. missing/stale/failed/not_configured не блокируют fallback на rg.
  4. Если домена проекта нет:
       wiki_initialized: false
       wiki_domain: null
       wiki_summary: null
       task_topic: <canonical topic or null>
       task_page_slug: "reference/tasks/<topic>" | null
       task_page_found: false
       task_lifecycle: null
       task_delivery_pending: <spool result when topic known; otherwise false>
       code_graph_available: false
       code_graph_domain: null
       code_graph_state: null
       code_graph_fresh: null
       code_graph_binding_source: null

ELSE (сервер не подключён):
  wiki_initialized: false
  wiki_domain: null
  wiki_summary: null
  task_topic: <canonical topic or null>
  task_page_slug: "reference/tasks/<topic>" | null
  task_page_found: false
  task_lifecycle: null
  task_delivery_pending: <spool result when topic known; otherwise false>
  code_graph_available: false
  code_graph_domain: null
  code_graph_state: null
  code_graph_fresh: null
  code_graph_binding_source: null
```

После привязки домена Phase 0 выводит точный контекст task page: определяет
канонический topic из запроса или уже контролируемых артефактов, читает
`reference/tasks/<topic>`, если topic известен. Независимо от доступности iwiki он
проверяет `$CODEX_HOME/state/iwiki-task-spool/<project>/<topic>.json`; очередь показывает
только `task_delivery_pending`, она не является durable status. Создание страницы остаётся
интерактивным действием parent agent по `task-ledger`, не действием context-awareness.

**Назначение:** Централизует проверку доступности документационного графа —
downstream-навыки (brainstorming, prd-generator) используют
`project_context.wiki_initialized` вместо самостоятельной проверки.
`wiki_search` — опциональный семантический поиск по секциям внутри задачи.
`wiki_code_status` — read-only availability probe; этот skill никогда не вызывает
`wiki_code_index` и не публикует snapshot.

## Output

Используй шаблон: `@template:project-context`

## Quick Reference

```json
{
  "project_context": {
    "language": "python|javascript|typescript|go|rust|bash",
    "framework": "fastapi|django|react|express|none",
    "test_framework": "pytest|jest|go test|none",
    "has_prd": true|false,
    "prd_path": "docs/prd/" | null,
    "syntax_command": "@shared:syntax-commands[language].syntax",
    "code_style": "pep8|prettier|gofmt|none",
    "wiki_initialized": true|false,
    "wiki_domain": "<имя домена iwiki>" | null,
    "wiki_summary": "синтезированный обзор из домена iwiki" | null,
    "code_graph_available": true,
    "code_graph_domain": "<primary>",
    "code_graph_state": "ready",
    "code_graph_fresh": true,
    "code_graph_binding_source": "session",
    "task_topic": "<topic>" | null,
    "task_page_slug": "reference/tasks/<topic>" | null,
    "task_page_found": true|false,
    "task_lifecycle": "in-progress|blocked|completion-pending|done" | null,
    "task_delivery_pending": false
  }
}
```

## Examples

### Example 1: Python FastAPI Project

**Project structure:**
```
/home/user/api-project/
├── requirements.txt (fastapi==0.104.1)
├── pyproject.toml
├── src/
│   └── main.py
├── tests/
└── docs/
    └── prd/
        └── API_SPEC.md
```

**Detection result:**
```json
{
  "project_context": {
    "language": "python",
    "framework": "fastapi",
    "test_framework": "pytest",
    "has_prd": true,
    "prd_path": "docs/prd/",
    "syntax_command": "python -m py_compile",
    "code_style": "pep8",
    "wiki_initialized": false,
    "wiki_domain": null,
    "wiki_summary": null,
    "code_graph_available": false,
    "code_graph_domain": null,
    "code_graph_state": null,
    "code_graph_fresh": null,
    "code_graph_binding_source": null,
    "task_topic": null,
    "task_page_slug": null,
    "task_page_found": false,
    "task_lifecycle": null,
    "task_delivery_pending": false
  }
}
```

---

### Example 2: TypeScript React Project

**Project structure:**
```
/home/user/web-app/
├── package.json (react: ^18.2.0, typescript: ^5.0.0)
├── tsconfig.json
├── src/
│   ├── App.tsx
│   └── components/
├── tests/
└── PRD.md
```

**Detection result:**
```json
{
  "project_context": {
    "language": "typescript",
    "framework": "react",
    "test_framework": "jest",
    "has_prd": true,
    "prd_path": "PRD.md",
    "syntax_command": "tsc --noEmit",
    "code_style": "prettier",
    "wiki_initialized": false,
    "wiki_domain": null,
    "wiki_summary": null,
    "code_graph_available": false,
    "code_graph_domain": null,
    "code_graph_state": null,
    "code_graph_fresh": null,
    "code_graph_binding_source": null,
    "task_topic": null,
    "task_page_slug": null,
    "task_page_found": false,
    "task_lifecycle": null,
    "task_delivery_pending": false
  }
}
```

---

### Example 3: Go Project with PRD

**Project structure:**
```
/home/user/go-service/
├── go.mod
├── main.go
├── internal/
│   └── handlers/
├── tests/
└── docs/
    └── requirements/
        └── SPEC.md
```

**Detection result:**
```json
{
  "project_context": {
    "language": "go",
    "framework": "none",
    "test_framework": "go test",
    "has_prd": true,
    "prd_path": "docs/requirements/",
    "syntax_command": "go build -o /dev/null",
    "code_style": "gofmt",
    "wiki_initialized": false,
    "wiki_domain": null,
    "wiki_summary": null,
    "code_graph_available": false,
    "code_graph_domain": null,
    "code_graph_state": null,
    "code_graph_fresh": null,
    "code_graph_binding_source": null,
    "task_topic": null,
    "task_page_slug": null,
    "task_page_found": false,
    "task_lifecycle": null,
    "task_delivery_pending": false
  }
}
```

---

### Example 4: Bash Script Project — без привязанного домена iwiki

**Project structure:**
```
/home/user/scripts/
├── deploy.sh
├── backup.sh
├── utils/
│   └── logger.sh
└── README.md
```

**Detection result:**
```json
{
  "project_context": {
    "language": "bash",
    "framework": "none",
    "test_framework": "none",
    "has_prd": false,
    "prd_path": null,
    "syntax_command": "bash -n",
    "code_style": "none",
    "wiki_initialized": false,
    "wiki_domain": null,
    "wiki_summary": null,
    "code_graph_available": false,
    "code_graph_domain": null,
    "code_graph_state": null,
    "code_graph_fresh": null,
    "code_graph_binding_source": null,
    "task_topic": null,
    "task_page_slug": null,
    "task_page_found": false,
    "task_lifecycle": null,
    "task_delivery_pending": false
  }
}
```

---

### Example 4b: Bash Script Project — с привязанным доменом iwiki

**Project structure:**
```
/home/user/iclaude/
├── iclaude.sh
├── lib/
│   └── proxy/...
└── docs/
    ├── PROXY.md
    └── ROUTER.md
```

**Detection result:**
```json
{
  "project_context": {
    "language": "bash",
    "framework": "none",
    "test_framework": "pytest",
    "has_prd": false,
    "prd_path": null,
    "syntax_command": "bash -n",
    "code_style": "none",
    "wiki_initialized": true,
    "wiki_domain": "iclaude",
    "wiki_summary": "iclaude — bash-обёртка для Claude Code: HTTP/HTTPS-прокси, изолированная NVM-среда, OAuth-обновление токенов, Claude Code Router, PII-прокси (Presidio), microVM-песочница, security-хуки.",
    "code_graph_available": false,
    "code_graph_domain": "iclaude",
    "code_graph_state": "not_configured",
    "code_graph_fresh": false,
    "code_graph_binding_source": "session",
    "task_topic": "proxy-audit",
    "task_page_slug": "reference/tasks/proxy-audit",
    "task_page_found": true,
    "task_lifecycle": "in-progress",
    "task_delivery_pending": false
  }
}
```

---

### Example 4c: Bash Script Project — с привязанным доменом iwiki (минимальный)

**Project structure:**
```
/home/user/iclaude/
├── iclaude.sh
├── lib/
└── docs/
```

**Detection result:**
```json
{
  "project_context": {
    "language": "bash",
    "framework": "none",
    "test_framework": "pytest",
    "has_prd": false,
    "prd_path": null,
    "syntax_command": "bash -n",
    "code_style": "none",
    "wiki_initialized": true,
    "wiki_domain": "iclaude",
    "wiki_summary": "iclaude — bash-обёртка для Claude Code: прокси, NVM, OAuth, PII-маскирование, microVM, security-хуки.",
    "code_graph_available": false,
    "code_graph_domain": "iclaude",
    "code_graph_state": "not_configured",
    "code_graph_fresh": false,
    "code_graph_binding_source": "session",
    "task_topic": "proxy-audit",
    "task_page_slug": "reference/tasks/proxy-audit",
    "task_page_found": true,
    "task_lifecycle": "completion-pending",
    "task_delivery_pending": true
  }
}
```

---

### Example 5: Multi-Language Project (Python Backend + JS Frontend)

**Project structure:**
```
/home/user/fullstack-app/
├── backend/
│   ├── requirements.txt (fastapi)
│   └── src/
├── frontend/
│   ├── package.json (react)
│   └── src/
├── docs/
│   └── PRD.md
└── README.md
```

**Detection priority (root directory check first):**
```json
{
  "project_context": {
    "language": "python",
    "framework": "fastapi",
    "test_framework": "pytest",
    "has_prd": true,
    "prd_path": "docs/PRD.md",
    "syntax_command": "python -m py_compile",
    "code_style": "pep8",
    "code_graph_available": false,
    "code_graph_domain": null,
    "code_graph_state": null,
    "code_graph_fresh": null,
    "code_graph_binding_source": null,
    "task_topic": "service-contract-check",
    "task_page_slug": "reference/tasks/service-contract-check",
    "task_page_found": true,
    "task_lifecycle": "blocked",
    "task_delivery_pending": false,
    "notes": [
      "Multi-language project detected",
      "Frontend: JavaScript/React in frontend/ subdirectory",
      "Backend language (Python) selected as primary based on root-level requirements.txt"
    ]
  }
}
```

**Alternative detection (if invoked from frontend/ subdirectory):**
```json
{
  "project_context": {
    "language": "javascript",
    "framework": "react",
    "test_framework": "jest",
    "has_prd": true,
    "prd_path": "../docs/PRD.md",
    "syntax_command": "npx tsc --noEmit",
    "code_style": "prettier",
    "code_graph_available": false,
    "code_graph_domain": null,
    "code_graph_state": null,
    "code_graph_fresh": null,
    "code_graph_binding_source": null,
    "task_topic": "frontend-typecheck",
    "task_page_slug": "reference/tasks/frontend-typecheck",
    "task_page_found": false,
    "task_lifecycle": null,
    "task_delivery_pending": false,
    "notes": [
      "Working directory: frontend/",
      "Root project has multi-language structure"
    ]
  }
}
```

---

## Integration with Other Skills

**Used by:**
- `adaptive-workflow` - Selects complexity based on project type
- `lsp-integration` - Determines which LSP server to install
- `validation-framework` - Chooses appropriate validation commands
- `code-review` - Applies language-specific review rules

**Delegates to:**
- iwiki MCP `wiki_search` - Targeted semantic search over the project's iwiki domain (optional, in-task)
- iwiki MCP `wiki_code_status` - Read-only code-graph availability check for Python, TypeScript, JavaScript, or Bash

**Provides:**
- `language` → Enables language-specific tooling
- `framework` → Enables framework-specific patterns
- `prd_path` → Enables PRD-driven validation
- `syntax_command` → Enables pre-commit syntax checks
- `wiki_initialized` / `wiki_domain` / `wiki_summary` → Enables doc-graph-aware context without re-checking files
- `code_graph_available` / `code_graph_domain` / `code_graph_state` / `code_graph_fresh` / `code_graph_binding_source` → Enables code-graph-first symbol and impact analysis
- `task_topic` / `task_page_slug` / `task_page_found` / `task_lifecycle` / `task_delivery_pending` → Surfaces exact task-page and non-authoritative spool state

---

🤖 Generated with Claude Code

**Author:** ikeniborn
**License:** MIT

## Changelog

### 1.7.1 (2026-08-20)
- Full `.iwiki.toml` binding now applies before status for local stdio and remote HTTP
- Added read-only Python/TypeScript code-graph availability fields via `wiki_code_status`
- Ready graphs route symbol and impact lookup to `wiki_code_search` / `wiki_code_context`

### 1.6.0 (2026-08-12)
- Phase 0 now resolves exact iwiki task-page context and reports pending local delivery without treating it as durable status

### 1.5.0 (2026-06-30)
- iwiki detection switched from `docs/wiki/` files to the iwiki MCP server (`wiki_status`)
- Output field `wiki_index_path` → `wiki_domain`; `iwiki:iwiki-query` delegate → MCP `wiki_search`

### 1.4.1 (2026-06-18)
- Удалён graphify knowledge-graph detection (Phase 6) и поля `graph_*` из output — graphify выпилен из проекта
- `graphify-context` убран из delegates

### 1.4.0 (2026-06-17)
- Заменён `lat.md/` detect на `docs/wiki/` detection (читает корневой индекс `docs/wiki/index.md`)
- Поля `lat_*` → `wiki_*` (`wiki_initialized`, `wiki_index_path`, `wiki_summary`)
- `graphify` detection дополнен: docs/wiki = проза, graph = структура
- `lat-search` заменён на `iwiki:iwiki-query` в delegates и dependencies

### 1.3.0 (2026-06-07)
- Заменён мёртвый detect `.wiki/` + `llm-wiki` на `lat.md/` detection (читал корневой индекс `lat.md/lat.md`)
- `lat-search` и `graphify-context` оформлены как delegates; добавлены в dependencies

### 1.2.0 (2026-02-19)

### 1.1.0 (2026-01-25)
- Добавлено: 5 примеров (Python FastAPI, TypeScript React, Go with PRD, Bash, multi-language)
- Обновлены references на @shared:
- Улучшена документация detection алгоритмов

### 1.0.0 (2025-XX-XX)
- Initial release
