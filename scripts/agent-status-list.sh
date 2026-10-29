#!/bin/bash
# agent-status-list.sh — чтение статус-регистра агентов (РП-395), зеркало писца
# agent-status-report.sh.
#
# НАЗНАЧЕНИЕ: показать пилоту текущие статусы всех агентов своего контура.
# Шаблонный чтец (scripts/agent-dashboard.py) читает через облачный agent_status_list
# MCP-инструмент; этот скрипт — тот же degraded-путь, что и писец: прямое чтение из
# indicators-БД через INDICATORS_URL. Формат вывода и stale-пороги (15 мин / 2 ч)
# повторяют agent-dashboard.py, чтобы глаз пилота видел одну и ту же картину.
#
# Использование:
#   agent-status-list.sh              # человекочитаемая таблица
#   agent-status-list.sh --plain      # без цветов и иконок (логи, скрипты)
#
# Только чтение: ни одной записи в БД. Ошибки — в stderr, exit 0 (fail-safe).

PLAIN=""
[ "$1" = "--plain" ] && PLAIN="1"

SECRETS_DIR="${IWE_SECRETS_DIR:-$HOME/IWE/.secrets}"
NEON_ENV="$SECRETS_DIR/neon-urls.env"
UID_FILE="$SECRETS_DIR/pilot-user-id"

fail() { echo "agent-status-list: $1" >&2; exit 0; }

USER_ID="${IWE_PILOT_USER_ID:-}"
[ -z "$USER_ID" ] && [ -f "$UID_FILE" ] && USER_ID="$(tr -d '[:space:]' < "$UID_FILE")"
[ -z "$USER_ID" ] && fail "pilot user_id not found ($UID_FILE)"

INDICATORS_URL="${INDICATORS_URL:-}"
if [ -z "$INDICATORS_URL" ] && [ -f "$NEON_ENV" ]; then
  # shellcheck disable=SC1090
  set -a; . "$NEON_ENV"; set +a
fi
[ -z "${INDICATORS_URL:-}" ] && fail "INDICATORS_URL not found ($NEON_ENV)"

command -v psql >/dev/null 2>&1 || fail "psql not installed"
export PGCLIENTENCODING=UTF8

# Neon free засыпает при простое: первая попытка может упасть, вторая проходит.
ROWS=""
rc=1
for _ in 1 2; do
  if ROWS=$(psql "$INDICATORS_URL" -t -A -F'|' -v ON_ERROR_STOP=1 -v uid="$USER_ID" 2>/dev/null <<'SQL'
SELECT agent, session_id, status, coalesce(task, ''), coalesce(array_to_string(files, ', '), ''),
       extract(epoch FROM (now() - updated_at))::int
FROM agent_status
WHERE user_id = :'uid'::uuid
ORDER BY agent, session_id;
SQL
); then rc=0; break; fi
  sleep 3
done
[ "$rc" -ne 0 ] && fail "db read failed (база недоступна?)"

if [ -z "$ROWS" ]; then
  echo "Нет данных об агентах. Возможно, ни один агент ещё не отчитывался."
  exit 0
fi

# Иконки и русские названия — как в agent-dashboard.py шаблона.
icon()  { case "$1" in idle) echo "💤";; working) echo "🔧";; peer-session) echo "🤝";; blocked) echo "🚫";; *) echo "❓";; esac; }
name()  { case "$1" in idle) echo "свободен";; working) echo "работает";; peer-session) echo "peer-сессия";; blocked) echo "заблокирован";; *) echo "$1";; esac; }

[ -n "$PLAIN" ] || printf '\n═══ Агенты IWE [%s] ═══\n\n' "$(date +%H:%M)"
[ -n "$PLAIN" ] && echo "agent|session|status|task|files|age"

printf '%s\n' "$ROWS" | while IFS='|' read -r agent sid status task files age; do
  if [ -n "$PLAIN" ]; then
    printf '%s|%s|%s|%s|%s|%ss\n' "$agent" "$sid" "$status" "$task" "$files" "$age"
    continue
  fi
  stale=""
  if [ "$status" != "idle" ]; then
    if [ "$age" -gt 7200 ] 2>/dev/null; then
      stale="  [вероятно зависла: $((age / 3600))ч $(( (age % 3600) / 60 ))м назад]"
    elif [ "$age" -gt 900 ] 2>/dev/null; then
      stale="  [устарел: $((age / 60))м назад]"
    fi
  fi
  if [ "$age" -lt 60 ]; then when="сейчас";
  elif [ "$age" -lt 3600 ]; then when="$((age / 60))м назад";
  else when="$((age / 3600))ч $(( (age % 3600) / 60 ))м назад"; fi
  task_short=${task:0:60}; [ "${#task}" -gt 60 ] && task_short="$task_short…"
  printf '  %s %-11s %s  (%s, %s)%s\n' "$(icon "$status")" "$agent" "$task_short" "$(name "$status")" "$when" "$stale"
  [ -n "$files" ] && printf '     📄 %s\n' "${files:0:120}"
done

if [ -z "$PLAIN" ]; then
  echo
  echo "  💤 свободен   🔧 работает   🤝 peer-сессия   🚫 заблокирован"
  echo "  [устарел] — нет обновления >15 мин, [вероятно зависла] — >2 ч"
fi

exit 0
