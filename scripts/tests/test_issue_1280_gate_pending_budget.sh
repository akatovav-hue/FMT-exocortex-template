#!/usr/bin/env bash
# test_issue_1280_gate_pending_budget.sh — regression for issue #1280.
#
# Root cause (IWE scheduler diagnosis 2026-10-23): day-open-scaffold.sh leaves
# «Бюджет дня» as a <!-- PENDING: budget ... --> comment and day-open-llm-fill.py
# does not guarantee the gate's '~Xч РП / ~Yч физ' format, so even a GREEN
# canonical Day Open run was uncommittable — validate-staged-artifacts.sh
# blocked every staged DayPlan on «бюджет не в формате» / «мультипликатор не
# найден». Fix: the gate now distinguishes an UNFILLED slot (PENDING comment
# still in the budget line → WARN, commit allowed) from a FILLED-WRONG budget
# (→ block, as before). This test drives real git commits:
#   1. PENDING budget line → commit passes, WARN names the skipped checks;
#   2. budget filled in a free-form format → commit blocked (both errors);
#   3. budget filled in the strict gate format → commit passes (no WARN).
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
ok()   { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=$((fail + 1)); }

# --- Каркас: workspace/FMT-exocortex-template/scripts + governance-репо ---
# (тот же fixture-контракт, что test_issue_544_staged_precommit.sh)
WS="$TMP/ws"
mkdir -p "$WS/FMT-exocortex-template/scripts"
cp "$ROOT/scripts/validate-staged-artifacts.sh" "$WS/FMT-exocortex-template/scripts/"
GOV="$WS/DS-strategy"
mkdir -p "$GOV/.githooks" "$GOV/current"
cp "$ROOT/seed/strategy/.githooks/pre-commit" "$GOV/.githooks/pre-commit"
chmod +x "$GOV/.githooks/pre-commit"
cp "$ROOT/scripts/pre-commit-secret-scan.sh" "$WS/FMT-exocortex-template/scripts/"
chmod +x "$WS/FMT-exocortex-template/scripts/pre-commit-secret-scan.sh"
mkdir -p "$GOV/.claude/hooks"
cp "$ROOT/.claude/hooks/secret-bypass-lib.sh" "$GOV/.claude/hooks/secret-bypass-lib.sh"
cp "$ROOT/.claude/hooks/secret-bypass-analyzer.py" "$GOV/.claude/hooks/secret-bypass-analyzer.py"
git -C "$GOV" init -q
git -C "$GOV" config user.email test@test && git -C "$GOV" config user.name test
git -C "$GOV" config core.hooksPath .githooks
export IWE_SCRIPTS="$WS/FMT-exocortex-template/scripts"
export IWE_WORKSPACE="$WS"
export IWE_ROOT="$WS"
echo "init" > "$GOV/README.md"
git -C "$GOV" add README.md && git -C "$GOV" commit -qm init

# base_dayplan <path> <budget-line>: валидный DayPlan, где меняется только строка бюджета
base_dayplan() { # <path> <budget-line>
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<EOF
# DayPlan 2026-10-24
## План на сегодня
| Время | РП |
|-------|----|
| 10:00 | WP-1280 |
## Календарь
| Время | Событие |
|-------|---------|
| 11:00 | Встреча |
## IWE за ночь
всё зелёное
## Разбор заметок
нет
## Итоги вчера
сделано
$2
Carry-over: нет
EOF
}

# --- 1. PENDING-бюджет scaffold'а → коммит проходит, WARN о пропущенных проверках ---
base_dayplan "$GOV/current/DayPlan 2026-10-24.md" \
    '**Бюджет дня:** <!-- PENDING: budget — посчитать после плана. -->'
if (cd "$GOV" && git add "current/DayPlan 2026-10-24.md" && git commit -qm "pending-budget") >"$TMP/c1.err" 2>&1; then
    ok "PENDING-бюджет: коммит разрешён"
else
    bad "PENDING-бюджет: коммит разрешён"
    cat "$TMP/c1.err"
fi
grep -q 'остался PENDING' "$TMP/c1.err" \
    && ok "WARN называет незаполненный слот" \
    || bad "WARN называет незаполненный слот"

# --- 2. Заполнено не в формате (free-form, как пишет LLM Fill) → блок ---
git -C "$GOV" rm -q "current/DayPlan 2026-10-24.md"
git -C "$GOV" commit -qm "cleanup" --allow-empty
base_dayplan "$GOV/current/DayPlan 2026-10-24.md" \
    '**Бюджет дня:** сумма budget_h из JSON = **11.5–15.5 ч**'
if (cd "$GOV" && git add "current/DayPlan 2026-10-24.md" && git commit -qm "freeform-budget") >"$TMP/c2.err" 2>&1; then
    bad "free-form бюджет заблокирован"
else
    ok "free-form бюджет заблокирован"
fi
grep -q 'бюджет дня не в формате' "$TMP/c2.err" \
    && ok "разбор называет ошибку формата бюджета" \
    || bad "разбор называет ошибку формата бюджета"
grep -q 'мультипликатор не найден' "$TMP/c2.err" \
    && ok "разбор называет отсутствующий мультипликатор" \
    || bad "разбор называет отсутствующий мультипликатор"
grep -q 'PROTOCOL ARTIFACT VALIDATION FAILED' "$TMP/c2.err" \
    && ok "блок с человекочитаемым разбором" \
    || bad "блок с человекочитаемым разбором"

# --- 3. Строгий формат (тот, что проходит в проде: '~Xh РП / ~Yh физ / ~N.Nx') → проходит ---
git -C "$GOV" reset -q
rm -f "$GOV/current/DayPlan 2026-10-24.md"
base_dayplan "$GOV/current/DayPlan 2026-10-24.md" \
    '**Бюджет дня:** ~10h РП / ~7h физ / Плановый мультипликатор ~1.4x'
if (cd "$GOV" && git add "current/DayPlan 2026-10-24.md" && git commit -qm "strict-budget") >"$TMP/c3.err" 2>&1; then
    ok "строгий формат бюджета проходит"
else
    bad "строгий формат бюджета проходит"
    cat "$TMP/c3.err"
fi

if [ "$fail" -gt 0 ]; then
    echo "FAIL: $fail проверок упало"
    exit 1
fi
echo "PASS: gate различает PENDING-слот (warn) и заполненное-не-в-формате (block) (issue #1280)"
