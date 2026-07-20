#!/usr/bin/env bash
# Functional test for core/eval: corpus mining picks exactly the qualifying
# commits, and the report aggregates results + telemetry correctly.
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$REPO_DIR/core/eval/corpus-build.sh"
REPORT="$REPO_DIR/core/eval/eval-report.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { echo "  PASS: $1"; }
die()  { echo "  FAIL: $1"; fail=1; }

# --- Synthetic repo: 1 qualifying commit, 2 non-qualifying ---
mkdir -p "$TMP/repo" && cd "$TMP/repo"
git init -q . && git config user.email t@t && git config user.name t
echo base > base.txt && git add -A && git commit -qm "chore: init"

# Non-qualifying: feat without tests
echo "code" > app.py && git add -A && git commit -qm "feat: add app without tests"

# Qualifying: fix touching source + test
mkdir -p tests
echo "fixed code" > app.py
echo "assert True" > tests/test_app.py
git add -A && git commit -qm "fix: handle empty input"

# Non-qualifying: docs
echo "docs" > README.md && git add -A && git commit -qm "docs: readme"

CORPUS="$TMP/corpus.jsonl"
bash "$BUILD" "$TMP/repo" 30 "$CORPUS" >/dev/null 2>&1

N=$(grep -c "" "$CORPUS" 2>/dev/null || echo 0)
[ "$N" = "1" ] && pass "corpus has exactly the 1 qualifying commit" || die "expected 1 corpus entry, got $N"

SUBJ=$(jq -r .subject "$CORPUS" 2>/dev/null | head -1)
[ "$SUBJ" = "fix: handle empty input" ] && pass "qualifying commit is the fix with tests" || die "wrong commit mined: $SUBJ"

TESTF=$(jq -r '.test_files[0]' "$CORPUS" 2>/dev/null | head -1)
[ "$TESTF" = "tests/test_app.py" ] && pass "test files (oracle) recorded" || die "test files missing: $TESTF"

# Re-run: dedupe by sha, no duplicates
bash "$BUILD" "$TMP/repo" 30 "$CORPUS" >/dev/null 2>&1
N2=$(grep -c "" "$CORPUS")
[ "$N2" = "1" ] && pass "re-run dedupes by sha" || die "dedupe failed: $N2 entries"

# --- Report aggregation on synthetic results + telemetry ---
RES="$TMP/results.jsonl"
cat > "$RES" <<'EOF'
{"id": "a", "label": "baseline", "shots": 4, "passed": true, "seconds": 10, "ts": "t"}
{"id": "b", "label": "baseline", "shots": 3, "passed": false, "seconds": 10, "ts": "t"}
{"id": "a", "label": "upgraded", "shots": 1, "passed": true, "seconds": 10, "ts": "t"}
{"id": "b", "label": "upgraded", "shots": 2, "passed": true, "seconds": 10, "ts": "t"}
EOF
TEL="$TMP/tasks.csv"
cat > "$TEL" <<'EOF'
task-1,erp,shots=2,cause=spec-gap+impl,caught=review-exec,2026-07-20
task-2,erp,shots=3,cause=spec-gap,caught=review-exec,2026-07-20
EOF
bash "$REPORT" "$RES" "$TEL" "$TMP/out" >/dev/null 2>&1

[ -f "$TMP/out/report.md" ] && [ -f "$TMP/out/report.json" ] && pass "report files emitted" || die "report files missing"

MED=$(jq -r '.revisions[] | select(.label == "upgraded") | .median_shots' "$TMP/out/report.json" 2>/dev/null)
[ "$MED" = "2" ] && pass "median shots computed per label" || die "median wrong: $MED"

SPEC=$(jq -r '.rerun_causes[] | select(.cause == "spec-gap") | .count' "$TMP/out/report.json" 2>/dev/null)
[ "$SPEC" = "2" ] && pass "rerun-cause histogram counts spec-gap=2" || die "cause histogram wrong: $SPEC"

exit $fail
