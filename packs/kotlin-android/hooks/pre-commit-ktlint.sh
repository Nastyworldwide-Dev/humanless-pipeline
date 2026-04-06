#!/bin/bash
# PreToolUse hook: runs ktlint formatting check before git commit
# Blocks feat:/fix: commits if formatting errors exist

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

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# Find project root with gradlew
GRADLE_ROOT=""
CHECK_DIR="$CWD"
while [ "$CHECK_DIR" != "/" ]; do
  if [ -f "$CHECK_DIR/gradlew" ]; then
    GRADLE_ROOT="$CHECK_DIR"
    break
  fi
  CHECK_DIR=$(dirname "$CHECK_DIR")
done

[ -z "$GRADLE_ROOT" ] && exit 0

# Try gradle ktlintCheck first, fall back to standalone ktlint
if grep -q "ktlint" "$GRADLE_ROOT/build.gradle.kts" 2>/dev/null || \
   grep -q "ktlint" "$GRADLE_ROOT/build.gradle" 2>/dev/null; then
  KTLINT_OUTPUT=$(cd "$GRADLE_ROOT" && ./gradlew ktlintCheck 2>&1)
  KTLINT_EXIT=$?
elif command -v ktlint &>/dev/null; then
  # Get staged .kt files
  STAGED_KT=$(cd "$CWD" && git diff --cached --name-only --diff-filter=ACMR -- '*.kt' '*.kts' 2>/dev/null)
  [ -z "$STAGED_KT" ] && exit 0
  KTLINT_OUTPUT=$(cd "$GRADLE_ROOT" && echo "$STAGED_KT" | xargs ktlint 2>&1)
  KTLINT_EXIT=$?
else
  exit 0  # No ktlint available
fi

if [ $KTLINT_EXIT -ne 0 ]; then
  ERROR_COUNT=$(echo "$KTLINT_OUTPUT" | grep -cE '^\S+:\d+:\d+:' || echo "0")
  SAMPLE=$(echo "$KTLINT_OUTPUT" | grep -E '^\S+:\d+:\d+:' | head -5)

  echo "BLOCKED: ktlint formatting errors detected ($ERROR_COUNT issues)."
  if [ -n "$SAMPLE" ]; then
    echo "Sample issues:"
    echo "$SAMPLE"
  fi
  echo ""
  echo "Run './gradlew ktlintFormat' or 'ktlint -F' to auto-fix."
  echo "Use 'chore:' prefix to bypass for non-logic changes."
  exit 2
fi

exit 0
