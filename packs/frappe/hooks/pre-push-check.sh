#!/bin/bash
# PreToolUse hook: advisory safety check before git push
# Checks for debug artifacts in committed code
# Does NOT block (exit 0 always) — advisory only via systemMessage

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only match Bash tool with git push commands
[ "$TOOL_NAME" = "Bash" ] || exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+push' || exit 0

# Detect CWD
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# Check diff for debug artifacts (last 5 commits vs remote)
REMOTE_BRANCH=$(cd "$CWD" && git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
if [ -z "$REMOTE_BRANCH" ]; then
  DIFF_RANGE="HEAD~1..HEAD"
else
  DIFF_RANGE="${REMOTE_BRANCH}..HEAD"
fi

DEBUG_ARTIFACTS=""
DIFF_OUTPUT=$(cd "$CWD" && git diff "$DIFF_RANGE" --unified=0 2>/dev/null || echo "")

if [ -n "$DIFF_OUTPUT" ]; then
  ADDED_LINES=$(echo "$DIFF_OUTPUT" | grep '^+' | grep -v '^+++')

  if echo "$ADDED_LINES" | grep -qE 'console\.log\('; then
    DEBUG_ARTIFACTS="${DEBUG_ARTIFACTS}\n  - console.log() found"
  fi
  if echo "$ADDED_LINES" | grep -qE '^\+.*\bprint\(' | grep -vE '(print_format|print_settings|print_designer|print_style)'; then
    DEBUG_ARTIFACTS="${DEBUG_ARTIFACTS}\n  - print() statement found (verify it's not debug)"
  fi
  if echo "$ADDED_LINES" | grep -qE '\bdebugger\b'; then
    DEBUG_ARTIFACTS="${DEBUG_ARTIFACTS}\n  - debugger statement found"
  fi
  if echo "$ADDED_LINES" | grep -qE 'pdb\.set_trace|breakpoint\(\)'; then
    DEBUG_ARTIFACTS="${DEBUG_ARTIFACTS}\n  - Python debugger breakpoint found"
  fi

  # Check for WIP commits
  WIP_COMMITS=$(cd "$CWD" && git log "$DIFF_RANGE" --oneline 2>/dev/null | grep -iE '^\w+ (wip|fixup|squash)' || true)
  if [ -n "$WIP_COMMITS" ]; then
    DEBUG_ARTIFACTS="${DEBUG_ARTIFACTS}\n  - WIP/fixup commits found: $(echo "$WIP_COMMITS" | head -3)"
  fi
fi

if [ -n "$DEBUG_ARTIFACTS" ]; then
  echo "{\"systemMessage\": \"PRE-PUSH WARNING: Potential debug artifacts detected in code being pushed:${DEBUG_ARTIFACTS}\nConsider cleaning these up before pushing. Proceeding anyway since this is advisory only.\"}"
fi

exit 0
