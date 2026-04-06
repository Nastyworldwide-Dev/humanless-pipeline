#!/bin/bash
# PreToolUse hook: validates Bash commands against a blocklist
# Exit 0 = allow, Exit 2 = block

# Source project detection library
LIB_DIR="${PIPELINE_HOOKS_DIR:-$(dirname "$0")}/lib"
[ -f "$LIB_DIR/project-detect.sh" ] && source "$LIB_DIR/project-detect.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Blocklist patterns (case-insensitive check)
COMMAND_LOWER=$(echo "$COMMAND" | tr '[:upper:]' '[:lower:]')

block_and_exit() {
  local pattern="$1"
  echo "BLOCKED: Command matches dangerous pattern '$pattern'"
  echo "If you really need this, ask the user to run it manually."
  # Log blocked command
  LOG_DIR="${PIPELINE_LOG_DIR:-$HOME/.claude/pipeline/logs}"
  mkdir -p "$LOG_DIR"
  echo "$(date '+%Y-%m-%d %H:%M:%S') BLOCKED: $COMMAND (matched: $pattern)" >> "$LOG_DIR/blocked-commands.log"
  exit 2
}

# --- rm guards: only block root-destroying rm, not rm on specific paths ---
if echo "$COMMAND_LOWER" | grep -qP '\brm\s+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r)[a-z]*\s+/(\s*\*?\s*$|\s*\*?\s*[;&|])'; then
  block_and_exit "rm -rf / or rm -rf /*"
fi
if echo "$COMMAND_LOWER" | grep -qP '\bsudo\s+rm\s+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r)[a-z]*\s+/(\s*\*?\s*$|\s*\*?\s*[;&|])'; then
  block_and_exit "sudo rm -rf /"
fi

# --- Simple substring patterns (safe — no false positives) ---
BLOCKED_PATTERNS=(
  "DROP TABLE"
  "DROP DATABASE"
  "TRUNCATE TABLE"
  "git push --force"
  "git push -f "
  "git reset --hard"
  "> /dev/sda"
  "mkfs."
  ":(){:|:&};:"
  "git checkout -- ."
  "chmod -R 777"
  "dd if="
)

# Conditionally add bench-specific blocks if in a Frappe bench
if [ "${PD_IS_FRAPPE_BENCH:-0}" = "1" ]; then
  BLOCKED_PATTERNS+=(
    "bench drop-site"
    "bench destroy-all-sessions"
    "bench setup production"
    "bench new-site"
    "bench reinstall"
  )
fi

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  pattern_lower=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')
  if [[ "$COMMAND_LOWER" == *"$pattern_lower"* ]]; then
    block_and_exit "$pattern"
  fi
done

exit 0
