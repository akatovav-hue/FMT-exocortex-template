#!/bin/bash
# shellcheck disable=SC2155,SC2034  # local+assign pattern, ARTICLE used for logging
# ТНВЭД Classifier Agent Runner
# Сканирует inbox → подготавливает данные → классифицирует через Claude CLI
#
# Использование:
#   classifier.sh scan           # Сканировать inbox, обработать новые файлы
#   classifier.sh classify FILE  # Классифицировать конкретный файл

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROLE_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE="/Users/andrey_akatov/IWE"
INBOX_DIR="$WORKSPACE/DS-strategy/inbox/classifier"
OUTPUT_DIR="$WORKSPACE/DS-strategy/inbox/classifier/done"
PROMPTS_DIR="$ROLE_DIR/prompts"
LOG_DIR="/Users/andrey_akatov/logs/classifier"
CLAUDE_PATH="claude"
BATCH_SIZE=10  # артикулов за один вызов claude

mkdir -p "$LOG_DIR" "$INBOX_DIR" "$OUTPUT_DIR"

DATE=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/$DATE.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

classify_file() {
    local XLSX_FILE="$1"
    local BASENAME=$(basename "$XLSX_FILE" .xlsx)
    local TEMP_DIR="/tmp/classifier-$BASENAME-$$"

    log "=== Классификация: $XLSX_FILE ==="

    # 1. Подготовка данных
    log "Подготовка данных..."
    python3 "$SCRIPT_DIR/prepare-batch.py" "$XLSX_FILE" "$TEMP_DIR"

    local ARTICLES_FILE="$TEMP_DIR/articles.jsonl"
    local IMAGES_DIR="$TEMP_DIR/images"
    local TOTAL=$(wc -l < "$ARTICLES_FILE" | tr -d ' ')
    log "Артикулов: $TOTAL"

    # 2. Pass 1: batch текстовая классификация
    log "Pass 1: текстовая классификация..."
    local RESULTS_FILE="$TEMP_DIR/results.jsonl"
    local BATCH_NUM=0

    while IFS= read -r BATCH; do
        BATCH_NUM=$((BATCH_NUM + 1))
        log "  Batch $BATCH_NUM..."

        local PROMPT="Классифицируй эти товары. Данные в формате JSONL:

$BATCH

Для каждого артикула верни строку JSON с полями: article, tnved, customs_name, confidence, flags"

        $CLAUDE_PATH -p "$PROMPT" \
            --system-prompt-file "$PROMPTS_DIR/classify-batch.md" \
            --model haiku \
            --allowedTools "" \
            2>>"$LOG_FILE" >> "$RESULTS_FILE" || true

    done < <(split -l "$BATCH_SIZE" "$ARTICLES_FILE" /tmp/classifier-batch- && \
             for f in /tmp/classifier-batch-*; do cat "$f"; echo "---BATCH_END---"; done)

    # 3. Pass 2: верификация по фото (спорные позиции)
    log "Pass 2: верификация по фото..."
    local VERIFY_FILE="$TEMP_DIR/verify.jsonl"

    while IFS= read -r LINE; do
        local ARTICLE=$(echo "$LINE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('article',''))" 2>/dev/null)
        local IMG=$(echo "$LINE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('image_file',''))" 2>/dev/null)

        if [ -n "$IMG" ] && [ -f "$IMAGES_DIR/$IMG" ]; then
            local PROMPT="Верифицируй классификацию по фото.
Фото товара: $IMAGES_DIR/$IMG
Данные: $LINE
Прочитай фото через Read tool и сравни тип изделия с наименованием."

            $CLAUDE_PATH -p "$PROMPT" \
                --system-prompt-file "$PROMPTS_DIR/verify-photo.md" \
                --model haiku \
                --allowedTools "Read" \
                --allow-dangerously-skip-permissions \
                2>>"$LOG_FILE" >> "$VERIFY_FILE" || true
        fi
    done < "$ARTICLES_FILE"

    # 4. Результат
    log "Результаты: $RESULTS_FILE"
    if [ -f "$VERIFY_FILE" ]; then
        log "Верификация: $VERIFY_FILE"
    fi

    # 5. Копируем результат
    cp "$RESULTS_FILE" "$OUTPUT_DIR/${BASENAME}_results_${DATE}.jsonl"
    [ -f "$VERIFY_FILE" ] && cp "$VERIFY_FILE" "$OUTPUT_DIR/${BASENAME}_verify_${DATE}.jsonl"

    log "=== Готово: $BASENAME ==="

    # Cleanup
    rm -rf "$TEMP_DIR" /tmp/classifier-batch-*
}

scan_inbox() {
    log "Сканирование inbox: $INBOX_DIR"
    local COUNT=0

    for FILE in "$INBOX_DIR"/*.xlsx; do
        [ -f "$FILE" ] || continue
        local BASENAME=$(basename "$FILE")

        # Пропускаем уже обработанные
        if [ -f "$OUTPUT_DIR/${BASENAME%.xlsx}_results_${DATE}.jsonl" ]; then
            log "  Пропуск (уже обработан): $BASENAME"
            continue
        fi

        classify_file "$FILE"
        COUNT=$((COUNT + 1))
    done

    if [ "$COUNT" -eq 0 ]; then
        log "Нет новых файлов для обработки"
    else
        log "Обработано файлов: $COUNT"
    fi
}

# --- Main ---
case "${1:-scan}" in
    scan)
        scan_inbox
        ;;
    classify)
        if [ -z "$2" ]; then
            echo "Usage: $0 classify FILE.xlsx"
            exit 1
        fi
        classify_file "$2"
        ;;
    *)
        echo "Usage: $0 {scan|classify FILE}"
        exit 1
        ;;
esac
