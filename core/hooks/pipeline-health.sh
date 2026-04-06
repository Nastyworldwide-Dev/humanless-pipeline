#!/bin/bash
# SessionStart hook — zero-infra pipeline health check
# Checks: infrastructure, active tasks, stale tasks, DLQ, circuit breaker

# Source log-event if available
PIPELINE_DIR="$HOME/.claude/pipeline"
LOG_EVENT_SCRIPT="$PIPELINE_DIR/scripts/log-event.sh"
[ -f "$LOG_EVENT_SCRIPT" ] && source "$LOG_EVENT_SCRIPT" 2>/dev/null

# Provide a no-op log_event if not loaded
type log_event &>/dev/null || log_event() { :; }

TASKS_DIR="$PIPELINE_DIR/tasks"
DEBOUNCE_DIR="$PIPELINE_DIR/debounce"
MESSAGES=""

# --- Infrastructure health (optional external health check) ---
HEALTH_SCRIPT="$HOME/.claude/hooks/health-check.sh"
if [ -x "$HEALTH_SCRIPT" ]; then
  HEALTH_OUTPUT=$(bash "$HEALTH_SCRIPT" 2>&1)
  if [ $? -ne 0 ]; then
    MESSAGES="${MESSAGES}Health check failed: ${HEALTH_OUTPUT}. Fix infrastructure issues before proceeding. "
  fi
fi

# --- Hook wiring self-test (optional) ---
SELF_TEST="$HOME/.claude/hooks/self-test.sh"
if [ -x "$SELF_TEST" ]; then
  SELF_TEST_OUTPUT=$(bash "$SELF_TEST" 2>&1)
  if echo "$SELF_TEST_OUTPUT" | grep -q "FAIL"; then
    MESSAGES="${MESSAGES}Hook self-test issues: $(echo "$SELF_TEST_OUTPUT" | grep 'FAIL' | head -3 | tr '\n' '; '). "
  fi
fi

# --- Check for active tasks (resume after hibernation) ---
ACTIVE_COUNT=$(find "$TASKS_DIR/active" -name '*.json' -type f 2>/dev/null | wc -l)
if [ "$ACTIVE_COUNT" -gt 0 ]; then
  ACTIVE_FILE=$(ls -t "$TASKS_DIR/active/"*.json 2>/dev/null | head -1)
  if [ -n "$ACTIVE_FILE" ] && command -v jq &>/dev/null; then
    TASK_ID=$(jq -r '.id // "unknown"' "$ACTIVE_FILE" 2>/dev/null)
    TASK_TITLE=$(jq -r '.title // "unknown"' "$ACTIVE_FILE" 2>/dev/null)
    PIPELINE_NODE=$(jq -r '.pipeline_node // "unknown"' "$ACTIVE_FILE" 2>/dev/null)
    STARTED_AT=$(jq -r '.started_at // ""' "$ACTIVE_FILE" 2>/dev/null)

    # Stale detection: active for >2 hours
    if [ -n "$STARTED_AT" ]; then
      STARTED_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null || echo 0)
      NOW_EPOCH=$(date +%s)
      AGE_HOURS=$(( (NOW_EPOCH - STARTED_EPOCH) / 3600 ))
      if [ "$AGE_HOURS" -ge 2 ]; then
        # Move stale task to failed
        mkdir -p "$TASKS_DIR/failed"
        jq '.status = "failed" | .error_log = "Stale: active for '"$AGE_HOURS"' hours without completion"' "$ACTIVE_FILE" > "$TASKS_DIR/failed/$(basename "$ACTIVE_FILE")" 2>/dev/null
        rm -f "$ACTIVE_FILE"
        MESSAGES="${MESSAGES}Stale task '$TASK_TITLE' (${AGE_HOURS}h) moved to DLQ. "
        ACTIVE_COUNT=0
      fi
    fi

    if [ "$ACTIVE_COUNT" -gt 0 ]; then
      MESSAGES="${MESSAGES}Resuming task '$TASK_TITLE' [$TASK_ID] at pipeline node: $PIPELINE_NODE. "
    fi
  fi
fi

# --- Backlog count ---
BACKLOG_COUNT=$(find "$TASKS_DIR/backlog" -name '*.json' -type f 2>/dev/null | wc -l)

# --- DLQ count ---
DLQ_COUNT=$(find "$TASKS_DIR/failed" -name '*.json' -type f 2>/dev/null | wc -l)

# --- Circuit breaker state ---
CIRCUIT_FILE="$PIPELINE_DIR/circuit/fix-loop.json"
CIRCUIT_MSG=""
if [ -f "$CIRCUIT_FILE" ] && command -v jq &>/dev/null; then
  CYCLE_COUNT=$(jq -r '.cycle_count // 0' "$CIRCUIT_FILE" 2>/dev/null)
  if [ "$CYCLE_COUNT" -gt 0 ]; then
    CIRCUIT_BRANCH=$(jq -r '.branch // "unknown"' "$CIRCUIT_FILE" 2>/dev/null)
    CIRCUIT_MSG=" Circuit breaker: ${CYCLE_COUNT} cycles on branch $CIRCUIT_BRANCH."
  fi
fi

# --- Clean stale debounce files (>24h) ---
if [ -d "$DEBOUNCE_DIR" ]; then
  find "$DEBOUNCE_DIR" -type f -mmin +1440 -delete 2>/dev/null
fi

# --- Learnings summary ---
LEARNINGS_COUNT=0
if [ -f "$PIPELINE_DIR/learnings/learnings.jsonl" ]; then
  LEARNINGS_COUNT=$(wc -l < "$PIPELINE_DIR/learnings/learnings.jsonl" 2>/dev/null || echo 0)
fi

# --- Build status line ---
STATUS="Pipeline: ${ACTIVE_COUNT} active, ${BACKLOG_COUNT} queued, ${DLQ_COUNT} in DLQ, ${LEARNINGS_COUNT} learnings.${CIRCUIT_MSG}"

# --- Log and emit ---
if [ -n "$MESSAGES" ]; then
  log_event "pipeline-health" "info" '{"active":'"$ACTIVE_COUNT"',"backlog":'"$BACKLOG_COUNT"',"dlq":'"$DLQ_COUNT"'}'
  echo "{\"systemMessage\": \"${MESSAGES}${STATUS}\"}"
else
  log_event "pipeline-health" "passed" '{"active":'"$ACTIVE_COUNT"',"backlog":'"$BACKLOG_COUNT"',"dlq":'"$DLQ_COUNT"'}'
  # Only emit if there's something worth reporting
  if [ "$ACTIVE_COUNT" -gt 0 ] || [ "$BACKLOG_COUNT" -gt 0 ] || [ "$DLQ_COUNT" -gt 3 ]; then
    echo "{\"systemMessage\": \"${STATUS}\"}"
  fi
fi

exit 0
