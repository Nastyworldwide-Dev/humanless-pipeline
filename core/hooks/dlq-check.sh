#!/bin/bash
# SessionStart hook — Auto-review DLQ on session start
# Counts DLQ entries, archives stale ones, triggers review-dlq skill if needed

# Source log-event if available
PIPELINE_DIR="$HOME/.claude/pipeline"
LOG_EVENT_SCRIPT="$PIPELINE_DIR/scripts/log-event.sh"
[ -f "$LOG_EVENT_SCRIPT" ] && source "$LOG_EVENT_SCRIPT" 2>/dev/null

# Provide a no-op log_event if not loaded
type log_event &>/dev/null || log_event() { :; }

DLQ_DIR="$PIPELINE_DIR/tasks/failed"
ARCHIVE_DIR="$DLQ_DIR/archive"
STALE_HOURS=72

# Skip if no DLQ directory
[ -d "$DLQ_DIR" ] || exit 0

# Archive entries older than 72 hours
mkdir -p "$ARCHIVE_DIR"
find "$DLQ_DIR" -maxdepth 1 -name "*.json" -type f -mmin +$((STALE_HOURS * 60)) -exec mv {} "$ARCHIVE_DIR/" \; 2>/dev/null

# Count remaining entries
DLQ_COUNT=$(find "$DLQ_DIR" -maxdepth 1 -name "*.json" -type f 2>/dev/null | wc -l)

if [ "$DLQ_COUNT" -gt 0 ]; then
  log_event "dlq-check" "failed" "{\"count\":$DLQ_COUNT}"
  if [ "$DLQ_COUNT" -gt 5 ]; then
    echo "{\"systemMessage\": \"MANDATORY HOOK: DLQ has $DLQ_COUNT unprocessed entries (threshold: 5). Invoke the review-dlq skill NOW to triage failures before starting new work.\"}"
  else
    echo "{\"systemMessage\": \"INFO: DLQ has $DLQ_COUNT unprocessed entries. Consider running /review-dlq to triage them.\"}"
  fi
else
  log_event "dlq-check" "passed" "{\"count\":0}"
fi

exit 0
