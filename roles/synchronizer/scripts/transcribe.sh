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
MODEL="${WHISPER_MODEL:-$HOME/.local/share/whisper-cpp/models/ggml-large-v3-turbo.bin}"
WHISPER_CLI="/usr/local/bin/whisper-cli"
FFMPEG="/usr/local/bin/ffmpeg"
EXTENSIONS="m4a mp4 wav mp3 webm"
LOG_DIR="/Users/andrey_akatov/logs/synchronizer"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [transcribe] $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [transcribe] $1" >> "$LOG_DIR/transcribe-$(date +%Y-%m-%d).log" 2>/dev/null || true
}

# Check dependencies
if [ ! -f "$WHISPER_CLI" ]; then
    log "ERROR: whisper-cli not found at $WHISPER_CLI"
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    log "ERROR: model not found at $MODEL. Download: curl -L -o $MODEL https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
    exit 1
fi

if [ ! -f "$FFMPEG" ]; then
    log "ERROR: ffmpeg not found at $FFMPEG"
    exit 1
fi

log "=== Transcribe Started ==="

# Scan for audio files
found=0
processed=0

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
            continue
        fi

        log "TRANSCRIBING: $basename_file"
        touch "$processing_file"

        # Convert to WAV 16kHz mono (whisper-cpp requirement)
        wav_tmp="/tmp/whisper_$(date +%s).wav"
        if ! "$FFMPEG" -i "$audio_file" -ar 16000 -ac 1 -c:a pcm_s16le "$wav_tmp" -y -loglevel error 2>&1; then
            log "ERROR: ffmpeg conversion failed for $basename_file"
            rm -f "$processing_file" "$wav_tmp"
            continue
        fi

        # Run whisper-cpp
        if "$WHISPER_CLI" -m "$MODEL" -f "$wav_tmp" -l ru --output-txt -of "${audio_file%.*}" 2>&1 | tail -3; then
            log "DONE: $basename_file → ${basename_file%.*}.txt"
            processed=$((processed + 1))
        else
            log "ERROR: whisper-cli failed for $basename_file"
        fi

        # Cleanup
        rm -f "$processing_file" "$wav_tmp"

    done < <(find "$INBOX_DIR" -maxdepth 2 -name "*.$ext" -print0 2>/dev/null)
done

log "=== Transcribe Completed: $found found, $processed transcribed ==="
