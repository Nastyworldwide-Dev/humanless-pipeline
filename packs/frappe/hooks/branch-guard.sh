#!/bin/bash
# PreToolUse hook: advisory warning when committing directly to main/master
# PROJECT-AWARE: Uses project-detect.sh for dynamic app detection
# Does NOT block (exit 0 always for non-feat/fix) — blocks feat/fix on main

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only match Bash tool with git commit commands
[ "$TOOL_NAME" = "Bash" ] || exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

# Extract commit type — skip warning for chore/docs (low-risk)
COMMIT_MSG=$(echo "$COMMAND" | grep -oP '(?<=-m\s)["\x27](.+?)["\x27]' | head -1 | sed "s/^[\"']//;s/[\"']$//")
COMMIT_TYPE=$(echo "$COMMIT_MSG" | grep -oP '^\w+(?=[:(\s])' | head -1)
case "$COMMIT_TYPE" in
  chore|docs|style) exit 0 ;;
esac

# Detect CWD
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# Source project detection library
LIB_DIR="$HOME/.claude/hooks/lib"
if [ -f "$LIB_DIR/project-detect.sh" ]; then
  source "$LIB_DIR/project-detect.sh"
fi

# Detect app name from CWD
APP_NAME=""
if type pd_get_app_for_file &>/dev/null && [ "$PD_IS_FRAPPE_BENCH" = "1" ]; then
  APP_NAME=$(pd_get_app_for_file "$CWD/dummy")
fi

# Fallback: extract from path pattern
if [ -z "$APP_NAME" ]; then
  APP_NAME=$(echo "$CWD" | grep -oP '(?<=/apps/)[^/]+' | head -1)
fi

# If not in an app directory, skip
[ -z "$APP_NAME" ] && exit 0

# Skip framework apps
case "$APP_NAME" in
  frappe|erpnext|hrms|insights|payments|india_compliance|lms) exit 0 ;;
esac

# Check current branch
BRANCH=$(cd "$CWD" && git branch --show-current 2>/dev/null)

case "$BRANCH" in
  main|master)
    case "$COMMIT_TYPE" in
      feat|fix)
        echo "BLOCKED: '$COMMIT_TYPE:' commits must use a feature branch on $APP_NAME."
        echo "  Run: git checkout -b $COMMIT_TYPE/<description>"
        echo "  Or use a worktree: git worktree add ../$APP_NAME-$COMMIT_TYPE $BRANCH"
        exit 2
        ;;
      *)
        echo "{\"systemMessage\": \"MANDATORY HOOK: Branch warning — committing '$COMMIT_TYPE:' directly to '$BRANCH' in $APP_NAME. This is allowed but consider a feature branch for larger changes.\"}"
        ;;
    esac
    ;;
esac

exit 0
