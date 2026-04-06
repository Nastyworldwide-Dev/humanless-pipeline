#!/bin/bash
# PostToolUse hook: auto-formats with biome/prettier after edits to JS/TS files
# Advisory only — never blocks

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

FILENAME=$(basename "$FILE_PATH")
EXTENSION="${FILENAME##*.}"

# Only format JS/TS/JSX/TSX files
case "$EXTENSION" in
  ts|tsx|js|jsx) ;;
  *) exit 0 ;;
esac

# Skip test files, config files, and generated files
case "$FILENAME" in
  *.test.*|*.spec.*|*.d.ts|*.config.*|*.generated.*) exit 0 ;;
esac

# Find project root with biome or prettier config
CHECK_DIR=$(dirname "$FILE_PATH")
FORMATTER=""
FORMATTER_CMD=""

while [ "$CHECK_DIR" != "/" ]; do
  if [ -f "$CHECK_DIR/biome.json" ] || [ -f "$CHECK_DIR/biome.jsonc" ]; then
    FORMATTER="biome"
    FORMATTER_CMD="npx @biomejs/biome format --write"
    break
  fi
  if [ -f "$CHECK_DIR/.prettierrc" ] || [ -f "$CHECK_DIR/.prettierrc.json" ] || \
     [ -f "$CHECK_DIR/.prettierrc.js" ] || [ -f "$CHECK_DIR/prettier.config.js" ]; then
    FORMATTER="prettier"
    FORMATTER_CMD="npx prettier --write"
    break
  fi
  CHECK_DIR=$(dirname "$CHECK_DIR")
done

[ -z "$FORMATTER" ] && exit 0

# Format the file (silent — don't pollute output)
$FORMATTER_CMD "$FILE_PATH" >/dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "{\"systemMessage\": \"Auto-formatted $FILENAME with $FORMATTER.\"}"
fi

exit 0
