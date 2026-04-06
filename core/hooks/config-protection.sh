#!/usr/bin/env bash
# Config Protection Hook — PreToolUse (Edit|Write)
# Prevents accidental or malicious modification of critical pipeline config files.
# Protected files: settings.json, hook scripts, agent definitions.
#
# Exit 2 = block with message, Exit 0 = allow

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Edit and Write operations
case "$TOOL_NAME" in
    Edit|Write) ;;
    *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -n "$FILE_PATH" ] || exit 0

# Protected file patterns
PROTECTED=false
REASON=""

case "$FILE_PATH" in
    */\.claude/settings\.json)
        PROTECTED=true
        REASON="Claude Code settings.json -- contains all hook definitions, permissions, and plugin config"
        ;;
    */\.claude/hooks/validate-bash\.sh)
        PROTECTED=true
        REASON="Bash validation hook -- core security gate"
        ;;
    */\.claude/hooks/tdd-gate\.sh|*/\.claude/hooks/tdd-gate-edit\.sh)
        PROTECTED=true
        REASON="TDD enforcement gate -- ensures test-driven development"
        ;;
    */\.claude/hooks/pre-commit-lint\.sh|*/\.claude/hooks/pre-commit-validate\.sh)
        PROTECTED=true
        REASON="Pre-commit quality gates -- enforce code quality standards"
        ;;
    */\.claude/hooks/secret-detection\.sh)
        PROTECTED=true
        REASON="Secret detection hook -- prevents credential leaks"
        ;;
    */\.claude/hooks/config-protection\.sh)
        PROTECTED=true
        REASON="Config protection hook -- self-protection (cannot disable itself)"
        ;;
    */\.claude/hooks/dev-server-block\.sh)
        PROTECTED=true
        REASON="Dev server blocking hook -- prevents session hangs"
        ;;
    */\.claude/hooks/pipeline-health\.sh|*/\.claude/hooks/dlq-check\.sh)
        PROTECTED=true
        REASON="Pipeline health monitoring -- session start checks"
        ;;
    */\.claude/hooks/post-commit-review\.sh)
        PROTECTED=true
        REASON="Auto code review trigger -- post-commit automation"
        ;;
    */\.claude/hooks/learnings-capture\.sh)
        PROTECTED=true
        REASON="Learnings capture hook -- continuous learning system"
        ;;
esac

if [ "$PROTECTED" = true ]; then
    cat <<EOF
{"decision": "block", "reason": "PROTECTED FILE: ${FILE_PATH}\n\nReason: ${REASON}\n\nThis file is part of the pipeline's critical infrastructure. Modifying it could break the entire humanless pipeline.\n\nTo modify protected files:\n  1. The user must explicitly request the change\n  2. Use: 'I authorize modifying ${FILE_PATH}'\n  3. Or temporarily bypass: ALLOW_CONFIG_EDIT=1 in the command"}
EOF
    exit 2
fi

exit 0
