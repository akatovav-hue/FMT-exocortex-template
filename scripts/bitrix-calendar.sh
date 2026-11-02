#!/usr/bin/env bash
# bitrix-calendar.sh — детерминированный источник календаря Bitrix24 для DayPlan/WeekPlan.
# see WP-318 (DS-strategy/inbox/WP-318): контур планировщика переведён на Kimi,
# claude-специфичный MCP-коннектор календаря недоступен — решение пилота 02.11:
# календарь берём из Битрикса через incoming webhook (REST: calendar.event.get).
#
# Контракт вывода — как у server-calendar.sh (WP-283): готовая markdown-секция
# «Календарь» для DayPlan/WeekPlan. Потребители (day-open-preflight.sh,
# day-open-scaffold.sh, ручные вызовы) встраивают stdout как есть.
#
# Требует (по порядку, первый найденный wins):
#   env: B24_DEFAULT_WEBHOOK (incoming webhook с scope calendar)
#   файл ~/.secrets/b24-webhook: либо сырой URL в первой строке,
#   либо строка B24_DEFAULT_WEBHOOK=<url>
#   env-файл с B24_DEFAULT_WEBHOOK=<url> (только извлечение строки, файл
#   не исполняется): путь из env B24_SECRETS_FILE, затем
#   <корень мастерской>/.secrets/bitrix24.env (тот же файл, что читают
#   bitrix-mirror push/pull — РП-68), затем ~/.secrets/bitrix24.env
# Чей календарь: по умолчанию владелец webhook'а (user.current),
# переопределение: env B24_CALENDAR_OWNER_ID (числовой id пользователя).
#
# Использование:
#   bash bitrix-calendar.sh YYYY-MM-DD
#   bash bitrix-calendar.sh --week [YYYY-MM-DD]
#
# На любом раннем выходе (нет webhook, сеть, пустой ответ) печатает секцию-
# заглушку «Календарь: ожидает подключения» с причиной — принцип server-calendar.sh
# «всегда рендерится», чтобы downstream не падал на пустом stdout.

set -uo pipefail

SCRIPT_SOURCE_VERSION=1

MODE="day"
TARGET_DATE=""
for arg in "$@"; do
  case "$arg" in
    --week) MODE="week" ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) TARGET_DATE="$arg" ;;
    *) ;; # CONFIG_PATH и прочие совместимые позиционные аргументы игнорируем
  esac
done
[ -n "$TARGET_DATE" ] || TARGET_DATE=$(date +%F)

# --- webhook resolution (env beats file, как в extractor.sh для токена) ---
WEBHOOK="${B24_DEFAULT_WEBHOOK:-}"
SECRET_FILE="$HOME/.secrets/b24-webhook"
if [ -z "$WEBHOOK" ] && [ -f "$SECRET_FILE" ]; then
  WEBHOOK=$(head -n 1 "$SECRET_FILE" | tr -d '[:space:]')
  case "$WEBHOOK" in
    B24_DEFAULT_WEBHOOK=*) WEBHOOK="${WEBHOOK#B24_DEFAULT_WEBHOOK=}" ;;
  esac
  WEBHOOK=$(printf '%s' "$WEBHOOK" | tr -d "\"'")
fi

# источник 3: env-файл зеркала Битрикса — строка B24_DEFAULT_WEBHOOK=<url>
# извлекается grep'ом, файл целиком не исполняется (M4 secret hygiene)
if [ -z "$WEBHOOK" ]; then
  for envfile in "${B24_SECRETS_FILE:-}" \
                 "$(cd "$(dirname "$0")/../.." && pwd)/.secrets/bitrix24.env" \
                 "$HOME/.secrets/bitrix24.env"; do
    [ -n "$envfile" ] && [ -f "$envfile" ] || continue
    line=$(grep -E '^[[:space:]]*(export[[:space:]]+)?B24_DEFAULT_WEBHOOK=' "$envfile" | tail -n 1)
    WEBHOOK="${line#*=}"
    WEBHOOK="${WEBHOOK//[[:space:]]/}"
    WEBHOOK="${WEBHOOK//\"/}"
    WEBHOOK=$(printf '%s' "$WEBHOOK" | tr -d "'")
    [ -n "$WEBHOOK" ] && break
  done
fi

render_pending() {
  local reason="$1"
  cat <<EOF
## Календарь

> ⏳ PENDING: Календарь Битрикс24 ожидает подключения: $reason
> Где взять webhook: env B24_DEFAULT_WEBHOOK, файл ~/.secrets/b24-webhook
> (первая строка) или B24_DEFAULT_WEBHOOK в <корень мастерской>/.secrets/bitrix24.env
> (файл зеркала Битрикса, scope должен включать «Календарь»).
EOF
}

if [ -z "$WEBHOOK" ]; then
  render_pending "webhook не задан (нет env B24_DEFAULT_WEBHOOK и файла ~/.secrets/b24-webhook)"
  exit 0
fi
case "$WEBHOOK" in
  http://*|https://*) ;;
  *)
    render_pending "webhook не похож на URL (проверьте ~/.secrets/b24-webhook)"
    exit 0
    ;;
esac

# --- окно запроса ---
if [ "$MODE" = "week" ]; then
  FROM="$TARGET_DATE"
  TO=$(date -d "$TARGET_DATE +6 days" +%F 2>/dev/null || date -v+6d -j -f %F "$TARGET_DATE" +%F 2>/dev/null || echo "$TARGET_DATE")
  TITLE="Календарь недели ($FROM — $TO)"
else
  FROM="$TARGET_DATE"
  TO="$TARGET_DATE"
  TITLE="Календарь ($FROM)"
fi

# --- чей календарь: по умолчанию — владелец webhook'а (user.current),
# переопределение: env B24_CALENDAR_OWNER_ID ---
OWNER_ID="${B24_CALENDAR_OWNER_ID:-}"
if [ -z "$OWNER_ID" ]; then
  ME=$(curl -fsS -m 20 "${WEBHOOK%/}/user.current" 2>/dev/null) || ME=""
  OWNER_ID=$(printf '%s' "$ME" | grep -oE '"ID":"[0-9]+"' | head -n 1 | grep -oE '[0-9]+')
fi
OWNER_ARGS=()
[ -n "$OWNER_ID" ] && OWNER_ARGS=(--data-urlencode "ownerId=$OWNER_ID")

# --- запрос ---
RESPONSE=$(curl -fsS -m 20 -G "${WEBHOOK%/}/calendar.event.get" \
  --data-urlencode "type=user" \
  "${OWNER_ARGS[@]}" \
  --data-urlencode "from=$FROM" \
  --data-urlencode "to=$TO" 2>/dev/null)
if [ -z "$RESPONSE" ]; then
  render_pending "запрос calendar.event.get не удался (сеть/токен/webhook — проверьте scope «Календарь»)"
  exit 0
fi

PY3="${PYTHON3:-}"
if [ -z "$PY3" ]; then
  PY3=$(bash "$(dirname "$0")/../.claude/lib/find-python3.sh" 2>/dev/null) || PY3=""
fi
[ -n "$PY3" ] || { render_pending "python3 не найден"; exit 0; }

PYTHONUTF8=1 PYTHONIOENCODING=utf-8 TITLE="$TITLE" FROM="$FROM" TO="$TO" RESPONSE="$RESPONSE" MODE="$MODE" "$PY3" - <<'PYEOF'
import json, os, re, sys

title = os.environ["TITLE"]; mode = os.environ["MODE"]
try:
    payload = json.loads(os.environ["RESPONSE"])
except json.JSONDecodeError:
    print(f"## Календарь\n\n> ⏳ Битрикс24 вернул не-JSON — проверьте webhook.\n"); sys.exit(0)

if not isinstance(payload, dict) or "result" not in payload:
    error = (payload or {}).get("error_description") or (payload or {}).get("error") or "пустой ответ"
    print(f"## Календарь\n\n> ⏳ Битрикс24: {error}\n"); sys.exit(0)

events = payload["result"] or []
strip = lambda h: re.sub(r"<[^>]+>", "", h or "").strip()

rows = []
for e in events:
    name = strip(e.get("NAME") or e.get("name") or "")
    if not name: continue
    df = (e.get("DATE_FROM") or e.get("date_from") or "")[:16]
    dt = (e.get("DATE_TO") or e.get("date_to") or "")[:16]
    loc = strip(e.get("LOCATION") or e.get("location") or "")
    if loc.startswith("calendar_"): loc = ""  # служебный id переговорки, не место
    day = df[:10]
    time_s = ""
    if e.get("DT_SKIP_TIME") == "Y":
        when = "весь день"
    else:
        time_s = df[11:16] if len(df) >= 16 else ""
        time_e = dt[11:16] if len(dt) >= 16 else ""
        when = f"{time_s}–{time_e}".strip("–") if time_s else "весь день"
    # ключ сортировки: события на весь день — в начале дня
    rows.append((day, time_s or "00:00", when, name, loc))

rows.sort()
# day-режим: Битрикс вместе с реальными вхождениями возвращает повторяющиеся
# события с датой начала исходной серии (за пределами запрошенного дня) —
# показываем только вхождения запрошенного дня (события, переходящие на
# полночь, при этом отсекаются — сознательное упрощение для day-plan).
# DATE_FROM у Битрикса «DD.MM.YYYY», запрос — ISO «YYYY-MM-DD»: сравниваем
# после конвертации.
if mode != "week":
    def to_iso(dmy):
        p = dmy.split(".")
        return f"{p[2]}-{p[1]}-{p[0]}" if len(p) == 3 and len(dmy) == 10 else dmy
    rows = [r for r in rows if to_iso(r[0]) == os.environ["FROM"]]
# «✅» — маркер успешного ответа для day-open-preflight.sh (контракт server-calendar.sh)
print(f"## {title} ✅\n")
if not rows:
    print("> Нет событий.\n"); sys.exit(0)
if mode == "week":
    cur = None
    for day, _, when, name, loc in rows:
        if day != cur:
            cur = day; print(f"**{day}**")
        loc_s = f" — {loc}" if loc else ""
        print(f"- {when} {name}{loc_s}")
        print()
else:
    for _, _, when, name, loc in rows:
        loc_s = f" — {loc}" if loc else ""
        print(f"- {when} {name}{loc_s}")
    print()
PYEOF
