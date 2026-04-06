#!/bin/bash
# PreCompact hook: saves current session state before context compression
# Writes structured handoff to memory so the session can recover context
# PROJECT-AWARE: Uses project-detect.sh library for dynamic detection

# Memory directory — configurable via env var
MEMORY_DIR="${PIPELINE_MEMORY_DIR:-$HOME/.claude/projects/default/memory}"
HANDOFF_FILE="$MEMORY_DIR/session-state.md"

mkdir -p "$MEMORY_DIR"

# Source project detection library
LIB_DIR="${PIPELINE_HOOKS_DIR:-$(dirname "$0")}/lib"
if [ -f "$LIB_DIR/project-detect.sh" ]; then
  source "$LIB_DIR/project-detect.sh"
fi

# --- Gather git state ---
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
BRANCH_INFO=""
DIRTY_INFO=""
RECENT_COMMITS=""

if [ -n "$GIT_ROOT" ]; then
  # If in a Frappe bench, scan apps/
  if [ "${PD_IS_FRAPPE_BENCH:-0}" = "1" ] && [ -n "${PD_BENCH_ROOT:-}" ]; then
    if type pd_get_custom_apps &>/dev/null; then
      APPS=$(pd_get_custom_apps)
    else
      APPS=""
      for d in "$PD_BENCH_ROOT"/apps/*/; do
        [ -d "$d/.git" ] && APPS="$APPS $(basename "$d")"
      done
    fi

    for app in $APPS; do
      APP_DIR="$PD_BENCH_ROOT/apps/$app"
      [ -d "$APP_DIR/.git" ] || continue
      BRANCH=$(git -C "$APP_DIR" branch --show-current 2>/dev/null)
      DIRTY=$(git -C "$APP_DIR" status --porcelain 2>/dev/null | wc -l)
      if [ "$DIRTY" -gt 0 ]; then
        DIRTY_INFO="${DIRTY_INFO}\n- $app ($BRANCH): $DIRTY uncommitted changes"
      fi
      BRANCH_INFO="${BRANCH_INFO}\n- $app: $BRANCH"

      COMMITS=$(git -C "$APP_DIR" log --since="30 minutes ago" --oneline 2>/dev/null | head -5)
      if [ -n "$COMMITS" ]; then
        RECENT_COMMITS="${RECENT_COMMITS}\n### $app\n$COMMITS"
      fi
    done
  else
    # Single repo
    BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null)
    DIRTY=$(git -C "$GIT_ROOT" status --porcelain 2>/dev/null | wc -l)
    REPO_NAME=$(basename "$GIT_ROOT")
    BRANCH_INFO="\n- $REPO_NAME: $BRANCH"
    if [ "$DIRTY" -gt 0 ]; then
      DIRTY_INFO="\n- $REPO_NAME ($BRANCH): $DIRTY uncommitted changes"
    fi
    COMMITS=$(git -C "$GIT_ROOT" log --since="30 minutes ago" --oneline 2>/dev/null | head -5)
    if [ -n "$COMMITS" ]; then
      RECENT_COMMITS="\n### $REPO_NAME\n$COMMITS"
    fi
  fi
fi

# Check circuit breaker state
CIRCUIT_STATE="unknown"
CIRCUIT_FILE="$HOME/.claude/pipeline/circuit/fix-loop.json"
if [ -f "$CIRCUIT_FILE" ]; then
  CIRCUIT_STATE=$(jq -r '.state' "$CIRCUIT_FILE" 2>/dev/null || echo "unknown")
fi

# Check DLQ
DLQ_COUNT=$(find "$HOME/.claude/pipeline/tasks/failed/" -name '*.json' -maxdepth 1 2>/dev/null | wc -l)

# Check active/backlog
ACTIVE_COUNT=$(find "$HOME/.claude/pipeline/tasks/active/" -name '*.json' -maxdepth 1 2>/dev/null | wc -l)
BACKLOG_COUNT=$(find "$HOME/.claude/pipeline/tasks/backlog/" -name '*.json' -maxdepth 1 2>/dev/null | wc -l)

# Write handoff file
cat > "$HANDOFF_FILE" << EOF
---
name: session-state
description: Auto-generated session state snapshot before context compaction
type: project
---

# Session State ($(date -Iseconds))

## Project Type
${PD_PROJECT_TYPE:-unknown}

## Active Branches
$(echo -e "$BRANCH_INFO")

## Uncommitted Changes
$(if [ -n "$DIRTY_INFO" ]; then echo -e "$DIRTY_INFO"; else echo "None"; fi)

## Recent Commits (last 30 min)
$(if [ -n "$RECENT_COMMITS" ]; then echo -e "$RECENT_COMMITS"; else echo "None"; fi)

## Pipeline Health
- Circuit breaker: $CIRCUIT_STATE
- DLQ entries: $DLQ_COUNT
- Pipeline: $ACTIVE_COUNT active, $BACKLOG_COUNT queued

## Context Note
This file is auto-generated before /compact. Read it on session resume to recover context.
EOF

# Also write task-focused handoff for /clear recovery
TASK_HANDOFF="$MEMORY_DIR/handoff.md"
cat > "$TASK_HANDOFF" << EOF
---
name: handoff
description: Current task handoff -- read at session start after /clear or /compact
type: project
---

# Handoff ($(date -Iseconds))

## Active Branches
$(echo -e "$BRANCH_INFO")

## Uncommitted Changes
$(if [ -n "$DIRTY_INFO" ]; then echo -e "$DIRTY_INFO"; else echo "None"; fi)

## Recent Commits
$(if [ -n "$RECENT_COMMITS" ]; then echo -e "$RECENT_COMMITS"; else echo "None"; fi)

## Pipeline Health
- Circuit breaker: $CIRCUIT_STATE
- DLQ entries: $DLQ_COUNT

## Next Step
<!-- Fill in manually or let Claude populate before /clear -->
EOF

# Emit message so Claude knows to reference these files
echo "{\"systemMessage\": \"MANDATORY HOOK: Pre-compact handoff saved to $HANDOFF_FILE and $TASK_HANDOFF. After compaction or /clear, read these files to recover session context.\"}"
exit 0
