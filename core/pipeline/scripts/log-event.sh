#!/bin/bash
# Shared pipeline event logger — source from any hook, call log_event()
# Usage: log_event <hook_name> <outcome> [metadata_json]
# Outcomes: spawned, blocked, skipped, passed, failed, error
# Appends one JSONL line to $HOME/.claude/pipeline/logs/pipeline-events.jsonl

PIPELINE_LOG="$HOME/.claude/pipeline/logs/pipeline-events.jsonl"

log_event() {
  local hook_name="${1:-unknown}"
  local outcome="${2:-unknown}"
  local metadata="${3:-{}}"
  local timestamp
  timestamp=$(date -Iseconds)

  # Ensure log dir exists
  mkdir -p "$(dirname "$PIPELINE_LOG")"

  # Append JSONL entry (atomic write via echo)
  echo "{\"ts\":\"$timestamp\",\"hook\":\"$hook_name\",\"outcome\":\"$outcome\",\"meta\":$metadata}" >> "$PIPELINE_LOG"

  # Log rotation: truncate if over 10,000 lines
  if [ -f "$PIPELINE_LOG" ]; then
    LINE_COUNT=$(wc -l < "$PIPELINE_LOG" 2>/dev/null || echo 0)
    if [ "$LINE_COUNT" -gt 10000 ]; then
      tail -5000 "$PIPELINE_LOG" > "${PIPELINE_LOG}.tmp" && mv "${PIPELINE_LOG}.tmp" "$PIPELINE_LOG"
    fi
  fi
}
