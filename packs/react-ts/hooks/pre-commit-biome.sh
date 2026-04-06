#!/bin/bash
# PreToolUse hook: runs biome format/lint check before git commit
# Blocks feat:/fix: commits if biome errors exist

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

# Find biome config (walk up from CWD)
BIOME_CONFIG=""
CHECK_DIR="$CWD"
while [ "$CHECK_DIR" != "/" ]; do
  if [ -f "$CHECK_DIR/biome.json" ] || [ -f "$CHECK_DIR/biome.jsonc" ]; then
    BIOME_CONFIG="$CHECK_DIR"
    break
  fi
  CHECK_DIR=$(dirname "$CHECK_DIR")
done

[ -z "$BIOME_CONFIG" ] && exit 0

# Get staged files
STAGED_FILES=$(cd "$CWD" && git diff --cached --name-only --diff-filter=ACMR -- '*.ts' '*.tsx' '*.js' '*.jsx' 2>/dev/null)
[ -z "$STAGED_FILES" ] && exit 0

# Run biome check on staged files
BIOME_OUTPUT=$(cd "$BIOME_CONFIG" && echo "$STAGED_FILES" | xargs npx @biomejs/biome check --no-errors-on-unmatched 2>&1)
BIOME_EXIT=$?

if [ $BIOME_EXIT -ne 0 ]; then
  ERROR_LINES=$(echo "$BIOME_OUTPUT" | grep -cE '(error|warning)\[' || echo "0")
  SAMPLE=$(echo "$BIOME_OUTPUT" | grep -E '(error|warning)\[' | head -5)

  echo "BLOCKED: Biome lint/format errors detected ($ERROR_LINES issues)."
  echo "Sample issues:"
  echo "$SAMPLE"
  echo ""
  echo "Run 'npx @biomejs/biome check --write .' to auto-fix."
  echo "Use 'chore:' prefix to bypass for non-logic changes."
  exit 2
fi

exit 0
