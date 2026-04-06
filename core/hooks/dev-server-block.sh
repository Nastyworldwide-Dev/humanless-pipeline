#!/usr/bin/env bash
# Dev Server Blocking Hook — PreToolUse (Bash)
# Prevents the agent from starting long-running dev servers that would hang the session.
# Allows if explicitly backgrounded (&) or run in tmux/screen.
#
# Exit 2 = block with message, Exit 0 = allow

set -uo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -n "$COMMAND" ] || exit 0

# Allow patterns — these make long-running commands safe
# Check these FIRST so backgrounded/tmux commands pass through
if [[ "$COMMAND" =~ \&[[:space:]]*$ ]] \
    || [[ "$COMMAND" =~ ^nohup\  ]] \
    || [[ "$COMMAND" =~ ^tmux\  ]] \
    || [[ "$COMMAND" =~ ^screen\  ]] \
    || [[ "$COMMAND" =~ ^timeout\  ]] \
    || [[ "$COMMAND" =~ --help ]] \
    || [[ "$COMMAND" =~ --version ]]; then
    exit 0
fi

# Blocking patterns — commands that start long-running servers
BLOCK_PATTERNS=(
    'bench serve'
    'bench start'
    'npm run dev'
    'npm start'
    'yarn dev'
    'yarn start'
    'bun dev'
    'bun run dev'
    'pnpm dev'
    'pnpm run dev'
    'flask run'
    'next dev'
    'webpack serve'
    'ng serve'
    'hugo server'
    'jekyll serve'
    'live-server'
    'http-server'
)

for block in "${BLOCK_PATTERNS[@]}"; do
    if [[ "$COMMAND" == *"$block"* ]]; then
        cat <<EOF
{"decision": "block", "reason": "DEV SERVER BLOCKED: '${COMMAND}'\n\nThis command starts a long-running server that will hang the session and waste tokens.\n\nSafe alternatives:\n  - Add '&' to background it: ${COMMAND} &\n  - Use 'timeout 10': timeout 10 ${COMMAND}\n  - Use run_in_background: true parameter\n  - Run in tmux: tmux new -d '${COMMAND}'"}
EOF
        exit 2
    fi
done

# Regex patterns (need special matching)
if echo "$COMMAND" | grep -qP 'python.*manage\.py\s+runserver' 2>/dev/null \
    || echo "$COMMAND" | grep -qP 'uvicorn .* --reload' 2>/dev/null \
    || echo "$COMMAND" | grep -qP 'python3? -m http\.server' 2>/dev/null \
    || echo "$COMMAND" | grep -qP 'php -S' 2>/dev/null \
    || echo "$COMMAND" | grep -qP '^\s*vite\b' 2>/dev/null; then
    cat <<EOF
{"decision": "block", "reason": "DEV SERVER BLOCKED: '${COMMAND}'\n\nThis command starts a long-running server that will hang the session and waste tokens.\n\nSafe alternatives:\n  - Add '&' to background it: ${COMMAND} &\n  - Use 'timeout 10': timeout 10 ${COMMAND}\n  - Use run_in_background: true parameter\n  - Run in tmux: tmux new -d '${COMMAND}'"}
EOF
    exit 2
fi

exit 0
