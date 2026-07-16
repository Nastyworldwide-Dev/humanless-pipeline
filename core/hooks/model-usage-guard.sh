#!/usr/bin/env bash
# model-usage-guard.sh
# UserPromptSubmit + PostToolUse(*) hook: proactive model-availability cutover.
#
# Polls the real Anthropic usage endpoint (/api/oauth/usage) and, when the top
# planning/advising tier is at/above the cutover threshold (default 98%), emits a
# systemMessage directing the Advisor to route ALL new planning/orchestration and
# agent spawns to the next-highest tier whose usage is still available.
#
# Advisory only (always exit 0) — it never blocks. The native `fallbackModel`
# cascade in settings.json handles the HARD limit (~100%); this hook is the
# proactive 98% layer for the delegated/spawned pipeline (the Advisor cannot
# hot-swap its OWN running model, but it CAN choose the model of every agent it
# spawns — that is what this directive drives).
#
# Env overrides (mainly for tests):
#   MODEL_USAGE_CUTOVER_PCT   threshold percent (default 98)
#   MODEL_USAGE_TTL           cache TTL seconds (default 60)
#   MODEL_USAGE_CACHE_FILE    cache path (default ~/.claude/.cache/oauth-usage.json)
#   MODEL_USAGE_NO_FETCH=1    never hit the network; use the cache as-is (tests)
set -euo pipefail

THRESHOLD="${MODEL_USAGE_CUTOVER_PCT:-98}"
TTL="${MODEL_USAGE_TTL:-60}"
CACHE_FILE="${MODEL_USAGE_CACHE_FILE:-$HOME/.claude/.cache/oauth-usage.json}"
CREDS="${MODEL_USAGE_CREDS:-$HOME/.claude/.credentials.json}"

# Planning/advising tiers, highest -> lowest. Left = model alias used when
# spawning agents; right = display_name as reported by the usage endpoint.
TIERS=("fable:Fable" "opus:Opus" "sonnet:Sonnet")

command -v jq >/dev/null 2>&1 || exit 0

# Drain stdin (hook event payload); we don't need its contents.
cat >/dev/null 2>&1 || true

mkdir -p "$(dirname "$CACHE_FILE")" 2>/dev/null || true

now=$(date +%s)
fresh=0
if [ -f "$CACHE_FILE" ]; then
  mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  [ $(( now - mtime )) -lt "$TTL" ] && fresh=1
fi

if [ "$fresh" -eq 0 ] && [ "${MODEL_USAGE_NO_FETCH:-0}" != "1" ]; then
  if [ -r "$CREDS" ]; then
    TOK=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS" 2>/dev/null || true)
    if [ -n "$TOK" ]; then
      resp=$(curl -sS -m 8 https://api.anthropic.com/api/oauth/usage \
               -H "Authorization: Bearer $TOK" \
               -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null || true)
      # Only overwrite the cache with a well-formed response.
      if printf '%s' "$resp" | jq -e '.limits' >/dev/null 2>&1; then
        printf '%s' "$resp" > "$CACHE_FILE"
      fi
    fi
  fi
fi

[ -s "$CACHE_FILE" ] || exit 0
jq -e '.limits' "$CACHE_FILE" >/dev/null 2>&1 || exit 0

# Effective % for a model display name = max percent across limits that apply to
# it: global limits (scope.model.display_name == null) plus that model's scoped
# limits.
tier_pct() {
  local name="$1" p
  p=$(jq -r --arg m "$name" '
        [ .limits[]
          | select(((.scope.model.display_name // null) == null)
                   or (.scope.model.display_name == $m))
          | .percent ] | (max // 0)
      ' "$CACHE_FILE" 2>/dev/null || echo 0)
  p="${p%.*}"
  [[ "$p" =~ ^[0-9]+$ ]] || p=0
  echo "$p"
}

top_name="${TIERS[0]##*:}"
top_pct=$(tier_pct "$top_name")

# Top tier still has headroom -> nothing to do.
[ "$top_pct" -lt "$THRESHOLD" ] && exit 0

# Top tier saturated: find the highest tier still under threshold.
recommended="" rec_name="" rec_pct=""
for t in "${TIERS[@]}"; do
  key="${t%%:*}"; name="${t##*:}"
  p=$(tier_pct "$name")
  if [ "$p" -lt "$THRESHOLD" ]; then
    recommended="$key"; rec_name="$name"; rec_pct="$p"; break
  fi
done

reset=$(jq -r --arg m "$top_name" \
  '[.limits[] | select(.scope.model.display_name == $m) | .resets_at] | (.[0] // "soon")' \
  "$CACHE_FILE" 2>/dev/null || echo "soon")

if [ -z "$recommended" ]; then
  msg="⚠️ MODEL-USAGE: every planning tier (fable/opus/sonnet) is ≥${THRESHOLD}% of its usage window. No higher-availability tier remains — the native fallbackModel cascade will switch on the hard limit. Consider pausing heavy orchestration until reset (${top_name} resets ${reset})."
else
  msg="⚠️ MODEL-USAGE CUTOVER — ${top_name} is at ${top_pct}% (≥${THRESHOLD}%) of its usage window (resets ${reset}). Route ALL new planning/orchestration and agent spawns to '${recommended}' (${rec_pct}% used) until ${top_name} resets: pass model:\"${recommended}\" on every Agent() spawn (planner/executor/etc.) and prefer '${recommended}' for your own reasoning. Do NOT spawn ${top_name}-pinned agents without the '${recommended}' override."
fi

jq -cn --arg m "$msg" '{systemMessage: $m}'
exit 0
