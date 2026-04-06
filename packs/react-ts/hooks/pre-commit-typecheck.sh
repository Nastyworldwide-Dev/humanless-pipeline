#!/bin/bash
# PreToolUse hook: runs tsc --noEmit before git commit
# Blocks feat:/fix: commits if TypeScript errors exist

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only match Bash tool with git commit commands
[ "$TOOL_NAME" = "Bash" ] || exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

# Extract commit type — skip for chore/docs
COMMIT_MSG=$(echo "$COMMAND" | grep -oP '(?<=-m\s)["\x27](.+?)["\x27]' | head -1 | sed "s/^[\"']//;s/[\"']$//")
COMMIT_TYPE=$(echo "$COMMIT_MSG" | grep -oP '^\w+(?=[:(\s])' | head -1)
case "$COMMIT_TYPE" in
  chore|docs|style) exit 0 ;;
esac

# Detect CWD
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# Find tsconfig.json (walk up from CWD)
TSCONFIG=""
CHECK_DIR="$CWD"
while [ "$CHECK_DIR" != "/" ]; do
  if [ -f "$CHECK_DIR/tsconfig.json" ]; then
    TSCONFIG="$CHECK_DIR/tsconfig.json"
    break
  fi
  CHECK_DIR=$(dirname "$CHECK_DIR")
done

[ -z "$TSCONFIG" ] && exit 0

PROJECT_DIR=$(dirname "$TSCONFIG")

# Run typecheck
TSC_OUTPUT=$(cd "$PROJECT_DIR" && npx tsc --noEmit 2>&1)
TSC_EXIT=$?

if [ $TSC_EXIT -ne 0 ]; then
  ERROR_COUNT=$(echo "$TSC_OUTPUT" | grep -c "error TS" || echo "0")
  SAMPLE_ERRORS=$(echo "$TSC_OUTPUT" | grep "error TS" | head -5)

  echo "BLOCKED: TypeScript type errors detected ($ERROR_COUNT errors)."
  echo "Sample errors:"
  echo "$SAMPLE_ERRORS"
  echo ""
  echo "Fix type errors before committing feat:/fix: changes."
  echo "Use 'chore:' prefix to bypass for non-logic changes."
  exit 2
fi

exit 0
