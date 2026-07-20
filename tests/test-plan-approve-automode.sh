#!/usr/bin/env bash
# Functional test for plan-approve.sh autonomous-mode gate:
# PIPELINE_AUTONOMOUS=1 requires .claude/plans/clarify-record.md with
# 'BLOCKERS: 0'; interactive mode is unaffected.
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPROVE="$REPO_DIR/core/hooks/plan-approve.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { echo "  PASS: $1"; }
die()  { echo "  FAIL: $1"; fail=1; }

mkrepo() { # $1 dir — git repo with a complete (MOCKUP + EXPECTED OUTPUT) plan
  mkdir -p "$1/.claude/plans" && cd "$1" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  cat > .claude/plans/current-plan.md <<'PLAN'
# Plan: test
MOCKUP: NOT NEEDED (backend only)
## EXPECTED OUTPUT
A passing test.
PLAN
}

# 1. Interactive mode (no flag): approves without any clarify record.
mkrepo "$TMP/r1"
if PIPELINE_AUTONOMOUS=0 bash "$APPROVE" "$TMP/r1" >/dev/null 2>&1; then
  pass "interactive mode approves without clarify record"
else
  die "interactive mode should approve without clarify record"
fi

# 2. Auto mode without clarify record: refused.
mkrepo "$TMP/r2"
if PIPELINE_AUTONOMOUS=1 bash "$APPROVE" "$TMP/r2" >/dev/null 2>&1; then
  die "auto mode should refuse without clarify record"
else
  pass "auto mode refuses without clarify record"
fi

# 3. Auto mode with clarify record but unresolved BLOCKERs: refused.
mkrepo "$TMP/r3"
cat > "$TMP/r3/.claude/plans/clarify-record.md" <<'REC'
| Question | State | Evidence |
| Which role? | BLOCKER | cannot determine |
BLOCKERS: 1
REC
if PIPELINE_AUTONOMOUS=1 bash "$APPROVE" "$TMP/r3" >/dev/null 2>&1; then
  die "auto mode should refuse with BLOCKERS: 1"
else
  pass "auto mode refuses with unresolved BLOCKERs"
fi

# 4. Auto mode with clean ledger (BLOCKERS: 0): approves.
mkrepo "$TMP/r4"
cat > "$TMP/r4/.claude/plans/clarify-record.md" <<'REC'
| Question | State | Evidence |
| Which role? | RESOLVED | schema read |
BLOCKERS: 0
REC
if PIPELINE_AUTONOMOUS=1 bash "$APPROVE" "$TMP/r4" >/dev/null 2>&1; then
  pass "auto mode approves with BLOCKERS: 0 ledger"
else
  die "auto mode should approve with clean ledger"
fi

# 5. Auto mode with a record missing the summary line: refused (machine check).
mkrepo "$TMP/r5"
cat > "$TMP/r5/.claude/plans/clarify-record.md" <<'REC'
| Question | State | Evidence |
| Which role? | RESOLVED | schema read |
REC
if PIPELINE_AUTONOMOUS=1 bash "$APPROVE" "$TMP/r5" >/dev/null 2>&1; then
  die "auto mode should refuse a ledger without the BLOCKERS: n line"
else
  pass "auto mode refuses ledger missing BLOCKERS line"
fi

exit $fail
