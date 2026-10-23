#!/usr/bin/env bash
# Regression coverage for check-status-legend.sh (WP-267 child of WP-217):
# the live WP-REGISTRY uses content-rich status cells («✅ done (23.10, W44)»,
# «🔄 in_progress (прогон 29.09 принят)»), and the detector used to compare the
# WHOLE CELL against the legend emoji set:
#   - I1 fired per unique cell text (~79 false positives);
#   - I2/I3 compared the whole cell to the terminal set (~51 false positives);
#   - a plain id with a struck-through NAME (done-no-strike, allowed by the
#     registry header since Day Close 06.10) was read as "active" even though
#     wp-sync-bundle.sh treats a strikethrough anywhere in the row as closed
#     (same semantics as issue #714 there);
#   - extract_legend_emojis never reset its column trackers per table and never
#     matched empty separator lines, so the «Домен»/Quick-links tables leaked
#     into the legend set (garbage legend report, false I1 passes).
# Each check below runs the real helper against an isolated fixture registry
# (mktemp + --registry) and asserts observable exit codes and report lines.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
HELPER="$ROOT/scripts/iwe-drift-helpers/check-status-legend.sh"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

pass_count=0
pass() { echo "  ✅ PASS: $*"; pass_count=$((pass_count + 1)); }
fail() { echo "  ❌ FAIL: $*" >&2; exit 1; }

[ -f "$HELPER" ] || fail "helper not found: $HELPER"

# ---------------------------------------------------------------------------
# Fixture 1: clean registry — content-rich cells must NOT drift.
# Covers: leading-marker extraction, done-no-strike (struck name, plain id),
# crossed id with terminal marker, decoy tables around the legend.
# ---------------------------------------------------------------------------
cat >"$TMP/clean.md" <<'EOF'
# WP-REGISTRY — fixture

| Статус | Расшифровка |
|--------|-------------|
| ✅ | done |
| 🔄 | in_progress |
| ⏳ | pending |
| 📦 | archived |
| ↗️ | merged в другой РП |

| Домен | Расшифровка |
|-------|-------------|
| IWE | инфраструктура |
| TL | операционка |

---

## Полный реестр

| # | Название | Статус | Приоритет | Домен |
|---|----------|--------|-----------|-------|
| 12 | ~~**Закрытый крестом id**~~ | ✅ done (23.10, W44) | ~~🔴~~ | TL |
| 34 | ~~Закрытый done-no-strike~~ | 📦 archived (superseded WP-12) | — | IWE |
| 56 | **Активный** | 🔄 in_progress (прогон 29.09 принят пилотом 06.10) | 🔴 | TL |
| 78 | Другой активный | ⏳ pending (ждёт РП-30) | 🟡 | ЛР |
EOF

echo "--- clean registry: content-rich status cells → no drift ---"
out=$(bash "$HELPER" --registry "$TMP/clean.md" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "exit 0 on clean fixture"
else
  fail "expected exit 0, got $rc. Output: $out"
fi
if printf '%s\n' "$out" | grep -q "undocumented status emoji (I1): 0"; then
  pass "I1 = 0 (markers, not whole cells, matched the legend)"
else
  fail "expected 'I1: 0' in summary. Output: $out"
fi
if printf '%s\n' "$out" | grep -q "format-compliance violations (I2+I3): 0"; then
  pass "I2+I3 = 0 (done-no-strike row and crossed-id row both accepted)"
else
  fail "expected 'I2+I3: 0' in summary. Output: $out"
fi
legend_block=$(printf '%s\n' "$out" | awk '/^```$/{f=!f; next} f')
if printf '%s\n' "$legend_block" | grep -qx "📦" \
   && ! printf '%s\n' "$legend_block" | grep -q "Домен"; then
  pass "legend block contains only the status table (no leak from «Домен»)"
else
  fail "legend block leaked foreign table rows: $legend_block"
fi

# ---------------------------------------------------------------------------
# Fixture 2: real violations — each invariant must fire on the MARKER.
# The decoy «Домен» table documents 🟡 — it must NOT silence the I1 on the
# status column (regression: non-legend tables leaked into the legend set).
# ---------------------------------------------------------------------------
cat >"$TMP/dirty.md" <<'EOF'
# WP-REGISTRY — fixture

| Статус | Расшифровка |
|--------|-------------|
| ✅ | done |
| 🔄 | in_progress |

| Домен | Расшифровка |
|-------|-------------|
| 🟡 | decoy: marker documented HERE must not count |

---

## Полный реестр

| # | Название | Статус | Приоритет |
|---|----------|--------|-----------|
| 10 | Активная строка с терминальным статусом | ✅ done 01.01 | 🔴 |
| 20 | ~~Закрытая строка с активным статусом~~ | 🔄 in_progress (забыли закрыть) | 🔴 |
| 30 | Строка с недокументированным маркером | 🟡 deferred | 🟡 |
EOF

echo "--- dirty registry: I1/I2/I3 fire on the marker ---"
out=$(bash "$HELPER" --registry "$TMP/dirty.md" --critical-only 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "exit 2 on dirty fixture"
else
  fail "expected exit 2, got $rc. Output: $out"
fi
if printf '%s\n' "$out" | grep -q "| I2 | active-row-with-terminal-status | WP-10 |"; then
  pass "I2 fires on plain row with terminal marker (marker, not whole cell)"
else
  fail "missing I2/WP-10 violation. Output: $out"
fi
if printf '%s\n' "$out" | grep -q "| I3 | terminal-row-with-active-status | WP-20 |"; then
  pass "I3 fires on struck row with active marker"
else
  fail "missing I3/WP-20 violation. Output: $out"
fi
if printf '%s\n' "$out" | grep -q "| I1 | undocumented-status | 🟡 |"; then
  pass "I1 fires on 🟡 even though a decoy non-legend table documents it"
else
  fail "missing I1/🟡 violation (legend leak regressed?). Output: $out"
fi

echo "--- locale independence: membership comparison is byte-based ---"
for loc in C C.UTF-8 en_US.UTF-8 ru_RU.UTF-8; do
  LC_ALL=$loc bash "$HELPER" --registry "$TMP/clean.md" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "LC_ALL=$loc: clean fixture stays green (4-byte emoji 📦/🟡 match the legend)"
  else
    fail "LC_ALL=$loc: expected exit 0, got $rc"
  fi
done

echo "check-status-legend marker parsing guard: $pass_count checks passed"
