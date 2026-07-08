#!/bin/bash
# UserPromptSubmit hook: routes prompts to task pipeline if they match task patterns
# Detects task-like prompts and creates task files in ~/.claude/pipeline/tasks/
# Exit 0 = allow (always allows, just emits systemMessage for task routing)

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

[ -z "$PROMPT" ] && exit 0

TASKS_DIR="$HOME/.claude/pipeline/tasks"

# Detect task-like patterns
if echo "$PROMPT" | grep -qiE '^\s*(task|todo|backlog|queue):\s'; then
  TASK_BODY=$(echo "$PROMPT" | sed -E 's/^\s*(task|todo|backlog|queue):\s*//i')
  TASK_ID="task-$(date +%s)"
  TASK_FILE="$TASKS_DIR/backlog/${TASK_ID}.md"

  mkdir -p "$TASKS_DIR/backlog"
  cat > "$TASK_FILE" <<TASKEOF
---
id: $TASK_ID
status: backlog
created: $(date -u +%Y-%m-%dT%H:%M:%SZ)
---
$TASK_BODY
TASKEOF

  cat <<EOF
{"systemMessage": "Task queued to backlog: $TASK_ID. Use 'task: list' to see all tasks. The task will be picked up in the next available slot."}
EOF
fi

exit 0
