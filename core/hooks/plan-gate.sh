#!/usr/bin/env bash
# plan-gate.sh
# PreToolUse gate (Edit|Write + Bash `git commit`): enforce plan-first.
#
# The planner/advisor must present a plan for USER review before any code is
# written. This gate blocks code Edit/Write and `git commit` until an APPROVED
# plan exists for the repo. Approval = a marker file whose stored hash matches
# the current plan file's content hash, so editing the plan re-arms the gate
# (you must re-approve a changed plan).
#
# Not gated: docs/config/data files, anything under .claude/, memory/,
# scratchpad/, /tmp/, and repos that opt out via .claude/plans/.plan-gate-off.
# Bash commits also honor PLAN_GATE_BYPASS=1.
#
# Exit 2 = block (with JSON reason), Exit 0 = allow.
set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

PLAN_REL=".claude/plans/current-plan.md"
MARKER_REL=".claude/plans/.plan-approved"
OFF_REL=".claude/plans/.plan-gate-off"

resolve_repo() { git -C "$1" rev-parse --show-toplevel 2>/dev/null || true; }

is_code_file() {
  case "$1" in
    *.md|*.mdx|*.json|*.jsonc|*.yml|*.yaml|*.toml|*.cfg|*.ini|*.txt|*.csv|\
*.lock|*.env|*.example|*.gitignore|*.editorconfig) return 1 ;;
    *) return 0 ;;
  esac
}

REPO=""
case "$TOOL" in
  Edit|Write)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    [ -n "$FILE" ] || exit 0
    case "$FILE" in
      */.claude/*|*/memory/*|*/scratchpad/*|/tmp/*) exit 0 ;;
    esac
    is_code_file "$FILE" || exit 0
    REPO=$(resolve_repo "$(dirname "$FILE")")
    ;;
  Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    echo "$CMD" | grep -qE '(^|&&|;|\|)[[:space:]]*git[[:space:]]+commit' || exit 0
    [ "${PLAN_GATE_BYPASS:-0}" = "1" ] && exit 0
    # The hook's .cwd is the SESSION dir, not an inline `cd` inside the command.
    # Prefer a leading `cd <path>` target so `cd <repo> && git commit` gates the
    # repo actually being committed.
    cdpath=$(echo "$CMD" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^ &;|]+).*/\1/p' | head -1)
    case "$cdpath" in "~"*) cdpath="${HOME}${cdpath#\~}" ;; esac
    if [ -n "$cdpath" ] && [ -d "$cdpath" ]; then
      REPO=$(resolve_repo "$cdpath")
    else
      REPO=$(resolve_repo "${CWD:-$PWD}")
    fi
    ;;
  *) exit 0 ;;
esac

# Not inside a git repo -> nothing to gate.
[ -n "$REPO" ] || exit 0
# Per-repo opt out.
[ -f "$REPO/$OFF_REL" ] && exit 0

PLAN="$REPO/$PLAN_REL"
MARKER="$REPO/$MARKER_REL"

if [ -f "$PLAN" ] && [ -f "$MARKER" ]; then
  cur=$(sha256sum "$PLAN" | awk '{print $1}')
  saved=$(awk 'NR==1{print $1}' "$MARKER" 2>/dev/null || true)
  [ -n "$cur" ] && [ "$cur" = "$saved" ] && exit 0
fi

reason="PLAN GATE — no approved plan for repo ${REPO}.\n\nThe planner/advisor must present a plan for USER review before any code is written.\n\nFlow:\n  1. Write the plan to ${PLAN}\n  2. Present it to the user and get explicit approval.\n  3. After the user approves, run:\n       bash ~/.claude/hooks/plan-approve.sh \"${REPO}\"\n     (records the plan's content hash; editing the plan later re-arms the gate)\n\nBypass for genuinely trivial / no-plan work:\n  touch ${REPO}/${OFF_REL}"

jq -cn --arg r "$reason" '{decision: "block", reason: $r}'
exit 2
