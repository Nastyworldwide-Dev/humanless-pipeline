#!/bin/bash
# PostToolUse hook: auto-spawns app-specific domain reviewers after commits
# PROJECT-AWARE: Uses project-detect.sh + project-registry.json for dynamic agent lookup
# Works for any app with reviewer config in registry

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Only match Bash tool with successful git commit commands
[ "$TOOL_NAME" = "Bash" ] || exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0
[ "$EXIT_CODE" = "0" ] || exit 0

# Source project detection library
LIB_DIR="$HOME/.claude/hooks/lib"
if [ -f "$LIB_DIR/project-detect.sh" ]; then
  source "$LIB_DIR/project-detect.sh"
else
  exit 0  # Can't route without library
fi

# Only works in frappe-bench context
[ "$PD_IS_FRAPPE_BENCH" = "1" ] || exit 0

# Get changed files from last commit
CHANGED_FILES=""
if [ -n "$CWD" ]; then
  CHANGED_FILES=$(cd "$CWD" && git diff --name-only HEAD~1..HEAD 2>/dev/null || echo "")
fi
[ -n "$CHANGED_FILES" ] || exit 0

# Detect which app(s) were changed
CHANGED_APPS=""
while IFS= read -r file; do
  app=$(pd_get_app_for_file "$PD_BENCH_ROOT/apps/$file" 2>/dev/null)
  [ -z "$app" ] && continue
  echo "$CHANGED_APPS" | grep -qw "$app" || CHANGED_APPS="$CHANGED_APPS $app"
done <<< "$CHANGED_FILES"

CHANGED_APPS=$(echo "$CHANGED_APPS" | xargs)
[ -n "$CHANGED_APPS" ] || exit 0

# For each changed app, look up reviewers in registry
ALL_AGENTS=()

for app in $CHANGED_APPS; do
  REVIEWER_JSON=$(pd_get_reviewers "$app")
  [ -n "$REVIEWER_JSON" ] && [ "$REVIEWER_JSON" != "null" ] || continue

  MAX_CONCURRENT=$(pd_get_reviewer_max_concurrent "$app")
  REVIEWER_TYPES=$(pd_get_reviewer_agents "$app")
  [ -n "$REVIEWER_TYPES" ] || continue

  APP_FILE_COUNT=$(echo "$CHANGED_FILES" | grep "$app/" | wc -l)

  if [ "$APP_FILE_COUNT" -le 1 ]; then
    SINGLE_FILE=$(echo "$CHANGED_FILES" | grep "$app/" | head -1)
    if ! echo "$SINGLE_FILE" | grep -qE '(hooks\.py|feature_flag|api\.py|permission)'; then
      continue
    fi
  fi

  APP_AGENTS=()
  for rtype in $REVIEWER_TYPES; do
    PATTERN=$(pd_get_reviewer_pattern "$app" "$rtype")
    [ -n "$PATTERN" ] || continue

    while IFS= read -r file; do
      if pd_file_matches_pattern "$file" "$PATTERN"; then
        APP_AGENTS+=("${app}-${rtype}-reviewer")
        break
      fi
    done <<< "$(echo "$CHANGED_FILES" | grep "$app/")"
  done

  COUNT=0
  for agent in "${APP_AGENTS[@]}"; do
    [ $COUNT -ge "$MAX_CONCURRENT" ] && break
    ALL_AGENTS+=("$agent")
    COUNT=$((COUNT + 1))
  done
done

[ ${#ALL_AGENTS[@]} -eq 0 ] && exit 0

DIFF_RANGE="HEAD~1..HEAD"
SPAWN_MSGS=""
for agent in "${ALL_AGENTS[@]}"; do
  SPAWN_MSGS="${SPAWN_MSGS} Spawn ${agent} agent (subagent_type=\"${agent}\", run_in_background: true) with prompt: \"Review diff ${DIFF_RANGE} for app-specific patterns. Report findings with BLOCKING: yes/no.\""
done

echo "{\"systemMessage\": \"MANDATORY HOOK: Custom app files changed in this commit.${SPAWN_MSGS} Execute immediately — these run in parallel with frappe-reviewer.\"}"
exit 0
