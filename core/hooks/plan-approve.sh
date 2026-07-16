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

# --- Plan completeness: a presentable plan embeds its deliverables ----------
# 1) EXPECTED OUTPUT section — what the user sees/gets when the work is done.
if ! grep -qiE '^[[:space:]]*(#+[[:space:]]*)?EXPECTED OUTPUT' "$PLAN"; then
  echo "plan-approve: REFUSED — plan has no EXPECTED OUTPUT section." >&2
  echo "  Add 'EXPECTED OUTPUT:' (UI result, code changed, how it ships), then re-present." >&2
  exit 1
fi

# 2) MOCKUP section — either a BUILT mockup (file must exist on disk) or an
#    explicit NOT NEEDED with a reason. A promised-but-unbuilt mockup refuses.
if ! grep -qiE '^[[:space:]]*(#+[[:space:]]*)?MOCKUP' "$PLAN"; then
  echo "plan-approve: REFUSED — plan has no MOCKUP section." >&2
  echo "  UI feature: spawn mockup-builder, embed 'MOCKUP: \$HOME/mockups/mockup-<name>.html' (resolved absolute path)." >&2
  echo "  Non-UI:     add 'MOCKUP: NOT NEEDED (<reason>)'." >&2
  exit 1
fi
# Any absolute path ending in .../mockup-<name>.html (covers ~/mockups and legacy /tmp).
mockup_path=$(grep -oE '/[A-Za-z0-9._/-]+/mockup-[A-Za-z0-9._-]+\.html' "$PLAN" | head -1 || true)
[ -z "$mockup_path" ] && mockup_path=$(grep -oE '/tmp/mockup-[A-Za-z0-9._-]+\.html' "$PLAN" | head -1 || true)
if [ -n "$mockup_path" ]; then
  if [ ! -f "$mockup_path" ]; then
    echo "plan-approve: REFUSED — plan references $mockup_path but the file does not exist." >&2
    echo "  Build the mockup (mockup-builder) BEFORE presenting the plan for approval." >&2
    exit 1
  fi
elif ! grep -iE '^[[:space:]]*(#+[[:space:]]*)?MOCKUP' "$PLAN" | grep -qiE 'NOT NEEDED|N/A'; then
  echo "plan-approve: REFUSED — MOCKUP section has neither an absolute mockup-*.html path nor 'NOT NEEDED (<reason>)'." >&2
  exit 1
fi

mkdir -p "$REPO/.claude/plans"
h=$(sha256sum "$PLAN" | awk '{print $1}')
printf '%s  approved_at=%s\n' "$h" "$(date -u +%FT%TZ)" > "$REPO/.claude/plans/.plan-approved"
echo "plan-approve: approved plan for $REPO (hash ${h:0:12}…)"
