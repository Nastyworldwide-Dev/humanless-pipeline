#!/bin/bash
# scoreboard.sh — render ~/.claude/pipeline/evals/results.jsonl as markdown.
# The baseline this prints is the yardstick every harness change re-runs
# against: green rate up / cost down = the change earned its keep.
set -u
RESULTS="${1:-$HOME/.claude/pipeline/evals/results.jsonl}"
[ -f "$RESULTS" ] || { echo "no results at $RESULTS"; exit 1; }

echo "## Eval scoreboard — $(date -u +%F)"
echo
echo "| task | stack | green | commits | turns | cost USD | mins | note |"
echo "|---|---|---|---|---|---|---|---|"
jq -r '[.task, .stack,
        (if .env_error then "ENV" elif .green then "✅" else "❌" end),
        (.commits|tostring), (.num_turns|tostring),
        (if .cost_usd then (.cost_usd*100|round/100|tostring) else "-" end),
        ((.duration_s/60)|round|tostring),
        (.env_error // "" | .[0:40])] | "| " + join(" | ") + " |"' "$RESULTS"
echo
TOTAL=$(jq -s 'map(select(.env_error == null)) | length' "$RESULTS")
GREENS=$(jq -s 'map(select(.env_error == null and .green)) | length' "$RESULTS")
COST=$(jq -s 'map(.cost_usd // 0) | add | .*100 | round / 100' "$RESULTS")
echo "**Green rate: ${GREENS}/${TOTAL} scoreable · total spend: \$${COST}** (ENV rows excluded from rate)"
