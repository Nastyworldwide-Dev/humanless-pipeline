#!/usr/bin/env bash
# plan-approve.sh
# Records USER approval of the current plan by storing its content hash, which
# unblocks plan-gate.sh for the repo. Run ONLY after the user has explicitly
# approved the plan you presented. Editing the plan afterwards invalidates the
# approval (hash mismatch) and re-arms the gate.
#
# Usage: plan-approve.sh [REPO_ROOT]   (defaults to the current git repo)
set -euo pipefail

REPO="${1:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [ -z "$REPO" ]; then
  echo "plan-approve: not in a git repo and no repo path given" >&2
  exit 1
fi

PLAN="$REPO/.claude/plans/current-plan.md"
if [ ! -f "$PLAN" ]; then
  echo "plan-approve: no plan at $PLAN — write the plan first" >&2
  exit 1
fi

mkdir -p "$REPO/.claude/plans"
h=$(sha256sum "$PLAN" | awk '{print $1}')
printf '%s  approved_at=%s\n' "$h" "$(date -u +%FT%TZ)" > "$REPO/.claude/plans/.plan-approved"
echo "plan-approve: approved plan for $REPO (hash ${h:0:12}…)"
