# ADR-003: Template-sync контракт

**Дата:** 2026-04-19
**Статус:** accepted (реализовано в MVP)
**Связано:** ADR-001 (setup in template), ADR-002 (modular roles), WP-49

## Контекст

До 19.04.2026 в CLAUDE.md §9 было описано flow `авторский IWE → template-sync.sh → FMT`, но `template-sync.sh` не существовал. Автор фактически правил FMT напрямую, что противоречило собственному правилу. ADR-001 и ADR-002 ссылались на `template-sync.sh` как на существующий инструмент.

Параллельно обнаружены утечки в FMT:
- 8 хардкодов `tserentserenov` (чужой пользователь)
- `DS-IT-systems` (авторский бот-репо)
- `/Users/andrey_akatov/Github/` (устаревшая структура, теперь `/Users/andrey_akatov/IWE/`)
- 7 скриптов с `LOG_DIR="/Users/andrey_akatov/logs/..."` (должно быть `$HOME/logs/...`)

## Решение

Реализовать `template-sync.sh` как авторский инструмент в **корне IWE** (не в FMT), с декларативным manifest и валидацией через существующий `validate-template.sh`.

### Размещение

`scripts/template-sync/` в **корне авторского IWE** (не в FMT):
- `template-sync.sh` — основной скрипт (bash + yq)
- `sync-manifest.yaml` — декларативные правила
- `README.md` — документация
- `.backup/YYYY-MM-DD-HHMMSS/` — снапшоты FMT перед apply

**Обоснование (АрхГейт 2026-04-19, ЭМОГССБ):** Вариант A (`FMT/roles/synchronizer/`) создаёт циркулярную зависимость (скрипт sync'ит сам себя). Вариант C (отдельный репо) — преждевременен для ~50 правил. Вариант B (в корне) соответствует ADR-001 («авторские инструменты не нужны пользователю»).

### Направления синхронизации

| Режим | Направление | Когда |
|-------|-------------|-------|
| `--dry-run` | корень → FMT (preview) | Перед apply |
| `--apply` | корень → FMT | После правки автором |
| `--bootstrap <path>` | FMT → корень (one-time) | Для устаревших/отсутствующих файлов в корне |
| `--verify` | — | Post-sync validate-template.sh |
| `--rollback` | backup → FMT | Если sync сломал FMT |

### Manifest формат

```yaml
schema_version: 1
source_root: /Users/andrey_akatov/IWE
target_root: /Users/andrey_akatov/IWE/FMT-exocortex-template

replacements:
  - from: "akatov.av@gmail.com"
    to: "{{USER_EMAIL}}"
  - from: "Андрей Акатов"
    to: "{{USER_NAME}}"

rules:
  - source: .claude/skills/day-open/SKILL.md
    target: .claude/skills/day-open/SKILL.md
    mode: placeholder    # placeholder | strip-author | passthrough
```

### Плейсхолдеры

**НЕ заменяем** (setup.sh у пользователей делает substitute):
- `/Users/andrey_akatov/IWE` → `$WORKSPACE_DIR`
- `/Users/andrey_akatov` → `$HOME_DIR`
- `-Users-andrey_akatov-IWE` → `$CLAUDE_PROJECT_SLUG`

**Заменяем** (setup.sh не знает):
- `akatov.av@gmail.com` → `{{USER_EMAIL}}`
- `Андрей Акатов` → `{{USER_NAME}}`

### Защитные меры

1. **Abort on uncommitted FMT:** `--apply` требует `git status` FMT чистым (иначе смешается с авторскими правками).
2. **Backup перед apply:** `.backup/<timestamp>/FMT-exocortex-template` — быстрый rollback.
3. **Post-apply validate:** `validate-template.sh` должен вернуть exit 0 (иначе sync fail).
4. **Bootstrap requires --force для diff:** если файл в корне отличается от FMT — ручное подтверждение.

## Последствия

### Положительные

- **Контракт §9 CLAUDE.md теперь выполним** — flow реально работает.
- **FMT чист от utечек** — `validate-template.sh` ALL 6 CHECKS PASSED.
- **Новые пользователи могут безопасно клонировать FMT** — `setup.sh` сработает.
- **Манифест декларативен** — новые правила добавляются без правки кода.

### Отрицательные / риски

- **Bash + yq зависимости** — вне macOS (Linux без brew) нужно `apt install yq`.
- **Корневой IWE — не git repo** — template-sync.sh сам не версионируется. Риск потери локально.
  Митигация: периодически копировать `scripts/template-sync/` в DS-agent-workspace или в DS-strategy/exocortex/.
- **Manifest растёт с добавлением правил** — при >200 правил возможен performance hit. Мониторить.

### Нейтральные

- Появился новый Service Clause: `LOCAL.SC.003` в `extensions/service-clause-template-sync.md` (авторский scope).
- validate-template.sh уточнён: Check 2 различает foreign paths (FAIL) от `/Users/andrey_akatov/` плейсхолдеров (INFO).

## Не-решения (отложено)

- **CI-интеграция** (GitHub Action проверяет что FMT синхронизирован с корнем) — после того как корневой IWE станет git repo.
- **Автогенерация manifest из корня** — не MVP. Автор ведёт manifest вручную.
- **Двунаправленный sync** (корень ↔ FMT) — не нужен. `--bootstrap` покрывает разовый FMT→корень.

## Ссылки

- [WP-49 Инфраструктура синхронизации IWE↔FMT](../../../DS-strategy/inbox/WP-49-iwe-fmt-alignment.md)
- [LOCAL.SC.003 Service Clause](../../../extensions/service-clause-template-sync.md)
- [scripts/template-sync/README.md](../../../scripts/template-sync/README.md)
- [ADR-001: Setup in template](ADR-001-setup-in-template.md)
- [ADR-002: Modular roles](ADR-002-modular-roles.md)
