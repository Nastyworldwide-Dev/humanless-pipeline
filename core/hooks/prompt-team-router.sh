#!/bin/bash
# UserPromptSubmit hook: suggests agent team composition based on prompt complexity
# Analyzes prompt to recommend which agents to spawn
# Exit 0 = allow (always allows, emits systemMessage with team suggestion)

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

[ -z "$PROMPT" ] && exit 0

# Count complexity signals
WORD_COUNT=$(echo "$PROMPT" | wc -w)
HAS_FILE_REFS=$(echo "$PROMPT" | grep -coE '\.(py|ts|tsx|js|kt|md|json|sh)' || echo 0)
HAS_FEATURE_KEYWORDS=$(echo "$PROMPT" | grep -ciE '(feature|implement|build|create|add|design|architect)' || echo 0)
HAS_BUG_KEYWORDS=$(echo "$PROMPT" | grep -ciE '(bug|fix|broken|error|crash|fail|issue)' || echo 0)
HAS_REFACTOR_KEYWORDS=$(echo "$PROMPT" | grep -ciE '(refactor|cleanup|reorganize|restructure|migrate)' || echo 0)

# Only suggest teams for complex prompts
if [ "$WORD_COUNT" -gt 50 ] || [ "$HAS_FILE_REFS" -gt 3 ]; then
  if [ "$HAS_FEATURE_KEYWORDS" -gt 0 ]; then
    cat <<EOF
{"systemMessage": "Complex feature request detected. Consider spawning: scope-analyzer (map affected files) → impl-designer (plan implementation) → test-planner (plan test coverage). Use the /new-feature skill for the full pipeline."}
EOF
  elif [ "$HAS_BUG_KEYWORDS" -gt 0 ]; then
    cat <<EOF
{"systemMessage": "Bug investigation detected. Consider spawning: scope-analyzer (map affected area) → security-checker (check for vulnerability). Follow the bugfix formula: investigate → reproduce → fix → test → commit."}
EOF
  elif [ "$HAS_REFACTOR_KEYWORDS" -gt 0 ]; then
    cat <<EOF
{"systemMessage": "Refactoring request detected. Consider spawning: scope-analyzer (map dependencies) → arch-reviewer (validate architecture changes). Ensure test coverage before refactoring."}
EOF
  fi
fi

exit 0
