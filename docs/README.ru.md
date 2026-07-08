# icodex

> Русский перевод [`README.md`](../README.md). При расхождениях источником истины
> считается английский README.

Изолированная bash-обёртка над [OpenAI Codex CLI](https://developers.openai.com/codex/cli),
сделанная по образцу `iclaude`. Она полностью замыкает Codex внутри проекта:
закреплённый статический бинарь `codex`, **состояние на каждый проект**, **безопасная по
умолчанию** файловая песочница и опциональная маршрутизация через прокси — поэтому Codex не
трогает ваш домашний каталог или другие проекты, пока вы сами этого не разрешите.

## Как работает изоляция

icodex хранит состояние Codex в двух слоях:

- **Общий склад** — `.codex-isolated/` держит дорогие, стабильные ассеты, общие для всех
  проектов: закреплённый бинарь `codex`, `uv`, вендоренный кеш плагина Superpowers, общий
  `auth.json` и отслеживаемый шаблон `config.toml`.
- **Home проекта** — каждый проект, из которого вы запускаетесь, получает собственный
  `CODEX_HOME` в `.codex-homes/<проект>-<хеш>/`. Он симлинкует общие ассеты (`plugins`,
  `skills`, `rules`, скрипты-хуки и `auth.json`), копирует шаблон `config.toml`, держит
  глобальные указания `AGENTS.md` в синхроне и хранит сессии, логи и sqlite этого проекта
  отдельно — см. [Что лежит в home проекта](#что-лежит-в-home-проекта). Home ключуется по
  git-корню проекта (или рабочему каталогу), поэтому два репозитория никогда не делят
  состояние сессий, но делят один логин и один бинарь.

`.codex-homes/` — это рантайм-состояние, оно в git-ignore.

## Установка

1. **Установить бинарь** (один раз на клон):

       ./icodex.sh --install

   Скачивает закреплённый бинарь `codex` (версия + sha256 из `.codex-lockfile.json`) в
   `.codex-isolated/bin/` и создаёт симлинк `icodex` в `~/.local/bin` (переопределяется
   `ICODEX_LINK_DIR`). Добавьте этот каталог в `PATH`, чтобы запускать `icodex` откуда
   угодно. Существующий не-симлинк по пути ссылки никогда не перезаписывается.

2. **Аутентификация** (выберите одно):

   - Запустите `codex login` — пишет `.codex-isolated/auth.json` (в git-ignore, общий для
     всех проектов), или
   - Задайте `ICODEX_API_KEY=sk-...` в `.codex_config` (см. [Переменные конфигурации](#переменные-конфигурации)), или
   - Экспортируйте `OPENAI_API_KEY` в шелле — внешний ключ всегда побеждает.

3. **Запуск** из любого каталога проекта:

       icodex                      # запустить Codex, изолированно для текущего проекта
       icodex -- exec "..."        # всё после -- передаётся в codex дословно

## Команды

    ./icodex.sh                 # запустить codex в изолированном окружении (по умолчанию)
    icodex                      # то же, когда ~/.local/bin в PATH
    ./icodex.sh --full-access   # запуск с полностью открытой файловой песочницей (предупреждает)
    ./icodex.sh --proxy http://p:8080 -- exec "..."   # через прокси, аргументы — в codex
    ./icodex.sh --no-proxy      # пропустить прокси для этого запуска
    ./icodex.sh --install       # скачать закреплённый бинарь + создать симлинк icodex
    ./icodex.sh --update        # обновить и пере-закрепить только бинарь codex
    ./icodex.sh --clear         # удалить сохранённый файл конфига (.codex_config)
    ./icodex.sh --version       # версии icodex + codex
    ./icodex.sh --help          # полный список флагов

Всё после первого не-флагового аргумента (или после `--`) передаётся прямо в `codex`.
На `--install`/`--update` симлинк `icodex` создаётся в `ICODEX_LINK_DIR`. `--install` и
`--update` качают только бинарь Codex. `--update` сначала определяет latest release; если
эта версия уже совпадает с установленным stamp и lockfile pin, архив не скачивается,
извлечение не запускается, lockfile не перезаписывается. Когда есть новая версия,
`--update` печатает каждую стадию сети/установки с прогресс-баром скачивания curl. Плагин
Superpowers и скиллы едут через git и обновляются только мейнтейнерскими скриптами.

## Переменные конфигурации

Настройки, которые нужны на каждом запуске, лежат в файле `.codex_config` в корне проекта
(в git-ignore, `chmod 600`). Начните с шаблона:

    cp .codex_config.example .codex_config
    chmod 600 .codex_config

Файл содержит простые строки `KEY=value`. **Учитываются только ключи с префиксом `ICODEX_`**,
и файл парсится — никогда не `source`-ится — поэтому значения не могут выполнить код.
Приоритет: **встроенные дефолты < `.codex_config` < флаги командной строки**. Любую
переменную ниже можно задать и как обычную переменную окружения.

| Переменная | Эффект | По умолчанию |
|------------|--------|--------------|
| `ICODEX_API_KEY` | Ключ OpenAI API → экспортируется как `OPENAI_API_KEY` (секрет; внешний `OPENAI_API_KEY` побеждает) | — |
| `ICODEX_MODE` | Пресет профиля запуска — задаёт песочницу, одобрение и управляемые права вместе (см. [Режим запуска](#режим-запуска-icodex_mode)) | `full-ask` |
| `ICODEX_SANDBOX` | Точечное переопределение: только файловая песочница — `read-only`, `workspace-write` или `danger-full-access`; приоритетнее `ICODEX_MODE` для поля sandbox | — |
| `ICODEX_APPROVAL` | Точечное переопределение: только политика одобрения — `untrusted`, `on-failure`, `on-request` или `never`; приоритетнее `ICODEX_MODE` для поля approval | — |
| `ICODEX_PERMISSIONS` | Точечное переопределение: только профиль управляемых прав — `dev-safe`, `ssh-on-request` или `none`; приоритетнее `ICODEX_MODE` для поля permissions | — |
| `ICODEX_PROXY` | URL прокси, экспортируется как `HTTPS_PROXY` / `HTTP_PROXY` для codex | — |
| `ICODEX_NO_PROXY` | Список хостов-исключений через запятую, экспортируется как `NO_PROXY` (например `localhost,127.0.0.1,github.com`) | — |
| `ICODEX_TELEMETRY` | Opt-in telemetry mode: `off`, `otel`, `langfuse` или `both` | `off` |
| `ICODEX_OTEL_ENDPOINT` | Локальный OTel collector endpoint для metadata-only ops metrics/Grafana | `http://127.0.0.1:4318` |
| `ICODEX_OTEL_CREDENTIALS` | Опциональные `user:password` для OTel Basic Auth header (секрет) | — |
| `ICODEX_LANGFUSE_BASE_URL` | Local trusted Langfuse URL для full-fidelity capture в режимах `langfuse`/`both` | — |
| `ICODEX_LANGFUSE_PUBLIC_KEY` | Langfuse public key для local capture layer | — |
| `ICODEX_LANGFUSE_SECRET_KEY` | Langfuse secret key для local capture layer (секрет) | — |
| `ICODEX_CA_FIX` | Обход поломки TLS-доверия curl: `auto` — определяет CA-бандл, который OpenSSL не может декодировать, и направляет curl через отфильтрованную копию; `off` — выключает | `auto` |
| `ICODEX_CA_BUNDLE` | Явный CA-бандл для curl/OpenSSL — экспортируется как `CURL_CA_BUNDLE` / `SSL_CERT_FILE`; пропускает детект | — |
| `ICODEX_REPO` | GitHub-репозиторий, откуда качается бинарь codex | `openai/codex` |
| `ICODEX_LINK_DIR` | Каталог для симлинка `icodex` (ведущий `~/` раскрывается) | `~/.local/bin` |
| `ICODEX_UNAME_S` / `ICODEX_UNAME_M` | Принудительно задать платформу релиз-ассета вместо авто-определения через `uname` | авто |

`ICODEX_NO_PROXY` — это список исключений (стандартная семантика `NO_PROXY`), **не**
выключатель — чтобы пропустить прокси на один запуск, используйте флаг `--no-proxy`.
`./icodex.sh --proxy <url>` пишет `ICODEX_PROXY` в `.codex_config` (сохраняя другие ключи);
`./icodex.sh --clear` удаляет файл.

Если `ICODEX_PROXY` задан, но прокси недоступен, icodex предупреждает и — при интерактивном
запуске — спрашивает, продолжить ли без прокси (по умолчанию да) или выйти; без TTY
продолжает без прокси. `--no-proxy` пропускает прокси (и проверку) целиком.

### Телеметрия

`icodex` поддерживает opt-in hybrid telemetry через `.codex_config`.

- `ICODEX_TELEMETRY=otel` включает metadata-only OpenTelemetry для local collector/Grafana.
- `ICODEX_TELEMETRY=langfuse` включает full prompt/response capture в local trusted Langfuse.
- `ICODEX_TELEMETRY=both` включает оба канала.
- По умолчанию telemetry выключена: `ICODEX_TELEMETRY=off`.

Grafana/OTel не получает prompt/response bodies. Full capture разрешён только для local
trusted Langfuse URL. При `langfuse`/`both` icodex запускает local capture layer, ждёт
локальный provider URL от него и на время telemetry mode пишет managed Codex provider
route в `CODEX_HOME/config.toml`; при `off` managed telemetry regions удаляются. Секреты
OTel/Langfuse храните только в `.codex_config` или окружении, не в tracked files.

> Ключи `ICODEX_*`, зарезервированные за плагином iwiki (например `ICODEX_IWIKI_*`),
> намеренно игнорируются конфигом обёртки.

На хостах, где curl слинкован со сборкой OpenSSL, не умеющей декодировать все CA в системном
бандле доверия (например ALT Linux, чей бандл содержит GOST-корни, отвергаемые OpenSSL 1.1.1),
curl обрывает весь handshake с `x509_pubkey_decode: unsupported algorithm`, и любой HTTPS-вызов
падает. Сам codex не затронут (он использует rustls со встроенными корнями), но curl-подпроцессы
— да. На каждом запуске icodex определяет это локально (без сети), пишет отфильтрованную копию
бандла без GOST в `.codex-isolated/ca-trust/` и экспортирует `CURL_CA_BUNDLE` / `SSL_CERT_FILE`,
чтобы curl снова работал. Это идемпотентно (кеш по mtime исходного бандла), не трогает системный
trust и ничего не делает на здоровых хостах. Задайте `ICODEX_CA_BUNDLE`, чтобы форсировать
конкретный бандл, или `ICODEX_CA_FIX=off`, чтобы выключить.

### Режим запуска (`ICODEX_MODE`)

Один пресет задаёт песочницу, политику одобрения и профиль управляемых прав вместе:

| `ICODEX_MODE` | Песочница | Одобрение | Управляемые права | `.git` на запись |
|---------------|-----------|-----------|-------------------|------------------|
| `ro` | read-only | on-request | dev-safe | нет |
| `safe` | workspace-write | on-request | dev-safe | да |
| `full-ask` (по умолчанию) | danger-full-access | on-request | ssh-on-request | да |
| `full-auto` | danger-full-access | never (без запросов) | off | да |

`full-auto` — режим «полный, без остановок», эквивалент
`--dangerously-bypass-approvals-and-sandbox`. Точечные ключи `ICODEX_SANDBOX`,
`ICODEX_APPROVAL` и `ICODEX_PERMISSIONS` переопределяют отдельные поля пресета.

### Проверка доступа на запись в `.git`

В каждом **записываемом** режиме icodex выдаёт `".git/" = "write"` в таблице
`:workspace_roots` активного профиля управляемых прав. Это перекрывает read-only
ре-монт, который Codex применяет к `.git/` под `workspace-write`, поэтому `git commit`
работает изнутри песочницы. Именно этот грант создаёт разницу под `workspace-write`
(`safe`); под `danger-full-access` (`full-ask` / `full-auto`) `.git` записываем самой
песочницей, а под `read-only` (`ro`) ничего не записываемо независимо от гранта.

Чтобы проверить грант напрямую — без модели и без сети — выполните запись под той же
песочницей, что применяет Codex, против одноразового репозитория:

```bash
repo="$(mktemp -d)"; git -C "$repo" init -q
home="$(mktemp -d -p "$HOME")"
cp .codex-isolated/config.toml "$home/config.toml"
CODEX_HOME="$home" .codex-isolated/bin/codex sandbox -C "$repo" -P dev-safe --include-managed-config -- sh -c 'echo x > .git/probe && echo WROTE || echo DENIED'
rm -rf "$repo" "$home"
```

С штатным грантом `.git/` это печатает `WROTE`; удалите строку `".git/" = "write"` из
таблицы `:workspace_roots` профиля `dev-safe` — и та же команда напечатает `DENIED`.

> **Приоритет режима с `.codex_config`:** обёртка экспортирует каждый ключ `ICODEX_*`,
> распарсенный из `.codex_config`, поэтому ключ, закреплённый в файле, перекрывает
> одноимённую переменную окружения. Чтобы выбрать режим через окружение (например
> `ICODEX_MODE=safe ./icodex.sh`), убедитесь, что этот ключ не задан в `.codex_config`.

## Песочница и доверие

icodex **безопасен по умолчанию**: каждый запуск пишет эффективную песочницу в конфиг
`CODEX_HOME` проекта. Эффективная песочница разрешается от низшего к высшему приоритету:

1. **Пресет `ICODEX_MODE`** — режим по умолчанию `full-ask` задаёт `danger-full-access`;
   `safe` и `ro` задают `workspace-write` и `read-only` соответственно. См.
   [Режим запуска](#режим-запуска-icodex_mode).
2. **`ICODEX_SANDBOX`** — точечное переопределение только поля sandbox: `read-only`,
   `workspace-write` или `danger-full-access`. Некорректное значение отклоняется с ошибкой.
3. **Флаг `--full-access`** — форсирует `danger-full-access` на один запуск.

`danger-full-access` даёт полный доступ к файловой системе; icodex всегда печатает
предупреждение в stderr, когда он активен. icodex также **авто-доверяет** запущенному
проекту в его конфиге, поэтому Codex не перезапрашивает доверие на каждом запуске.

## Что хранится в git

Только **бинарь codex** скачивается по требованию (закреплён версией + sha256 в
коммиченном `.codex-lockfile.json`); всё остальное едет с репозиторием, поэтому клон готов
к работе офлайн, как только бинарь на месте:

- **Закоммичено** — курируемый шаблон конфига Codex под `.codex-isolated/`: `AGENTS.md`,
  `AGENTS.override.md`, **`config.toml`**, `rules/default.rules` и предустановленный
  **плагин Superpowers** — его скиллы (`.codex-isolated/skills/`, кроме управляемых codex
  `.system/`) и кеш плагина (`.codex-isolated/plugins/cache/*/superpowers/…`). У клона есть
  полный фреймворк скиллов **без установки плагина** — на `--install` качается только бинарь.
- **В git-ignore** — скачанный бинарь (`.codex-isolated/bin/`), секреты
  (`.codex-isolated/auth.json`, `.codex_config`) и всё рантайм-состояние по проектам под
  `.codex-homes/` (сессии, логи, `*.sqlite`).

Правило игнора `.codex-isolated/` — это белый список: игнорируется всё, кроме перечисленных
выше коммиченных файлов, поэтому секреты и рантайм-шум никогда не закоммитятся случайно.

> **Существующим пользователям со своим `config.toml`:** базовый `config.toml`
> отслеживается и работает как **шаблон** — он копируется в каждый `CODEX_HOME` проекта на
> первом запуске. Держите секреты в `.codex_config` или `auth.json`, никогда в `config.toml`.

## Что лежит в home проекта

Когда вы запускаете `icodex`, он собирает home проекта в `.codex-homes/<проект>-<хеш>/`.
Ничего тяжёлого не дублируется: home **ссылается** на общий склад `.codex-isolated/` для
всего, что одинаково во всех проектах, и держит **реальные приватные копии** только того,
что обязано отличаться от проекта к проекту.

| В home | Как подключено | Зачем |
|--------|----------------|-------|
| Скиллы (`skills/`) | симлинк на общий склад | встроенные скиллы (`context-awareness`, `git-workflow`, `html-report`, `intent`, `mermaid-obsidian`) одинаковы везде, поэтому их видит каждый проект; рядом Codex сам управляет своими системными скиллами `.system` |
| Правила команд (`rules/`) | симлинк | политика `rules/default.rules`, которая авто-одобряет безопасные команды (например `git`) и блокирует опасные (например `shutdown`), действует в каждом проекте |
| Плагины, логин, скрипты-хуки (`plugins/`, `auth.json`, `hooks/`) | симлинк | один общий кеш плагинов, один логин и один набор скриптов-хуков на все проекты |
| Глобальные указания (`AGENTS.md`) | копия, ресинк на каждом запуске | несёт инструкции из общего `AGENTS.md`; обновляется при каждом запуске, чтобы правки `.codex-isolated/AGENTS.md` доезжали до уже созданных home, не затирая опциональный блок caveman |
| Рантайм-конфиг (`config.toml`) | копируется один раз | каждый проект может расходиться — последующие запуски лишь переприменяют sandbox и доверие, и никогда не затирают ваши правки |
| Сессии, логи, sqlite | создаёт сам Codex, для каждого проекта | история изолирована — два репозитория никогда не делят состояние сессий |

Поскольку общие части — симлинки, правка скилла, правила или глобального `AGENTS.md` в
`.codex-isolated/` вступает в силу при **следующем запуске** каждого проекта — никаких копий
по проектам обновлять руками не нужно. Home, собранный до этой схемы, конвертируется
автоматически при следующем запуске (старая реальная папка `skills/` заменяется симлинком).

Две вещи намеренно остаются вне home: **бинарь** `codex` (запускается напрямую из общего
`bin/`) и **шаблон caveman** (рендерится в `AGENTS.md` на запуске только когда задан
`ICODEX_CAVEMAN_MODE` — см. [`docs/wiki/caveman.md`](wiki/caveman.md)).

## Краткий гид по конфигу Codex

icodex использует два файла конфига:

- `.codex_config` — локальные настройки обёртки: API-ключ, песочница, прокси, репозиторий
  установки, путь симлинка. Этот файл в git-ignore и это правильное место для секретов.
- `.codex-isolated/config.toml` — **шаблон** рантайм-настроек Codex: модель, песочница,
  одобрения, права, плагины, проекты и UI. Он копируется в `CODEX_HOME` каждого проекта
  (`.codex-homes/<id>/config.toml`) на первом запуске; последующие запуски лишь
  переуправляют `sandbox_mode` и доверие к проекту и никогда не затирают ваши правки копии
  проекта. Правьте шаблон, чтобы менять дефолты для *новых* home проектов.

Частые ключи `.codex-isolated/config.toml`:

| Ключ | Простое значение |
|------|------------------|
| `model` | Имя модели по умолчанию, используемой Codex |
| `model_reasoning_effort` | Уровень рассуждений, например `low`, `medium`, `high` |
| `model_provider` | Именованный провайдер из `[model_providers.<name>]` |
| `sandbox_mode` | Файловая песочница: `read-only`, `workspace-write` или `danger-full-access` |
| `approval_policy` | Когда Codex спрашивает перед командами: `untrusted`, `on-request`, `never`; `on-failure` устарел |
| `default_permissions` | Именованный профиль управляемых прав из `[permissions.<name>]` |
| `web_search` | Режим веб-поиска, используемый Codex |
| `bypass_hook_trust` | Разрешает доверенным встроенным хукам запускаться без интерактивного запроса доверия |
| `[marketplaces.*]` / `[plugins.*]` | Пути marketplace плагинов и включённые плагины |
| `[features]` | Флаги фич, например `multi_agent = true` |
| `[projects."<path>"]` | Настройки доверия к проекту (icodex авто-добавляет запущенный проект) |
| `[tui]` | Настройки терминального UI, например строка статуса |

Полезные пресеты безопасности запуска:

```toml
# Безопаснее на каждый день: пишем внутри workspace, спрашиваем при риске.
sandbox_mode = "workspace-write"
approval_policy = "on-request"
default_permissions = "dev-safe"

# Полный доступ к ФС, но всё ещё спрашиваем при рискованных действиях.
sandbox_mode = "danger-full-access"
approval_policy = "on-request"
default_permissions = "ssh-on-request"

# Без песочницы и без запросов на одобрение.
# Эквивалент: codex --dangerously-bypass-approvals-and-sandbox
sandbox_mode = "danger-full-access"
approval_policy = "never"
default_permissions = "ssh-on-request"
```

`default_permissions` — это не то же самое, что `sandbox_mode`. Он выбирает один из
именованных управляемых профилей ниже в том же TOML-файле, например `dev-safe` или
`ssh-on-request`. Эти профили описывают разрешённые файлы, запрещённые секреты, доступ к
сети и доступ по SSH. Они важнее всего, когда Codex работает с управляемыми правами или
`workspace-write`.

> `sandbox_mode` в шаблоне — это **стартовое** значение для нового home проекта; на каждом
> запуске icodex переприменяет эффективную песочницу (см. [Песочница и доверие](#песочница-и-доверие))
> в `config.toml` этого home.
