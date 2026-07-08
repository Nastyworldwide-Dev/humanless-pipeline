#!/bin/bash
# PreToolUse hook: validates conventional commit message format
# Checks that git commit messages follow the conventional commits spec
# Exit 0 = allow, Exit 2 = block

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

# Extract commit message
MSG=$(echo "$COMMAND" | grep -oP '(?<=-m\s["\x27])[^"\x27]+' | head -1)

# Also try heredoc pattern
if [ -z "$MSG" ]; then
  MSG=$(echo "$COMMAND" | grep -oP '(?<=<<.*EOF\n).*(?=\nEOF)' | head -1)
fi

# If we can't extract the message, allow (don't block on parse failure)
[ -z "$MSG" ] && exit 0

# Validate conventional commit format
if ! echo "$MSG" | grep -qE '^\s*(feat|fix|chore|refactor|docs|test|style|perf|ci|build|revert)(\(.+\))?\s*:\s*.+'; then
  cat <<EOF
{"systemMessage": "Commit message doesn't follow conventional commits format. Expected: type(scope): description. Valid types: feat, fix, chore, refactor, docs, test, style, perf, ci, build, revert. Example: feat(auth): add OAuth2 login flow"}
EOF
  # Warn but don't block
  exit 0
fi

exit 0
