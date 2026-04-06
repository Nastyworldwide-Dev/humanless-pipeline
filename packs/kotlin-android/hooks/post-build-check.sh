#!/bin/bash
# PostToolUse hook: verifies APK/AAB build after code changes
# Advisory only — suggests building if Kotlin files were edited

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

FILENAME=$(basename "$FILE_PATH")
EXTENSION="${FILENAME##*.}"

# Only trigger for Kotlin/Gradle files
case "$EXTENSION" in
  kt|kts) ;;
  *) exit 0 ;;
esac

# Skip test files
echo "$FILE_PATH" | grep -qE '/(test|androidTest)/' && exit 0

# Debounce: only fire once per 120-second window
DEBOUNCE_DIR="$HOME/.claude/pipeline/debounce"
mkdir -p "$DEBOUNCE_DIR"
DEBOUNCE_FILE="$DEBOUNCE_DIR/android-build-pending"

if [ -f "$DEBOUNCE_FILE" ]; then
  FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$DEBOUNCE_FILE" 2>/dev/null || echo 0) ))
  if [ "$FILE_AGE" -lt 120 ]; then
    exit 0
  fi
fi

touch "$DEBOUNCE_FILE"
(sleep 120 && rm -f "$DEBOUNCE_FILE") &

# Find project root
GRADLE_ROOT=""
CHECK_DIR=$(dirname "$FILE_PATH")
while [ "$CHECK_DIR" != "/" ]; do
  if [ -f "$CHECK_DIR/gradlew" ]; then
    GRADLE_ROOT="$CHECK_DIR"
    break
  fi
  CHECK_DIR=$(dirname "$CHECK_DIR")
done

[ -z "$GRADLE_ROOT" ] && exit 0

echo "{\"systemMessage\": \"Kotlin source file $FILENAME modified. Consider running a build check: cd $GRADLE_ROOT && ./gradlew assembleDebug to verify the build still succeeds. This is advisory — proceed with your current task first.\"}"
exit 0
