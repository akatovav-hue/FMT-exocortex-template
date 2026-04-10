#!/bin/bash
# Установка классификатора ТНВЭД
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="/Users/andrey_akatov/IWE"
INBOX_DIR="$WORKSPACE/DS-strategy/inbox/classifier"
PLIST_SRC="$SCRIPT_DIR/scripts/launchd/com.iwe.classifier.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.iwe.classifier.plist"

echo "=== Установка классификатора ТНВЭД ==="

# 1. Создать inbox директорию
mkdir -p "$INBOX_DIR" "$INBOX_DIR/done"
echo "✅ Inbox: $INBOX_DIR"

# 2. Проверить зависимости
if ! python3 -c "import openpyxl" 2>/dev/null; then
    echo "⚠️  openpyxl не установлен. Установите: pip3 install openpyxl"
fi

# 3. Создать директорию для логов
mkdir -p "$HOME/logs/classifier"

# 4. Установить launchd agent
if [ -f "$PLIST_DST" ]; then
    launchctl unload "$PLIST_DST" 2>/dev/null || true
fi
cp "$PLIST_SRC" "$PLIST_DST"
launchctl load "$PLIST_DST"
echo "✅ LaunchAgent установлен (5:00 ежедневно)"

echo ""
echo "Использование:"
echo "  Положить xlsx в: $INBOX_DIR/"
echo "  Ручной запуск:   bash $SCRIPT_DIR/scripts/classifier.sh classify FILE.xlsx"
echo "  Автоматически:   каждый день в 5:00"
echo ""
echo "✅ Готово!"
