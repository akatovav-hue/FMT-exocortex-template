#!/usr/bin/env bash
# test_issue_1281_telegram_delivery_switch.sh — regression for issue #1281.
#
# Diagnosis 2026-10-23 (IWE scheduler): TG delivery was never configured by the
# pilot, and every night each notification burned network-wait + 3 curl retries
# into DNS-failure noise ("[telegram] FAIL after 3 attempts" x3+ per night).
# Fix: telegram.sh reads the switch
#   notify.channels.telegram.enabled
# from ${IWE_TELEGRAM_CONFIG:-${IWE_WORKSPACE}/.iwe-runtime/roles/synchronizer/config.yaml}.
# Default (key absent / false / config missing) = delivery SKIPPED: one stderr
# line, exit 0, no credential loading, no curl. enabled: true = the delivery
# code path runs (checked here up to the credential gate, without network).
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
LIB="$ROOT/scripts/lib/telegram.sh"

fail=0
ok()   { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=$((fail + 1)); }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# send <config> [secrets] — sources the lib and sends; prints stdout+stderr,
# returns telegram_send's exit code (set -uo pipefail, не -e: ожидаем и rc!=0).
send() { # <config> [secrets]
    local rc=0
    IWE_TELEGRAM_CONFIG="$1" TG_SECRETS_FILE="${2:-$T/no-secrets}" bash -c ". '$LIB'; telegram_send 'msg'" 2>&1 || rc=$?
    return "$rc"
}

mkcfg() { # <name> <telegram-block-content>
    mkdir -p "$T/$1"
    printf 'notify:\n  channels:\n    telegram:\n%s\n' "$2" > "$T/$1/config.yaml"
}

# --- 1. enabled: false → пропуск, rc=0, одна строка, без обращения к creds/curl ---
mkcfg off '      enabled: false
      env_file: x'
OUT=$(send "$T/off/config.yaml"); RC=$?
[ "$RC" -eq 0 ] && ok "enabled: false → rc=0" || bad "enabled: false → rc=0 (rc=$RC)"
grep -q 'доставка отключена конфигом' <<<"$OUT" && ok "enabled: false → понятная строка-пропуск" || bad "enabled: false → понятная строка-пропуск: $OUT"
! grep -q 'TELEGRAM_BOT_TOKEN' <<<"$OUT" && ok "enabled: false → creds не читаются" || bad "enabled: false → creds не читаются"

# --- 2. ключа enabled нет → тоже выключено (default off) ---
mkcfg nokey '      env_file: x'
OUT=$(send "$T/nokey/config.yaml"); RC=$?
[ "$RC" -eq 0 ] && grep -q 'доставка отключена конфигом' <<<"$OUT" \
    && ok "ключа enabled нет → выключено по умолчанию" || bad "ключа enabled нет → выключено по умолчанию: $OUT"

# --- 3. конфиг отсутствует → выключено (default off) ---
OUT=$(send "$T/missing/config.yaml"); RC=$?
[ "$RC" -eq 0 ] && grep -q 'доставка отключена конфигом' <<<"$OUT" \
    && ok "конфиг отсутствует → выключено по умолчанию" || bad "конфиг отсутствует → выключено по умолчанию: $OUT"

# --- 4. enabled: true → ветка доставки открывается (упирается в creds, не в switch) ---
mkcfg on '      enabled: true
      env_file: x'
OUT=$(send "$T/on/config.yaml"); RC=$?
if [ "$RC" -ne 0 ] && grep -q 'TELEGRAM_BOT_TOKEN или TELEGRAM_CHAT_ID не заданы' <<<"$OUT"; then
    ok "enabled: true → доставка пытается отправить (упёрлась в creds, не в switch)"
else
    bad "enabled: true → доставка пытается отправить: rc=$RC $OUT"
fi
! grep -q 'доставка отключена конфигом' <<<"$OUT" && ok "enabled: true → без строки-пропуска" || bad "enabled: true → без строки-пропуска"

# --- 5. enabled: true в чужом блоке (schedules) не включает доставку ---
mkcfg foreign '      enabled: false
      env_file: x'
printf 'schedules:\n  x:\n    enabled: true\n' >> "$T/foreign/config.yaml"
OUT=$(send "$T/foreign/config.yaml"); RC=$?
[ "$RC" -eq 0 ] && grep -q 'доставка отключена конфигом' <<<"$OUT" \
    && ok "enabled: true вне блока telegram не включает доставку" || bad "enabled: true вне блока telegram не включает доставку: $OUT"

if [ "$fail" -gt 0 ]; then
    echo "FAIL: $fail проверок упало"
    exit 1
fi
echo "PASS: telegram-выключатель читает notify.channels.telegram.enabled (issue #1281)"
