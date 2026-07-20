#!/usr/bin/env bash
# Functional test for the SDD gates: plan-approve's /analyze consistency pass
# and tdd-gate's spec traceability block.
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPROVE="$REPO_DIR/core/hooks/plan-approve.sh"
TDD_GATE="$REPO_DIR/core/hooks/tdd-gate.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { echo "  PASS: $1"; }
die()  { echo "  FAIL: $1"; fail=1; }

mkrepo() { # $1 dir
  mkdir -p "$1/.claude/plans" && cd "$1" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  cat > .claude/plans/current-plan.md <<'PLAN'
# Plan: test
MOCKUP: NOT NEEDED (backend only)
## EXPECTED OUTPUT
A passing test.
PLAN
}

spec() { # $1 repo  $2 mapping_row  $3 property_line
  cat > "$1/.claude/plans/spec-feature.md" <<SPEC
# Spec: feature
## Requirements
- REQ-1: valid input is accepted
## REQ ↔ Test mapping
| REQ | Test |
|-----|------|
$2
$3
## End
SPEC
}

tdd_gate_json() { # $1 cwd — feed a feat commit through the gate
  jq -n --arg cwd "$1" '{tool_input: {command: "git commit -m \"feat: x\""}, cwd: $cwd}'
}

# 1. plan-approve: spec with unmapped REQ -> refused
mkrepo "$TMP/r1"
spec "$TMP/r1" "" "PROPERTY TESTS: N/A (glue)"
if bash "$APPROVE" "$TMP/r1" >/dev/null 2>&1; then
  die "unmapped REQ should refuse approval"
else
  pass "unmapped REQ refuses approval"
fi

# 2. plan-approve: fully mapped spec -> approved
mkrepo "$TMP/r2"
spec "$TMP/r2" "| REQ-1 | tests/test_f.py |" "PROPERTY TESTS: N/A (glue)"
if bash "$APPROVE" "$TMP/r2" >/dev/null 2>&1; then
  pass "mapped spec approves"
else
  die "mapped spec should approve"
fi

# 3. plan-approve: constitution present but no CONSTITUTION: PASS -> refused
mkrepo "$TMP/r3"
echo "- C-1: no prod DB" > "$TMP/r3/.claude/constitution.md"
spec "$TMP/r3" "| REQ-1 | tests/test_f.py |" "PROPERTY TESTS: N/A (glue)"
if bash "$APPROVE" "$TMP/r3" >/dev/null 2>&1; then
  die "missing CONSTITUTION: PASS should refuse when constitution exists"
else
  pass "missing constitution assertion refuses approval"
fi

# 4. plan-approve: missing PROPERTY TESTS line -> refused
mkrepo "$TMP/r4"
spec "$TMP/r4" "| REQ-1 | tests/test_f.py |" ""
if bash "$APPROVE" "$TMP/r4" >/dev/null 2>&1; then
  die "missing PROPERTY TESTS line should refuse"
else
  pass "missing PROPERTY TESTS line refuses approval"
fi

# 5. tdd-gate: spec maps REQ to a missing test file -> BLOCK (exit 2)
mkrepo "$TMP/r5"
spec "$TMP/r5" "| REQ-1 | tests/test_f.py |" "PROPERTY TESTS: N/A (glue)"
echo "code" > "$TMP/r5/mod.py" && (cd "$TMP/r5" && git add -A)
tdd_gate_json "$TMP/r5" | bash "$TDD_GATE" >/dev/null 2>&1
RC=$?
[ "$RC" = "2" ] && pass "tdd-gate blocks on missing mapped test file" || die "expected exit 2, got $RC"

# 6. tdd-gate: mapping satisfied (file exists with assertion) -> allow
mkrepo "$TMP/r6"
mkdir -p "$TMP/r6/tests"
echo "def test_f(): assert True" > "$TMP/r6/tests/test_f.py"
spec "$TMP/r6" "| REQ-1 | tests/test_f.py |" "PROPERTY TESTS: N/A (glue)"
echo "code" > "$TMP/r6/mod.py" && (cd "$TMP/r6" && git add -A)
tdd_gate_json "$TMP/r6" | bash "$TDD_GATE" >/dev/null 2>&1
RC=$?
[ "$RC" = "0" ] && pass "tdd-gate allows fully mapped spec" || die "expected exit 0, got $RC"

# 7. tdd-gate: PROPERTY TESTS REQUIRED but no property marker -> BLOCK
mkrepo "$TMP/r7"
mkdir -p "$TMP/r7/tests"
echo "def test_f(): assert True" > "$TMP/r7/tests/test_f.py"
spec "$TMP/r7" "| REQ-1 | tests/test_f.py |" "PROPERTY TESTS: REQUIRED"
echo "code" > "$TMP/r7/mod.py" && (cd "$TMP/r7" && git add -A)
tdd_gate_json "$TMP/r7" | bash "$TDD_GATE" >/dev/null 2>&1
RC=$?
[ "$RC" = "2" ] && pass "tdd-gate blocks REQUIRED property tests without marker" || die "expected exit 2, got $RC"

# 8. tdd-gate: property marker present (@given) -> allow
mkrepo "$TMP/r8"
mkdir -p "$TMP/r8/tests"
printf 'from hypothesis import given\n@given(x=None)\ndef test_f(x): assert True\n' > "$TMP/r8/tests/test_f.py"
spec "$TMP/r8" "| REQ-1 | tests/test_f.py |" "PROPERTY TESTS: REQUIRED"
echo "code" > "$TMP/r8/mod.py" && (cd "$TMP/r8" && git add -A)
tdd_gate_json "$TMP/r8" | bash "$TDD_GATE" >/dev/null 2>&1
RC=$?
[ "$RC" = "0" ] && pass "tdd-gate allows property marker via @given" || die "expected exit 0, got $RC"

# 9. tdd-gate: no spec at all -> unchanged advisory behavior (exit 0)
mkrepo "$TMP/r9"
echo "code" > "$TMP/r9/mod.py" && (cd "$TMP/r9" && git add -A)
tdd_gate_json "$TMP/r9" | bash "$TDD_GATE" >/dev/null 2>&1
RC=$?
[ "$RC" = "0" ] && pass "no spec => advisory behavior unchanged" || die "expected exit 0 without spec, got $RC"

exit $fail
