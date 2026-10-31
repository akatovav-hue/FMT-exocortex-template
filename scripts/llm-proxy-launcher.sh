#!/bin/bash
# llm-proxy-launcher.sh — обёртка запуска локального LLM-адаптера (IWE scheduler diagnostics, 10.09.2026)
#
# ЛОКАЛЬНАЯ ПОДМЕНА канонической версии (канон делает exec llm-proxy.py — dead file,
# superseded by auth-gateway.py, issue #504; OpenRouter-секретов на этом хосте нет).
# Адаптер эмулирует контракт прокси на 127.0.0.1 и ходит в Kimi API ключом из
# конфигурации Kimi Code CLI. Дрейф зафиксирован: .before-adapter — каноническая копия.
# При обновлении FMT, если upstream изменит этот файл, подмену нужно восстановить.
set -euo pipefail

IWE_WS="${IWE_WORKSPACE:-$HOME/IWE}"
PORT="${1:-18765}"
exec python3 "$IWE_WS/${IWE_GOVERNANCE_REPO:-DS-strategy}/scripts/llm-adapter.py" --port "$PORT"
