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

# --- Deterministic pre-gates: run BEFORE any LLM reviewer spawns ---
# Failures short-circuit the review entirely (no LLM spend on commits that
# fail lint/schema/syntax); the orchestrator fixes and re-commits, which
# re-triggers this hook.
PRE_GATES="$HOME/.claude/hooks/lib/pre-gates.sh"
if [ -n "$CWD" ] && [ -x "$PRE_GATES" ]; then
  PG_OUT=$(bash "$PRE_GATES" "$CWD" "HEAD~1..HEAD" 2>&1)
  if [ $? -ne 0 ]; then
    jq -n --arg out "$(echo "$PG_OUT" | tail -15)" \
      '{systemMessage: ("PRE-GATES FAILED — deterministic checks are authoritative and run before any LLM review. Fix these and re-commit (review re-triggers automatically). Do NOT spawn reviewers for this commit.\n" + $out)}'
    exit 0
  fi
fi

# --- Detect app type for reviewer selection ---
REVIEWER_MSG=""
IS_FRAPPE_APP=false
IS_ANDROID_APP=false
if [ -n "$CWD" ]; then
  # Check if CWD is inside a Frappe app (has hooks.py in a parent dir)
  # or an Android app (build.gradle.kts + app/src in a parent dir)
  CHECK_DIR="$CWD"
  while [ "$CHECK_DIR" != "/" ]; do
    if [ -f "$CHECK_DIR/hooks.py" ]; then
      IS_FRAPPE_APP=true
      break
    fi
    if [ -f "$CHECK_DIR/build.gradle.kts" ] && [ -d "$CHECK_DIR/app/src" ]; then
      IS_ANDROID_APP=true
      break
    fi
    CHECK_DIR=$(dirname "$CHECK_DIR")
  done
fi

if [ "$IS_FRAPPE_APP" = true ]; then
  # Frappe project: use specialized frappe-reviewer agent
  REVIEWER_MSG='MANDATORY HOOK: Commit succeeded. Spawn frappe-reviewer agent NOW (subagent_type="frappe-reviewer", run_in_background: true) with prompt: "Review diff HEAD~1..HEAD. Report Critical/Warning/Suggestion findings. End with NEXT_ACTION: DEPLOY or NEXT_ACTION: FIX_CRITICAL." Execute immediately.'
elif [ "$IS_ANDROID_APP" = true ]; then
  # Android project: use specialized android-reviewer agent (same retry
  # contract as frappe: FIX_CRITICAL -> fix, re-commit, review re-triggers)
  REVIEWER_MSG='MANDATORY HOOK: Commit succeeded. Spawn android-reviewer agent NOW (subagent_type="android-reviewer", run_in_background: true) with prompt: "Review diff HEAD~1..HEAD. Report Critical/Warning/Suggestion findings. End with NEXT_ACTION: DEPLOY or NEXT_ACTION: FIX_CRITICAL." If the verdict is FIX_CRITICAL: fix the findings and re-commit — this review re-triggers automatically; repeat until DEPLOY. Execute immediately.'
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
  if echo "$CHANGED_FILES" | grep -qE '(api\.py|auth|permission|whitelist|login|session|password|token|secret|AndroidManifest\.xml|network_security|[Kk]eystore|[Cc]rypto|WebView)'; then
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
    # Mockup contract: if the approved plan embeds a mockup, the design review
    # must compare the implementation against it (the mockup is the design contract).
    CONTRACT_MSG=""
    GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
    PLAN_FILE="$GIT_ROOT/.claude/plans/current-plan.md"
    if [ -f "$PLAN_FILE" ]; then
      MOCKUP_REF=$(grep -oE '/[A-Za-z0-9._/-]+/mockup-[A-Za-z0-9._-]+\.html' "$PLAN_FILE" | head -1 || true)
      if [ -n "$MOCKUP_REF" ] && [ -f "$MOCKUP_REF" ]; then
        CONTRACT_MSG=" MOCKUP CONTRACT: ${MOCKUP_REF} — compare the implemented UI against this approved mockup (palette, typography, spacing, layout, states) and report every deviation as a finding."
      fi
    fi
    DESIGN_MSG=" ALSO MANDATORY: Spawn design-reviewer agent (subagent_type=\"design-reviewer\", run_in_background: true) with prompt: \"Design review diff HEAD~1..HEAD. Project type: ${APP_TYPE}. Check design tokens, accessibility (WCAG 2.1 AA), responsive patterns, theming, CSS best practices. Apply ${APP_TYPE}-specific checks.${CONTRACT_MSG} End with VERDICT: DESIGN_APPROVED or FIX_WARNINGS or FIX_CRITICAL.\""
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
