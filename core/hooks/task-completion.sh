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
      cat <<EOF
{"systemMessage": "Task completed: $TASK_NAME has been moved to done/ after successful push."}
EOF
    fi
  fi
fi

exit 0
