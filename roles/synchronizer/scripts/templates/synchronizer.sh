#!/bin/bash
# shellcheck disable=SC2034  # Variables used indirectly by caller (notify.sh sources this file)
# Шаблон уведомлений: Синхронизатор (R8)
# Вызывается из notify.sh через source

LOG_DIR="/Users/andrey_akatov/logs/synchronizer"
DATE=$(date +%Y-%m-%d)

build_message() {
    local scenario="$1"

    case "$scenario" in
        "code-scan")
            local log_file="$LOG_DIR/code-scan-$DATE.log"

            if [ ! -f "$log_file" ]; then
                echo ""
                return
            fi

            local latest_run
            latest_run=$(awk '/=== Code Scan Started ===/{buf=""} {buf=buf"\n"$0} END{print buf}' "$log_file" 2>/dev/null)

            local found
            found=$(echo "$latest_run" | grep -c 'FOUND:' 2>/dev/null || echo "0")
            local skipped
            skipped=$(echo "$latest_run" | grep -c 'SKIP:' 2>/dev/null || echo "0")

            local repo_list
            repo_list=$(echo "$latest_run" | grep 'FOUND:' 2>/dev/null | sed 's/.*FOUND: /  /' || echo "")

            printf "<b>🔄 Code Scan</b>\n\n"
            printf "📅 %s\n\n" "$DATE"
            printf "Репо с коммитами: %s\n" "$found"
            printf "Без изменений: %s\n\n" "$skipped"

            if [ "$found" -gt 0 ]; then
                printf "<b>Репо:</b>\n%s" "$repo_list"
            fi
            ;;

        "health-alert")
            local state_dir="$HOME/.local/state/exocortex"
            local issues=""
            local failed_tasks=""

            # Check critical tasks
            if [ ! -f "$state_dir/synchronizer-code-scan-$DATE" ]; then
                failed_tasks+="code-scan, "
            fi
            if [ ! -f "$state_dir/strategist-morning-$DATE" ] && (( 10#$(date +%H) >= 6 )); then
                failed_tasks+="strategist morning, "
            fi

            if [ -z "$failed_tasks" ]; then
                echo ""
                return
            fi

            failed_tasks="${failed_tasks%, }"

            printf "<b>🔴 Health Alert</b>\n\n"
            printf "📅 %s\n\n" "$DATE"
            printf "<b>Не запустились:</b> %s\n\n" "$failed_tasks"
            printf "Проверь логи:\n"
            printf "<code>cat ~/logs/synchronizer/launchd-scheduler.log | tail -20</code>\n\n"
            printf "Ручной запуск:\n"
            printf "<code>cd ~/IWE/FMT-exocortex-template && bash roles/synchronizer/scripts/scheduler.sh dispatch</code>"
            ;;

        *)
            echo ""
            ;;
    esac
}

build_buttons() {
    echo '[]'
}
