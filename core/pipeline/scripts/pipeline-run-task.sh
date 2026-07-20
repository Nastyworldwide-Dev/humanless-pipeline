#!/bin/bash
# pipeline-run-task.sh — headless autonomous task runner.
# Picks the oldest non-parked backlog task and runs it through the full
# pipeline in a headless claude session with PIPELINE_AUTONOMOUS=1 exported —
# the signal every gate (grill-me, plan-approve, requirement-interpreter,
# new-feature) uses to switch to its autonomous variant.
#
# Usage: pipeline-run-task.sh [--dry-run]
# Cron example (one task per half hour):
#   */30 * * * * $HOME/.claude/bin/pipeline-run-task.sh >> $HOME/.claude/pipeline/telemetry/runner.log 2>&1
set -u

TASKS_DIR="$HOME/.claude/pipeline/tasks"
LOG_DIR="$HOME/.claude/pipeline/telemetry"
mkdir -p "$TASKS_DIR/backlog" "$TASKS_DIR/running" "$TASKS_DIR/done" "$TASKS_DIR/failed" "$LOG_DIR"

log() { echo "[runner $(date -u +%FT%TZ)] $*"; }

# --- Pick the oldest backlog task that isn't parked ---
NEXT=""
for f in $(ls -1tr "$TASKS_DIR/backlog"/task-*.md 2>/dev/null); do
  grep -qE '^status:[[:space:]]*parked' "$f" && continue
  NEXT="$f"
  break
done

if [ -z "$NEXT" ]; then
  log "no runnable backlog task (parked tasks wait for answers)"
  exit 0
fi

TASK_ID=$(basename "$NEXT" .md)
TASK_BODY=$(awk 'flag; /^---$/ && NR>1 {flag=1}' "$NEXT")
REPO=$(grep -oE '^repo:[[:space:]]*.*' "$NEXT" | sed 's/^repo:[[:space:]]*//' || true)
NEEDS_CLARIFY=$(grep -qE '^needs_clarify:[[:space:]]*true' "$NEXT" && echo true || echo false)
WORKDIR="${REPO:-$HOME}"
[ -d "$WORKDIR" ] || WORKDIR="$HOME"

if [ "${1:-}" = "--dry-run" ]; then
  log "would run $TASK_ID in $WORKDIR (needs_clarify=$NEEDS_CLARIFY)"
  exit 0
fi

# Single-flight: never run two autonomous tasks at once
LOCK="$TASKS_DIR/.runner.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  log "another runner is active — skipping"
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

RUNNING="$TASKS_DIR/running/$TASK_ID.md"
mv "$NEXT" "$RUNNING"
sed -i 's/^status:.*/status: running/' "$RUNNING"
log "starting $TASK_ID in $WORKDIR"

CLARIFY_PREFIX=""
[ "$NEEDS_CLARIFY" = "true" ] && CLARIFY_PREFIX="This task was flagged needs_clarify. START with /grill-me Autonomous Mode (self-grill ledger) before anything else. "

PROMPT="${CLARIFY_PREFIX}Run this task through the full humanless pipeline (requirements → plan → TDD → commit → review → deploy). PIPELINE_AUTONOMOUS=1 is set: use the autonomous variants of every gate — self-grill instead of interviewing, clarify-record.md with BLOCKERS: 0 before plan approval, park the task back to backlog on any BLOCKER. Task file: $RUNNING

TASK:
$TASK_BODY"

# The autonomy signal — everything downstream branches on this
export PIPELINE_AUTONOMOUS=1

RUN_LOG="$LOG_DIR/run-$TASK_ID.log"
( cd "$WORKDIR" && claude -p "$PROMPT" ${PIPELINE_CLAUDE_FLAGS:---permission-mode acceptEdits} ) \
  > "$RUN_LOG" 2>&1
EXIT_CODE=$?

# --- Outcome routing (a parked task moved itself back to backlog) ---
if [ ! -f "$RUNNING" ]; then
  log "$TASK_ID parked itself back to backlog (BLOCKER) — see $RUN_LOG"
  exit 0
fi
if [ $EXIT_CODE -eq 0 ]; then
  sed -i 's/^status:.*/status: done/' "$RUNNING"
  mv "$RUNNING" "$TASKS_DIR/done/$TASK_ID.md"
  log "$TASK_ID done (log: $RUN_LOG)"
else
  sed -i 's/^status:.*/status: failed/' "$RUNNING"
  mv "$RUNNING" "$TASKS_DIR/failed/$TASK_ID.md"
  log "$TASK_ID FAILED exit=$EXIT_CODE (log: $RUN_LOG)"
fi
exit 0
