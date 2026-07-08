#!/bin/bash
# PostToolUse hook: auto-triggers code review after successful git commits
# Uses frappe-reviewer for Frappe apps, generic requesting-code-review skill for others
# Spawns dependency-checker when dependency files change

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // empty')

# Only match Bash tool with git commit commands
[ "$TOOL_NAME" = "Bash" ] || exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

# Only on successful commits
[ "$EXIT_CODE" = "0" ] || exit 0

# --- Check if trivial commit (skip review) ---
COMMIT_MSG=$(echo "$COMMAND" | grep -oP '(?<=-m\s)["\x27](.+?)["\x27]' | head -1 | sed "s/^[\"']//;s/[\"']$//")
COMMIT_TYPE=$(echo "$COMMIT_MSG" | grep -oP '^\w+(?=[:(\s])' | head -1)

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
FILE_COUNT=0
if [ -n "$CWD" ]; then
  FILE_COUNT=$(cd "$CWD" && git diff --name-only HEAD~1..HEAD 2>/dev/null | wc -l || echo "0")
fi

# Skip review for trivial commits: <=2 files AND chore/docs/style type
case "$COMMIT_TYPE" in
  chore|docs|style)
    if [ "$FILE_COUNT" -le 2 ]; then
      exit 0
    fi
    ;;
esac

# --- Detect app type for reviewer selection ---
REVIEWER_MSG=""
IS_FRAPPE_APP=false
if [ -n "$CWD" ]; then
  # Check if CWD is inside a Frappe app (has hooks.py in a parent dir)
  CHECK_DIR="$CWD"
  while [ "$CHECK_DIR" != "/" ]; do
    if [ -f "$CHECK_DIR/hooks.py" ]; then
      IS_FRAPPE_APP=true
      break
    fi
    CHECK_DIR=$(dirname "$CHECK_DIR")
  done
fi

if [ "$IS_FRAPPE_APP" = true ]; then
  # Frappe project: use specialized frappe-reviewer agent
  REVIEWER_MSG='MANDATORY HOOK: Commit succeeded. Spawn frappe-reviewer agent NOW (subagent_type="frappe-reviewer", run_in_background: true) with prompt: "Review diff HEAD~1..HEAD. Report Critical/Warning/Suggestion findings. End with NEXT_ACTION: DEPLOY or NEXT_ACTION: FIX_CRITICAL." Execute immediately.'
else
  # Generic project: use the requesting-code-review skill
  REVIEWER_MSG='MANDATORY HOOK: Commit succeeded. Run requesting-code-review skill NOW for HEAD~1..HEAD. Execute immediately.'
fi

# --- Check for cross-app impact ---
CROSS_APP_MSG=""
if [ -n "$CWD" ]; then
  CHANGED_FILES=$(cd "$CWD" && git diff --name-only HEAD~1..HEAD 2>/dev/null || echo "")
  if echo "$CHANGED_FILES" | grep -qE '(doc_events/|hooks\.py|api\.py|customisations/|fixtures/)'; then
    CROSS_APP_MSG=' ALSO MANDATORY: Spawn cross-app-impact agent (subagent_type="cross-app-impact", run_in_background: true) in parallel with the reviewer.'
  fi
fi

# --- Check for security-sensitive changes ---
SECURITY_MSG=""
if [ -n "$CWD" ]; then
  if echo "$CHANGED_FILES" | grep -qE '(api\.py|auth|permission|whitelist|login|session|password|token|secret)'; then
    SECURITY_MSG=' ALSO MANDATORY: Spawn security-reviewer agent (subagent_type="security-reviewer", run_in_background: true) with prompt: "Security review diff HEAD~1..HEAD. Check for SQL injection, permission bypass, XSS, hardcoded secrets, SSRF, mass assignment. End with VERDICT and BLOCKING: yes/no."'
  fi
fi

# --- Check for front-end design changes ---
DESIGN_MSG=""
if [ -n "$CWD" ]; then
  # Detect project type via project-detect library
  HOOKS_LIB="$HOME/.claude/hooks/lib/project-detect.sh"
  APP_TYPE="generic"
  if [ -f "$HOOKS_LIB" ]; then
    PD_PROJECT_ROOT="$CWD"
    source "$HOOKS_LIB"
    APP_TYPE="$PD_PROJECT_TYPE"
  fi

  # Match front-end files based on app type
  DESIGN_MATCH=""
  case "$APP_TYPE" in
    react-ts|monorepo|electron|node)
      echo "$CHANGED_FILES" | grep -qE '\.(css|scss|less|tsx|jsx|vue|svelte|html)$|tailwind\.config|theme\.|tokens\.|\.styled\.|\.module\.css' && DESIGN_MATCH="yes"
      ;;
    android)
      echo "$CHANGED_FILES" | grep -qE '(res/layout|res/drawable|res/values|res/color|Theme|Color|Style|ui/|\.compose\.)' && DESIGN_MATCH="yes"
      ;;
    frappe-bench)
      echo "$CHANGED_FILES" | grep -qE '\.(css|scss|html|js|jsx|ts|tsx)$' && DESIGN_MATCH="yes"
      ;;
    *)
      echo "$CHANGED_FILES" | grep -qE '\.(css|scss|less|tsx|jsx|vue|svelte|html)$|tailwind\.config|theme\.|tokens\.' && DESIGN_MATCH="yes"
      ;;
  esac

  if [ -n "$DESIGN_MATCH" ]; then
    DESIGN_MSG=" ALSO MANDATORY: Spawn design-reviewer agent (subagent_type=\"design-reviewer\", run_in_background: true) with prompt: \"Design review diff HEAD~1..HEAD. Project type: ${APP_TYPE}. Check design tokens, accessibility (WCAG 2.1 AA), responsive patterns, theming, CSS best practices. Apply ${APP_TYPE}-specific checks. End with VERDICT: DESIGN_APPROVED or FIX_WARNINGS or FIX_CRITICAL.\""
  fi
fi

# --- Check for dependency changes ---
DEP_CHECK_MSG=""
if [ -n "$CWD" ]; then
  if echo "$CHANGED_FILES" | grep -qE '(requirements\.txt|pyproject\.toml|setup\.py|setup\.cfg|package\.json)'; then
    DEP_CHECK_MSG=' ALSO MANDATORY: Spawn dependency-checker agent (subagent_type="dependency-checker", run_in_background: true) in parallel.'
  fi
fi

echo "{\"systemMessage\": \"${REVIEWER_MSG}${CROSS_APP_MSG}${SECURITY_MSG}${DESIGN_MSG}${DEP_CHECK_MSG}\"}"
exit 0
