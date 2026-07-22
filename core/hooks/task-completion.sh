#!/bin/bash
# PostToolUse hook: detects task completion signals and updates task state
# Watches for successful git push or deploy completion
# Exit 0 = always allow (post-tool hooks don't block)

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // .tool_result.exit_code // "0"')

[ "$TOOL_NAME" = "Bash" ] || exit 0
[ "$EXIT_CODE" = "0" ] || exit 0

TASKS_DIR="$HOME/.claude/pipeline/tasks"

# Detect git push success — anywhere in the command, not only at its start:
# real pushes are compound ("cd repo && git commit ... && git push"), which
# the old ^-anchored match silently skipped (muting retro + CI dispatch).
if echo "$COMMAND" | grep -qE '(^|&&|;)[[:space:]]*git[[:space:]]+push'; then
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

  # Async CI loop for Frappe app repos (no local bench on this VPS): every
  # push dispatches the repo's GitHub CI; pipeline-health reports the result
  # at next session start. Push events don't trigger runs on this org
  # (known GitHub issue) — workflow_dispatch is the working path.
  # Candidate repos come from every `cd <dir>` in the command PLUS the hook
  # cwd — a compound command may push from a different repo than .cwd.
  CI_NOTE=""
  if command -v gh >/dev/null 2>&1; then
    CANDIDATES=$(printf '%s\n%s\n' "$CWD" \
      "$(echo "$COMMAND" | grep -oE '(^|&&|;)[[:space:]]*cd[[:space:]]+[^ &;]+' | sed -E 's/.*cd[[:space:]]+//')" \
      | sort -u)
    while IFS= read -r DIR; do
      [ -d "$DIR" ] || continue
      GIT_ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || continue
      ls "$GIT_ROOT"/*/hooks.py >/dev/null 2>&1 || continue
      ls "$GIT_ROOT"/.github/workflows/*.yml >/dev/null 2>&1 || continue
      BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null)
      if [ -n "$BRANCH" ] && (cd "$GIT_ROOT" && timeout 30 gh workflow run CI --ref "$BRANCH") >/dev/null 2>&1; then
        CI_NOTE="${CI_NOTE}Frappe CI dispatched for $(basename "$GIT_ROOT")@$BRANCH (verdict at next session start via pipeline-health). "
      fi
    done <<< "$CANDIDATES"
  fi

  if [ -n "$TASK_NOTE$RETRO_MSG$CI_NOTE" ]; then
    jq -n --arg msg "${TASK_NOTE}${CI_NOTE}${RETRO_MSG}" '{systemMessage: $msg}'
  fi
fi

exit 0
