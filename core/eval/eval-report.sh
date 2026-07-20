#!/bin/bash
# eval-report.sh — aggregate eval results + retro telemetry into the pipeline
# scoreboard: shots-to-green per revision label and the rerun-cause histogram.
# Emits report.md (human) and report.json (desktop Pipeline page / charts).
#
# Usage: eval-report.sh [results.jsonl] [tasks.csv] [out_dir]
set -u
RESULTS="${1:-$HOME/.claude/pipeline/eval/results.jsonl}"
TELEMETRY="${2:-$HOME/.claude/pipeline/telemetry/tasks.csv}"
OUT_DIR="${3:-$HOME/.claude/pipeline/eval}"
mkdir -p "$OUT_DIR"

[ -f "$RESULTS" ] || { echo "no results at $RESULTS" >&2; exit 1; }

# --- Per-label aggregates (median shots, pass rate, n) ---
LABELS_JSON=$(jq -s '
  group_by(.label) | map({
    label: .[0].label,
    n: length,
    pass_rate: ((map(select(.passed)) | length) / length * 100 | round),
    median_shots: (map(.shots) | sort | .[(length / 2 | floor)]),
    mean_shots: ((map(.shots) | add) / length * 10 | round / 10)
  })' "$RESULTS")

# --- Rerun-cause histogram from retro telemetry (cause=<x> on shots>=2 rows) ---
CAUSES_JSON="[]"
if [ -f "$TELEMETRY" ]; then
  CAUSES_JSON=$(grep -oE 'cause=[a-z+-]+' "$TELEMETRY" 2>/dev/null \
    | sed 's/^cause=//' | tr '+' '\n' | sort | uniq -c | sort -rn \
    | awk '{printf "{\"cause\": \"%s\", \"count\": %s}\n", $2, $1}' \
    | jq -s '.' 2>/dev/null || echo "[]")
fi

jq -n --argjson labels "$LABELS_JSON" --argjson causes "$CAUSES_JSON" \
  --arg generated "$(date -u +%FT%TZ)" \
  '{generated: $generated, revisions: $labels, rerun_causes: $causes}' \
  > "$OUT_DIR/report.json"

{
  echo "# Pipeline Eval Report"
  echo
  echo "Generated: $(date -u +%FT%TZ)"
  echo
  echo "## Shots-to-green by pipeline revision"
  echo
  echo "| Revision | Tasks | Median shots | Mean shots | Pass rate |"
  echo "|----------|-------|--------------|------------|-----------|"
  echo "$LABELS_JSON" | jq -r '.[] | "| \(.label) | \(.n) | \(.median_shots) | \(.mean_shots) | \(.pass_rate)% |"'
  echo
  echo "## Why reruns happened (retro telemetry)"
  echo
  if [ "$CAUSES_JSON" = "[]" ]; then
    echo "_No retro telemetry yet — rows accrue in $TELEMETRY as tasks complete._"
  else
    echo "| Cause | Count |"
    echo "|-------|-------|"
    echo "$CAUSES_JSON" | jq -r '.[] | "| \(.cause) | \(.count) |"'
  fi
  echo
  echo "_Target: median ≤ 2.0 shots. Every gate change lands with a before/after label in this table._"
} > "$OUT_DIR/report.md"

echo "[eval-report] wrote $OUT_DIR/report.md and report.json"
jq -r '.revisions[] | "  \(.label): median \(.median_shots) shots, \(.pass_rate)% pass (n=\(.n))"' "$OUT_DIR/report.json"
