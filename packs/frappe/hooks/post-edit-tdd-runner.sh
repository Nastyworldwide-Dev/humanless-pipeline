#!/bin/bash
# PostToolUse hook: triggers tdd-runner agent after implementation file edits
# Fires on Edit/Write tool calls for code files (not tests, not config)
# 60-second debounce to avoid spamming

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

FILENAME=$(basename "$FILE_PATH")
EXTENSION="${FILENAME##*.}"

# --- Filter: only code files ---
case "$EXTENSION" in
  py|ts|tsx|js|jsx|kt) ;;
  *) exit 0 ;;
esac

# --- Filter: skip test files ---
if [[ "$FILENAME" == test_* ]]; then
  exit 0
fi
if [[ "$FILENAME" == *.test.* ]] || [[ "$FILENAME" == *.spec.* ]]; then
  exit 0
fi

# --- Filter: skip known config files ---
case "$FILENAME" in
  hooks.py|setup.py|conftest.py|__init__.py|pyproject.toml)
    exit 0
    ;;
esac

# --- Debounce: only fire once per 60-second window ---
DEBOUNCE_DIR="$HOME/.claude/pipeline/debounce"
mkdir -p "$DEBOUNCE_DIR"
DEBOUNCE_FILE="$DEBOUNCE_DIR/tdd-runner-pending"

if [ -f "$DEBOUNCE_FILE" ]; then
  FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$DEBOUNCE_FILE" 2>/dev/null || echo 0) ))
  if [ "$FILE_AGE" -lt 60 ]; then
    exit 0
  fi
fi

touch "$DEBOUNCE_FILE"

# Clean up debounce file after 60 seconds
(sleep 60 && rm -f "$DEBOUNCE_FILE") &

echo '{"systemMessage": "MANDATORY HOOK: Implementation file '"$FILENAME"' modified. Spawn tdd-runner agent NOW (subagent_type=\"tdd-runner\", run_in_background: true) with prompt: \"Run tests for recently modified files. Report pass/fail results.\" After it completes: if all tests pass AND you have no more edits to make, commit immediately. If tests fail, fix them first. Execute immediately — do not ask user."}'
