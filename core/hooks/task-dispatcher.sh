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

  # Ambiguity screening at queue time — backlog tasks used to bypass the
  # requirement-interpreter entirely; a queued vague task is a vague task the
  # autonomous runner will pick up with no user present.
  NEEDS_CLARIFY=false
  TASK_VAGUE=$(echo "$TASK_BODY" | grep -ciE '(make it better|improve|optimize|clean up|fix it|make it work|something like|sort of|kind of|maybe|probably|etc\.)' || echo 0)
  TASK_WORDS=$(echo "$TASK_BODY" | wc -w)
  { [ "$TASK_VAGUE" -gt 0 ] || [ "$TASK_WORDS" -lt 8 ]; } && NEEDS_CLARIFY=true

  mkdir -p "$TASKS_DIR/backlog"
  cat > "$TASK_FILE" <<TASKEOF
---
id: $TASK_ID
status: backlog
needs_clarify: $NEEDS_CLARIFY
created: $(date -u +%Y-%m-%dT%H:%M:%SZ)
---
$TASK_BODY
TASKEOF

  CLARIFY_NOTE=""
  [ "$NEEDS_CLARIFY" = "true" ] && CLARIFY_NOTE=" Flagged needs_clarify — the autonomous runner starts it with /grill-me Autonomous Mode (self-grill ledger) before any code."
  cat <<EOF
{"systemMessage": "Task queued to backlog: $TASK_ID.${CLARIFY_NOTE} Use 'task: list' to see all tasks."}
EOF
fi

exit 0
