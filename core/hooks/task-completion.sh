#!/bin/bash
# PostToolUse hook: detects task completion signals and updates task state
# Watches for successful git push or deploy completion
# Exit 0 = always allow (post-tool hooks don't block)

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // "0"')

[ "$TOOL_NAME" = "Bash" ] || exit 0
[ "$EXIT_CODE" = "0" ] || exit 0

TASKS_DIR="$HOME/.claude/pipeline/tasks"

# Detect git push success
if echo "$COMMAND" | grep -qE '^\s*git\s+push'; then
  TASK_NOTE=""
  # Check for active tasks and mark the most recent one as done
  ACTIVE_DIR="$TASKS_DIR/active"
  if [ -d "$ACTIVE_DIR" ]; then
    LATEST_TASK=$(ls -t "$ACTIVE_DIR"/*.md 2>/dev/null | head -1)
    if [ -n "$LATEST_TASK" ] && [ -f "$LATEST_TASK" ]; then
      mkdir -p "$TASKS_DIR/done"
      TASK_NAME=$(basename "$LATEST_TASK")
      # Update status in frontmatter
      sed -i 's/status: active/status: done/' "$LATEST_TASK"
      mv "$LATEST_TASK" "$TASKS_DIR/done/$TASK_NAME"
      TASK_NOTE="Task completed: $TASK_NAME moved to done/. "
    fi
  fi

  # Retro back-edge: every pushed task gets a shots-to-green retrospective —
  # the telemetry rows power the eval report's rerun-cause histogram.
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  RETRO_MSG=""
  if [ -n "$CWD" ] && git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    RETRO_MSG="MANDATORY HOOK: Push succeeded. Spawn retro-analyst agent NOW (subagent_type=\"retro-analyst\", run_in_background: true) with prompt: \"Retro for repo $CWD, range origin/HEAD@{1}..HEAD (fall back to the last 6h of commits). Count shots-to-green, classify causes, append the telemetry CSV row.\" Execute immediately."
  fi

  if [ -n "$TASK_NOTE$RETRO_MSG" ]; then
    jq -n --arg msg "${TASK_NOTE}${RETRO_MSG}" '{systemMessage: $msg}'
  fi
fi

exit 0
