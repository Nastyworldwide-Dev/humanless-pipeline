#!/bin/bash
# PreToolUse hook: runs ./gradlew detekt before git commit
# Blocks feat:/fix: commits if detekt errors exist

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

# Check if detekt is configured
if ! grep -q "detekt" "$GRADLE_ROOT/build.gradle.kts" 2>/dev/null && \
   ! grep -q "detekt" "$GRADLE_ROOT/build.gradle" 2>/dev/null && \
   ! [ -f "$GRADLE_ROOT/detekt.yml" ]; then
  exit 0
fi

# Run detekt
DETEKT_OUTPUT=$(cd "$GRADLE_ROOT" && ./gradlew detekt 2>&1)
DETEKT_EXIT=$?

if [ $DETEKT_EXIT -ne 0 ]; then
  ERROR_COUNT=$(echo "$DETEKT_OUTPUT" | grep -c "- " || echo "0")
  SAMPLE=$(echo "$DETEKT_OUTPUT" | grep -E "(ComplexMethod|LongMethod|MagicNumber|MaxLineLength)" | head -5)

  echo "BLOCKED: detekt static analysis errors detected ($ERROR_COUNT issues)."
  if [ -n "$SAMPLE" ]; then
    echo "Sample issues:"
    echo "$SAMPLE"
  fi
  echo ""
  echo "Fix detekt issues before committing feat:/fix: changes."
  echo "Use 'chore:' prefix to bypass for non-logic changes."
  exit 2
fi

exit 0
