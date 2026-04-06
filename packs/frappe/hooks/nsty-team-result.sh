#!/bin/bash
# SubagentStop hook: handles results from app-specific domain reviewer agents
# Routes BLOCKING findings to fix-and-recommit, non-blocking passes silently
# Generalized: handles any <appname>-* prefixed agent types

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
[ "$EVENT" = "SubagentStop" ] || exit 0

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
RESULT=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')

# Only handle app-specific team agents (pattern: <app>-<domain>-reviewer)
# Skip core pipeline agents
case "$AGENT_TYPE" in
  frappe-reviewer|tdd-runner|cross-app-impact|migration-checker) exit 0 ;;
  *-reviewer|*-checker) ;; # proceed for team agents
  *) exit 0 ;;
esac

# Check for BLOCKING: yes in agent output
if echo "$RESULT" | grep -qi "BLOCKING: yes"; then
  CRITICAL_SUMMARY=$(echo "$RESULT" | grep -A3 "CRITICAL:" | grep "^\s*-" | head -3 | sed 's/^\s*/  /')

  if [ -n "$CRITICAL_SUMMARY" ]; then
    echo "{\"systemMessage\": \"MANDATORY HOOK: ${AGENT_TYPE} found BLOCKING issues:\\n${CRITICAL_SUMMARY}\\nFix these issues NOW, then re-commit. Do NOT deploy.\"}"
  else
    echo "{\"systemMessage\": \"MANDATORY HOOK: ${AGENT_TYPE} found BLOCKING issues. Review the agent output, fix the issues, then re-commit. Do NOT deploy.\"}"
  fi
else
  if echo "$RESULT" | grep -qi "WARNING:"; then
    echo "{\"systemMessage\": \"INFO: ${AGENT_TYPE} completed with warnings (non-blocking). Review when convenient. Pipeline continues.\"}"
  fi
fi

exit 0
