# Маршрутизация знаний

> **Source-of-truth** для всех промптов KE.
> При добавлении нового Pack'а — обновить ТОЛЬКО этот файл.
> Все промпты читают маршрутизацию отсюда.

---

## 1. Pack-репо по домену

> Добавь свои Pack'и в эту таблицу. Пример:

| Домен | Pack | Префикс | Путь |
|-------|------|---------|------|
| _Твой домен (напр. Machine Learning)_ | _PACK-my-domain_ | _MD_ | _{{WORKSPACE_DIR}}/PACK-my-domain/pack/my-domain/_ |

<!-- Удали пример выше и добавь свои Pack'и. Формат:
| Домен (ключевые слова) | Имя Pack-репо | Короткий префикс (2-3 буквы) | Путь к pack/ директории |
-->

## 2. Директории по типу знания

| Тип | Код | Директория в Pack | Формат файла |
|-----|-----|-------------------|-------------|
| Доменная сущность | `entity` | `02-domain-entities/` | Отдельный файл |
| Различение | `distinction` | `01-domain-contract/01B-distinctions.md` | Секция в файле |
| Метод | `method` | `03-methods/` | Отдельный файл |
| Рабочий продукт | `wp` | `04-work-products/` | Отдельный файл |
| Failure mode | `fm` | `05-failure-modes/` | Отдельный файл |
| Характеристика | `chr` | `06-characteristics/` | Отдельный файл |
| SoTA-аннотация | `sota` | `08-sota/` | Отдельный файл |
| Правило (глобальное) | `rule` | `{{WORKSPACE_DIR}}/CLAUDE.md` | Строки |
| Правило (локальное) | `rule` | `<repo>/CLAUDE.md` | Строки |
| Правило (урок) | `rule` | `memory/<topic>.md` | Строки |

## 3. Именование файлов

**Конвенция:** `{PREFIX}.{TYPE}.{NNN}-{slug}.md`

| Компонент | Источник | Пример |
|-----------|----------|--------|
| `PREFIX` | Колонка «Префикс» из таблицы 1 | `MD`, `DP`, `PP` |
| `TYPE` | Код типа (AISYS, METHOD, FM, WP, CHR, SOTA, ...) | `METHOD` |
| `NNN` | max(существующий) + 1 | `002` |
| `slug` | kebab-case из названия | `handler-per-state` |

## 4. Тест маршрутизации

Для каждого кандидата:

1. **Домен?** → определи Pack по таблице 1
2. **Тип знания?** → определи директорию по таблице 2
3. **MCP-проверка:** `knowledge_search("тема кандидата")` → нет ли уже в базе?
4. **Проверка bounded context:** Прочитай `00-pack-manifest.md` целевого Pack'а — попадает ли кандидат в scope?
5. **Если не попадает ни в один Pack** → предложи defer и уточни у пользователя

## 4a. Pre-write checks (NEW 2026-05-15, обязательные)

> Извлечены из 3 insights apply-captures session 2026-05-15. Если хотя бы один check fail — изменить target_path / id / target_file прежде чем фиксировать в отчёте.

### 4a.1 Cross-Pack duplicate grep

Прежде чем создать новый файл / секцию:

```bash
# grep по ключевому тезису (3-5 уникальных слов) по ВСЕМ Pack-* репо
grep -rin "ключевой термин" $WORKSPACE_DIR/Pack-*/ $WORKSPACE_DIR/PACK-*/ 2>/dev/null
```

Если найдено existing entity — это **duplicate / extension candidate**, не new. Возможные действия:
- Reject как duplicate (если содержательно совпадает)
- Extension (добавить evidence/section к существующей entity)
- Альтернативный target_path (тематически более правильный файл)

**Incident reference:** «SOTA-верификация ментора» предложен в `06-management-methods.md`, но уже существовал в `13-laputin-framework.md §4a.1` (incident 2026-04-22). См. `inbox/feedback-log.md`.

### 4a.2 Pending-id collision check

Прежде чем зафиксировать ID (MIGR.M.NNN / OPS.FM.NNN / DP.D.NNN):

```bash
# claimed ids = (existing files) ∪ (pending reports already proposed)
existing=$(ls $PACK_DIR/{category}/ | grep -oE '{PREFIX}\.{TYPE}\.[0-9]+' | sort -u)
pending=$(grep -hE '{PREFIX}\.{TYPE}\.[0-9]+' $GOVERNANCE_REPO/inbox/extraction-reports/*.md 2>/dev/null | grep -oE '{PREFIX}\.{TYPE}\.[0-9]+' | sort -u)
claimed=$(echo "$existing $pending" | tr ' ' '\n' | sort -u)
# next free = max(claimed) + 1 ИЛИ первый gap
```

Если id уже claimed — взять next free. Это критично при параллельных sub-runs одного дня (extractor может запускаться 2-3 раза за день launchd-ом).

**Incident reference:** MIGR.M.015 claimed двумя reports одновременно (2026-05-14-inbox-check.md и 2026-05-14-inbox-check-3.md). См. `inbox/feedback-log.md`.

### 4a.3 Canonical-vs-legacy routing (Pack-operations specific)

Pack-operations после Phase 2 refactor (14.05.2026) имеет hybrid structure. Правило выбора target_path:

| Тип кандидата | Target |
|---------------|--------|
| Новый `failure-mode` (entity-level) | canonical `05-failure-modes/OPS.FM.NNN-*.md` |
| Новый `distinction` (structural insight) | canonical `06-distinctions/OPS.D.NNN-*.md` |
| Новый `method` (entity-level) | canonical `03-methods/OPS.M.NNN-*.md` |
| Новая `role` (entity-level) | canonical `08-roles/OPS.R.NNN-*.md` |
| Подпункт §9.X decision principle (1-2 параграфа) | legacy `06-management-methods.md` |
| Подпункт принципа Лапутина | legacy `13-laputin-framework.md` |

**Правило выбора:** entity-уровень (большая formalization, frontmatter, structure) → canonical. Короткое правило-принцип под последовательную нумерацию → legacy thematic.

**Incident reference:** 2026-05-03 R2 предложил Compliance-decay → `08-compliance.md` (legacy); R15 пересдвинул в `OPS.FM.041` (canonical). Аналогично Бойло-noticer → `OPS.D.043`. См. `inbox/feedback-log.md`.

## 5. DS Routing (реализационное знание)

> Реализационное знание (вендор, стек, деплой, конфигурация) → DS-репо, **не Pack**.
> Один pipeline KE → два выхода: domain → Pack (§1-4), implementation → DS docs/ (§5).

| Признак | Куда маршрутизировать |
|---------|----------------------|
| Используется в другом проекте/контексте? **Да** | → Pack (доменное) |
| Привязано к конкретному стеку/вендору? **Да** | → DS docs/ (реализационное) |
| Описывает «что» и «почему» (архитектурный паттерн)? | → Pack |
| Описывает «как именно» (конфигурация, deployment)? | → DS docs/ |

### DS-репо по системам

> Добавь свои DS-репо в эту таблицу. Пример:

| Система | DS-репо | Путь к docs/ |
|---------|--------|-------------|
| _Мой бот_ | _your-org/my-bot_ | _{{WORKSPACE_DIR}}/your-org/my-bot/docs/_ |

<!-- Удали пример и добавь свои DS-репо -->

### Директории в DS docs/

| Тип реализационного знания | Директория | Формат |
|---------------------------|-----------|--------|
| Сценарий использования | `docs/scenarios/` | Отдельный файл |
| Процесс / алгоритм | `docs/processes/` | Отдельный файл |
| Схема данных | `docs/data/` | Отдельный файл |
| Архитектурное решение (стек, интеграция) | `implementation.md` в C.IT-Platform | Секция в файле |

### Формализация DS-кандидатов

DS-кандидаты **не требуют** frontmatter с trust/epistemic_stage (в отличие от Pack). Формат:

```markdown
# {Название сценария/процесса}

## Описание
{Что делает}

## Шаги / Алгоритм
{Как работает}

## Связи
- Pack: [{ID}](path) — доменное основание
- Код: `{module/file}` — реализация
```

## 6. Feedback (обратная связь)

При reject/defer — записать причину в `config/feedback-log.md`.
При повторном inbox-check — прочитать feedback-log и не предлагать аналогичные кандидаты.

---

*Последнее обновление: {{сегодняшняя дата}}*
