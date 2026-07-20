#!/bin/bash
# corpus-build.sh — mine a repo's git history for replayable eval tasks.
# A qualifying task is a non-merge feat/fix commit that touched BOTH source
# and test files with a bounded diff — its tests are the oracle (SWE-bench
# style fail-to-pass), its parent sha is the replay starting point.
#
# Usage: corpus-build.sh <repo_dir> [count] [corpus_file]
# Appends JSONL entries (deduped by sha) to the corpus file.
set -u
REPO_DIR="${1:?usage: corpus-build.sh <repo_dir> [count] [corpus_file]}"
COUNT="${2:-30}"
CORPUS="${3:-$HOME/.claude/pipeline/eval/corpus.jsonl}"
mkdir -p "$(dirname "$CORPUS")"
touch "$CORPUS"

cd "$REPO_DIR" || exit 1
GIT_ROOT=$(git rev-parse --show-toplevel) || exit 1
cd "$GIT_ROOT"
REPO_NAME=$(basename "$GIT_ROOT")

added=0
scanned=0
for sha in $(git log --no-merges --format=%H -500); do
  scanned=$((scanned + 1))
  [ "$added" -ge "$COUNT" ] && break
  grep -q "\"sha\":\"$sha\"" "$CORPUS" && continue

  SUBJECT=$(git log -1 --format=%s "$sha")
  echo "$SUBJECT" | grep -qE '^(feat|fix)[:(]' || continue

  FILES=$(git diff-tree --no-commit-id --name-only -r "$sha")
  TEST_FILES=$(echo "$FILES" | grep -E '(^|/)(tests?|__tests__)/|\.(test|spec)\.[a-z]+$|^test_|/test_' || true)
  SRC_FILES=$(echo "$FILES" | grep -vE '(^|/)(tests?|__tests__)/|\.(test|spec)\.[a-z]+$|^test_|/test_' | grep -vE '\.(md|json|lock|txt)$' || true)
  [ -n "$TEST_FILES" ] || continue
  [ -n "$SRC_FILES" ] || continue

  DIFF_LINES=$(git show --numstat --format= "$sha" | awk '{a+=$1+$2} END {print a+0}')
  [ "$DIFF_LINES" -le 800 ] || continue
  PARENT=$(git rev-parse "$sha^" 2>/dev/null) || continue

  BODY=$(git log -1 --format=%b "$sha")
  jq -cn \
    --arg id "${REPO_NAME}-${sha:0:8}" \
    --arg repo "$GIT_ROOT" \
    --arg sha "$sha" \
    --arg parent "$PARENT" \
    --arg subject "$SUBJECT" \
    --arg body "$BODY" \
    --arg tests "$TEST_FILES" \
    --argjson lines "$DIFF_LINES" \
    '{id: $id, repo: $repo, sha: $sha, parent: $parent, subject: $subject, body: $body, test_files: ($tests | split("\n") | map(select(length > 0))), diff_lines: $lines}' \
    >> "$CORPUS"
  added=$((added + 1))
done

TOTAL=$(grep -c "" "$CORPUS" || echo 0)
echo "[corpus-build] $REPO_NAME: scanned $scanned commits, added $added tasks (corpus total: $TOTAL) -> $CORPUS"
