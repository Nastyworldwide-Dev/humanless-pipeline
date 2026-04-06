#!/usr/bin/env bash
# Secret Detection Hook — PreToolUse (Edit|Write)
# Scans file content being written/edited for API keys, tokens, and secrets.
# Blocks the operation if secrets are detected.
#
# Hook input: JSON on stdin with tool_input containing file content
# Exit 2 = block with message, Exit 0 = allow

set -euo pipefail

INPUT=$(cat)

# Extract the tool name and content to scan
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Get content based on tool type
if [ "$TOOL_NAME" = "Write" ]; then
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
elif [ "$TOOL_NAME" = "Edit" ]; then
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
else
    exit 0
fi

# Skip if no content to scan
if [ -z "$CONTENT" ]; then
    exit 0
fi

# Skip test files, fixtures, and hook scripts themselves (they may reference patterns)
case "$FILE_PATH" in
    */test_*|*/tests/*|*_test.py|*.test.js|*.test.ts|*.spec.js|*.spec.ts)
        exit 0
        ;;
    */.claude/hooks/secret-detection*)
        exit 0
        ;;
    # Skip the pipeline's own secret-detection hook
    */humanless-pipeline/*/secret-detection*)
        exit 0
        ;;
esac

# Secret patterns to detect
# Each pattern: "REGEX:::LABEL"
PATTERNS=(
    'sk-[a-zA-Z0-9]{20,}:::OpenAI/Anthropic API key (sk-...)'
    'sk-ant-[a-zA-Z0-9-]{20,}:::Anthropic API key (sk-ant-...)'
    'ghp_[a-zA-Z0-9]{36,}:::GitHub personal access token (ghp_...)'
    'gho_[a-zA-Z0-9]{36,}:::GitHub OAuth token (gho_...)'
    'ghs_[a-zA-Z0-9]{36,}:::GitHub server token (ghs_...)'
    'github_pat_[a-zA-Z0-9_]{22,}:::GitHub fine-grained PAT'
    'AKIA[0-9A-Z]{16}:::AWS Access Key ID (AKIA...)'
    'xoxb-[0-9]{10,}-[a-zA-Z0-9]{20,}:::Slack bot token (xoxb-...)'
    'xoxp-[0-9]{10,}-[a-zA-Z0-9]{20,}:::Slack user token (xoxp-...)'
    'xoxs-[0-9]{10,}-[a-zA-Z0-9]{20,}:::Slack session token (xoxs-...)'
    'SG\.[a-zA-Z0-9_-]{22,}\.[a-zA-Z0-9_-]{43,}:::SendGrid API key'
    'eyJ[a-zA-Z0-9_-]{10,}\.eyJ[a-zA-Z0-9_-]{10,}:::JWT token (eyJ...)'
    'PRIVATE KEY-----:::Private key block'
    'password\s*[:=]\s*["\x27][^"\x27]{8,}:::Hardcoded password'
    'secret\s*[:=]\s*["\x27][^"\x27]{8,}:::Hardcoded secret'
    'api[_-]?key\s*[:=]\s*["\x27][a-zA-Z0-9]{16,}:::Hardcoded API key'
    'mysql://[^:]+:[^@]+@:::Database connection string with credentials'
    'postgres://[^:]+:[^@]+@:::Database connection string with credentials'
    'mongodb(\+srv)?://[^:]+:[^@]+@:::MongoDB connection string with credentials'
)

FOUND=""

for entry in "${PATTERNS[@]}"; do
    REGEX="${entry%%:::*}"
    LABEL="${entry##*:::}"

    if echo "$CONTENT" | grep -qPi "$REGEX" 2>/dev/null; then
        # Extract the matching line (truncated) for context
        MATCH=$(echo "$CONTENT" | grep -Pi "$REGEX" 2>/dev/null | head -1 | cut -c1-80)
        FOUND="${FOUND}\n  - ${LABEL}: ...${MATCH}..."
    fi
done

if [ -n "$FOUND" ]; then
    echo "BLOCKED" >&2
    cat <<EOF
{"decision": "block", "reason": "SECRET DETECTED in ${FILE_PATH}\n\nPotential secrets found:${FOUND}\n\nIf these are intentional (test fixtures, documentation examples), use environment variables or config files instead. Never hardcode secrets in source code."}
EOF
    exit 2
fi

exit 0
