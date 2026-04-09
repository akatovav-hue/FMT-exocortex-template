#!/bin/bash
# shellcheck disable=SC2034  # Variables may be used by caller
# transcribe.sh — автоматическая транскрипция аудио в inbox
#
# Сканирует inbox/ на аудиофайлы, транскрибирует через whisper-cpp.
# Три маркера состояния:
#   file.m4a                       → новый → транскрибировать
#   file.m4a + file.m4a.processing → в работе → пропустить
#   file.m4a + file.txt            → готов → пропустить
#
# Использование:
#   transcribe.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INBOX_DIR="/Users/andrey_akatov/IWE/DS-strategy/inbox"
EXTENSIONS="m4a mp4 wav mp3 webm"
# Транскрипция через Buzz (GUI) — скрипт только детектирует и уведомляет
LOG_DIR="/Users/andrey_akatov/logs/synchronizer"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [transcribe] $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [transcribe] $1" >> "$LOG_DIR/transcribe-$(date +%Y-%m-%d).log" 2>/dev/null || true
}

# No CLI dependencies needed — Buzz handles transcription

log "=== Transcribe Started ==="

# Scan for audio files
found=0
pending_files=()

for ext in $EXTENSIONS; do
    while IFS= read -r -d '' audio_file; do
        found=$((found + 1))
        basename_file="$(basename "$audio_file")"
        dir_file="$(dirname "$audio_file")"
        txt_file="${audio_file%.*}.txt"
        processing_file="${audio_file}.processing"

        # Skip if already processed
        if [ -f "$txt_file" ]; then
            log "SKIP (done): $basename_file"
            continue
        fi

        # Skip if currently processing
        if [ -f "$processing_file" ]; then
            # Check if stale (>2 hours)
            if [ "$(find "$processing_file" -mmin +120 2>/dev/null)" ]; then
                log "WARN: stale .processing marker (>2h): $basename_file — removing"
                rm -f "$processing_file"
            else
                log "SKIP (in progress): $basename_file"
                continue
            fi
        fi

        if [ "$DRY_RUN" = true ]; then
            log "DRY RUN: would transcribe $basename_file"
            pending_files+=("$basename_file")
            continue
        fi

        pending_files+=("$basename_file")
        log "PENDING: $basename_file (открой Buzz для транскрипции)"

    done < <(find "$INBOX_DIR" -maxdepth 2 -name "*.$ext" -print0 2>/dev/null)
done

pending_count=${#pending_files[@]}
log "=== Transcribe Completed: $found found, $pending_count pending ==="

# Notify via Telegram if there are pending files
if [ "$pending_count" -gt 0 ] && [ "$DRY_RUN" = false ]; then
    file_list=$(printf '• %s\n' "${pending_files[@]}")
    "$SCRIPT_DIR/notify.sh" synchronizer audio-pending 2>/dev/null || log "WARN: notification failed"
fi
