#!/usr/bin/env bash
# Deploy Gate Hook — PreToolUse (Bash)
# Blocks deploy-phase commands for non-admin users.
# Admin users are defined in ~/.claude/config/deploy-permissions.json
#
# Exit 0 = allow, Exit 2 = block with reason

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -n "$COMMAND" ] || exit 0

# --- Detect if this is a deploy-phase command ---
IS_DEPLOY=false

if echo "$COMMAND" | grep -qE 'bench.*(migrate|backup.*--with-files|clear-cache|clear-website-cache|setup)'; then
  IS_DEPLOY=true
elif echo "$COMMAND" | grep -qE 'git push --follow-tags'; then
  IS_DEPLOY=true
elif echo "$COMMAND" | grep -qE 'npm version (patch|minor|major)'; then
  IS_DEPLOY=true
elif echo "$COMMAND" | grep -qE 'electron-builder'; then
  IS_DEPLOY=true
elif echo "$COMMAND" | grep -qE 'bunx turbo run build|bun run build'; then
  IS_DEPLOY=true
fi

$IS_DEPLOY || exit 0

# --- Check admin authorization ---
PERMS_FILE="$HOME/.claude/config/deploy-permissions.json"
CURRENT_USER=$(whoami)

# Emergency override (must be set explicitly in environment)
if [ "${DEPLOY_ADMIN_OVERRIDE:-}" = "1" ]; then
  logger -t deploy-gate "OVERRIDE: User '$CURRENT_USER' used DEPLOY_ADMIN_OVERRIDE for: $COMMAND"
  exit 0
fi

IS_ADMIN=false

if [ -f "$PERMS_FILE" ] && command -v jq &>/dev/null; then
  # Check admin_users array
  MATCH=$(jq -r --arg u "$CURRENT_USER" \
    '.admin_users // [] | map(select(. == $u)) | length' \
    "$PERMS_FILE" 2>/dev/null || echo "0")
  [ "${MATCH:-0}" -gt "0" ] && IS_ADMIN=true

  # Check root_is_always_admin flag (default true if key missing)
  if [ "$CURRENT_USER" = "root" ]; then
    ROOT_FLAG=$(jq -r 'if has("root_is_always_admin") then .root_is_always_admin else true end' "$PERMS_FILE" 2>/dev/null || echo "true")
    [ "$ROOT_FLAG" = "true" ] && IS_ADMIN=true
  fi
else
  # No config or no jq: default — only root is admin
  [ "$CURRENT_USER" = "root" ] && IS_ADMIN=true
fi

$IS_ADMIN && exit 0

# --- Not admin: block and create pending record ---
PENDING_DIR="$HOME/.claude/pipeline/deploy-pending"
mkdir -p "$PENDING_DIR"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')

# Write pending deploy record
PENDING_FILE="$PENDING_DIR/pending-${TIMESTAMP}.json"
if command -v jq &>/dev/null; then
  jq -n \
    --arg user "$CURRENT_USER" \
    --arg cmd "$COMMAND" \
    --arg cwd "$CWD" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{user: $user, command: $cmd, cwd: $cwd, timestamp: $ts, status: "pending_approval"}' \
    > "$PENDING_FILE"
else
  echo "{\"user\":\"$CURRENT_USER\",\"command\":\"$COMMAND\",\"cwd\":\"$CWD\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"status\":\"pending_approval\"}" > "$PENDING_FILE"
fi

logger -t deploy-gate "BLOCKED: User '$CURRENT_USER' attempted deploy in '$CWD': $COMMAND"

# --- Build notification instruction based on configured channel ---
NOTIFY_CHANNEL="file"
ADMIN_CONTACT=""
if [ -f "$PERMS_FILE" ] && command -v jq &>/dev/null; then
  NOTIFY_CHANNEL=$(jq -r '.notification.channel // "file"' "$PERMS_FILE" 2>/dev/null || echo "file")
  ADMIN_CONTACT=$(jq -r '.notification.admin_contact // ""' "$PERMS_FILE" 2>/dev/null || echo "")
fi

SUPERSET_URL=""
if [ -f "$PERMS_FILE" ] && command -v jq &>/dev/null; then
  SUPERSET_URL=$(jq -r '.notification.superset_url // ""' "$PERMS_FILE" 2>/dev/null || echo "")
fi

case "$NOTIFY_CHANNEL" in
  superset)
    # POST to Superset's deploy-blocked webhook (local VPS call, no auth needed)
    HOOK_URL="${SUPERSET_URL:-http://localhost:3001}/hook/deploy-blocked"
    PAYLOAD=$(jq -n \
      --arg user "$CURRENT_USER" \
      --arg cmd "$COMMAND" \
      --arg cwd "$CWD" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{user: $user, command: $cmd, cwd: $cwd, timestamp: $ts}')
    curl -s -X POST "$HOOK_URL" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      --connect-timeout 3 --max-time 5 \
      > /dev/null 2>&1 || true
    NOTIFY_MSG="Deploy-blocked notification sent to Superset at ${HOOK_URL}. The admin will see it in the Superset dashboard."
    ;;
  slack)
    NOTIFY_MSG="MANDATORY: Use Slack MCP to send a message to '${ADMIN_CONTACT}': 'Deploy approval needed — user ${CURRENT_USER} in ${CWD}. Command: ${COMMAND}. Pending record: ${PENDING_FILE}'"
    ;;
  github)
    NOTIFY_MSG="MANDATORY: Use GitHub MCP to create an issue on '${ADMIN_CONTACT}' titled 'Deploy Approval Required: ${CWD##*/}' with body: 'User ${CURRENT_USER} attempted deploy. Command: \`${COMMAND}\`. Approve by adding user to admin_users in deploy-permissions.json or run with DEPLOY_ADMIN_OVERRIDE=1.'"
    ;;
  *)
    NOTIFY_MSG="A pending deploy record has been saved to ${PENDING_FILE}. Inform the user that deploy requires admin approval. An admin can approve by adding '${CURRENT_USER}' to admin_users in ${PERMS_FILE}."
    ;;
esac

cat <<EOF
{"decision": "block", "reason": "DEPLOY BLOCKED: User '${CURRENT_USER}' is not authorized to deploy.\n\nCommand: ${COMMAND}\nWorking directory: ${CWD}\n\nPending deploy record saved to:\n  ${PENDING_FILE}\n\n${NOTIFY_MSG}\n\nTo grant deploy access:\n  1. Add '${CURRENT_USER}' to admin_users in ${PERMS_FILE}\n  2. Or set DEPLOY_ADMIN_OVERRIDE=1 for one-time override"}
EOF
exit 2
