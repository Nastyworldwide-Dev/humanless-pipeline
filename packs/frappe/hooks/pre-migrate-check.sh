#!/bin/bash
# PreToolUse hook: advisory warning when running bench migrate manually
# Reminds to run migration-checker agent before proceeding
# Does NOT block (exit 0) — advisory only

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only match Bash tool
[ "$TOOL_NAME" = "Bash" ] || exit 0

# Detect bench migrate commands (with or without --site)
echo "$COMMAND" | grep -qE 'bench\s+(--site\s+\S+\s+)?migrate(\s|$)' || exit 0

# Don't warn if this is being called from the deploy agent (avoid double-checking)
echo "$COMMAND" | grep -q 'DEPLOY_AGENT_SKIP_MIGRATE_CHECK' && exit 0

echo '{"systemMessage": "PRE-MIGRATE ADVISORY: You are about to run bench migrate. Consider spawning the migration-checker agent first to verify patches are safe, check for data loss risks, and ensure proper rollback paths. Run: Agent(subagent_type=\"migration-checker\"). If you already ran the check or this is a routine migrate with no schema changes, proceed."}'
exit 0
