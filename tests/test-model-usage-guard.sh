#!/usr/bin/env bash
# Functional test for model-usage-guard.sh — the proactive 98% cutover hook.
#
# Feeds fixture usage-endpoint payloads via a cache file (MODEL_USAGE_NO_FETCH=1
# so no network) and asserts the emitted directive picks the correct tier.
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_DIR/core/hooks/model-usage-guard.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CACHE="$TMP/usage.json"

fail=0
pass() { echo "  PASS: $1"; }
die()  { echo "  FAIL: $1"; fail=1; }

# limit helper -> build a payload with global weekly_all + a Fable/Opus/Sonnet scope
mk() { # $1 weekly_all  $2 fable  $3 opus  $4 sonnet
  cat > "$CACHE" <<JSON
{"limits":[
 {"kind":"session","percent":10,"severity":"normal","is_active":false,"scope":null,"resets_at":"2026-07-16T06:00:00Z"},
 {"kind":"weekly_all","percent":$1,"severity":"normal","is_active":false,"scope":null,"resets_at":"2026-07-20T12:00:00Z"},
 {"kind":"weekly_scoped","percent":$2,"severity":"critical","is_active":true,"scope":{"model":{"id":null,"display_name":"Fable"}},"resets_at":"2026-07-20T12:00:00Z"},
 {"kind":"weekly_scoped","percent":$3,"severity":"normal","is_active":true,"scope":{"model":{"id":null,"display_name":"Opus"}},"resets_at":"2026-07-20T12:00:00Z"},
 {"kind":"weekly_scoped","percent":$4,"severity":"normal","is_active":true,"scope":{"model":{"id":null,"display_name":"Sonnet"}},"resets_at":"2026-07-20T12:00:00Z"}
]}
JSON
}

# emit the decoded systemMessage text (empty when the guard stays silent)
run() { MODEL_USAGE_NO_FETCH=1 MODEL_USAGE_CACHE_FILE="$CACHE" bash "$GUARD" </dev/null 2>/dev/null | jq -r '.systemMessage // empty' 2>/dev/null; }

# 1. Fable below threshold -> no directive at all.
mk 58 95 20 5
msg=$(run)
[ -z "$msg" ] && pass "Fable 95% < 98% => silent" || die "expected silence, got: $msg"

# 2. Fable at 98% -> cut over to opus.
mk 58 98 20 5
msg=$(run)
if echo "$msg" | grep -q 'model:"opus"'; then pass "Fable 98% => recommend opus"; else die "expected opus, got: $msg"; fi

# 3. Fable AND opus saturated -> cut over to sonnet.
mk 58 99 98 5
msg=$(run)
if echo "$msg" | grep -q 'model:"sonnet"'; then pass "Fable+Opus saturated => recommend sonnet"; else die "expected sonnet, got: $msg"; fi

# 4. Global weekly_all >= 98 -> every tier blocked, no fallback helps.
mk 99 50 50 50
msg=$(run)
if echo "$msg" | grep -qi "no higher-availability tier\|every planning tier"; then pass "global cap => no-fallback message"; else die "expected no-fallback msg, got: $msg"; fi

# 5. Custom threshold via env (90) with Fable at 92 -> cut over.
mk 58 92 20 5
msg=$(MODEL_USAGE_NO_FETCH=1 MODEL_USAGE_CACHE_FILE="$CACHE" MODEL_USAGE_CUTOVER_PCT=90 bash "$GUARD" </dev/null 2>/dev/null | jq -r '.systemMessage // empty')
if echo "$msg" | grep -q 'model:"opus"'; then pass "threshold=90, Fable 92% => opus"; else die "expected opus at threshold 90, got: $msg"; fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS: model-usage-guard"; exit 0; else echo "FAILURES in model-usage-guard"; exit 1; fi
