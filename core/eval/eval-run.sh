#!/bin/bash
# eval-run.sh — replay corpus tasks against the CURRENT pipeline revision and
# measure shots-to-green. For each task: start a worktree at the parent sha,
# hand the commit's subject+body to a headless autonomous claude session, then
# restore the ORIGINAL commit's test files (the oracle) and run the repo's
# test command. Repeat with failure feedback until green or MAX_SHOTS.
#
# Usage: eval-run.sh --label <revision-label> [--limit N] [--corpus file] [--max-shots N]
# Results append to results.jsonl: {id, label, shots, passed, seconds, ts}
set -u

CORPUS="$HOME/.claude/pipeline/eval/corpus.jsonl"
RESULTS="$HOME/.claude/pipeline/eval/results.jsonl"
LABEL=""
LIMIT=0
MAX_SHOTS="${EVAL_MAX_SHOTS:-4}"

while [ $# -gt 0 ]; do
  case "$1" in
    --label) LABEL="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --corpus) CORPUS="$2"; shift 2 ;;
    --max-shots) MAX_SHOTS="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[ -z "$LABEL" ] && { echo "usage: eval-run.sh --label <revision-label> [--limit N]" >&2; exit 1; }
[ -f "$CORPUS" ] || { echo "no corpus at $CORPUS — run corpus-build.sh first" >&2; exit 1; }
mkdir -p "$(dirname "$RESULTS")"

log() { echo "[eval-run $(date -u +%FT%TZ)] $*"; }

# Repo test command: explicit map in eval-config.json beats detection.
test_cmd_for() { # $1 repo_root
  local cfg="$HOME/.claude/pipeline/eval/eval-config.json"
  if [ -f "$cfg" ]; then
    local mapped
    mapped=$(jq -r --arg r "$1" '.test_cmds[$r] // empty' "$cfg" 2>/dev/null)
    [ -n "$mapped" ] && { echo "$mapped"; return; }
  fi
  if [ -f "$1/verify.sh" ]; then echo "bash verify.sh"; return; fi
  if [ -f "$1/package.json" ] && command -v bun >/dev/null; then echo "bun test"; return; fi
  if ls "$1"/tests/test-*.sh >/dev/null 2>&1; then echo 'for t in tests/test-*.sh; do bash "$t" || exit 1; done'; return; fi
  echo ""
}

run_count=0
while IFS= read -r entry; do
  [ "$LIMIT" -gt 0 ] && [ "$run_count" -ge "$LIMIT" ] && break
  id=$(echo "$entry" | jq -r .id)
  repo=$(echo "$entry" | jq -r .repo)
  sha=$(echo "$entry" | jq -r .sha)
  parent=$(echo "$entry" | jq -r .parent)
  subject=$(echo "$entry" | jq -r .subject)
  body=$(echo "$entry" | jq -r .body)
  mapfile -t test_files < <(echo "$entry" | jq -r '.test_files[]')

  # Skip tasks already measured at this label
  grep -q "\"id\":\"$id\",\"label\":\"$LABEL\"" "$RESULTS" 2>/dev/null && continue
  [ -d "$repo" ] || { log "skip $id — repo missing"; continue; }

  TCMD=$(test_cmd_for "$repo")
  [ -z "$TCMD" ] && { log "skip $id — no test command for $repo"; continue; }

  WT=$(mktemp -d "/tmp/eval-${id}-XXXX")
  if ! git -C "$repo" worktree add -q --detach "$WT" "$parent" 2>/dev/null; then
    log "skip $id — worktree failed"; rm -rf "$WT"; continue
  fi
  # Replay measures implementation convergence against the test oracle, not
  # gate choreography — disable the plan gate inside the throwaway worktree.
  mkdir -p "$WT/.claude/plans" && touch "$WT/.claude/plans/.plan-gate-off"

  start=$(date +%s)
  shots=0
  passed=false
  feedback=""
  while [ "$shots" -lt "$MAX_SHOTS" ]; do
    shots=$((shots + 1))
    PROMPT="Implement this task in the current repo. Write/keep tests as needed; the change must make the repo's test suite pass.${feedback}

TASK: $subject
$body"
    ( cd "$WT" && PIPELINE_AUTONOMOUS=1 claude -p "$PROMPT" ${PIPELINE_CLAUDE_FLAGS:---permission-mode acceptEdits} ) \
      > "$WT/.eval-shot-$shots.log" 2>&1

    # Restore the oracle: the original commit's test files
    for tf in "${test_files[@]}"; do
      git -C "$WT" checkout -q "$sha" -- "$tf" 2>/dev/null || true
    done
    if ( cd "$WT" && timeout 600 bash -c "$TCMD" ) > "$WT/.eval-test-$shots.log" 2>&1; then
      passed=true
      break
    fi
    feedback=" PREVIOUS ATTEMPT FAILED — test output tail: $(tail -12 "$WT/.eval-test-$shots.log" | tr '"' "'")"
  done
  secs=$(( $(date +%s) - start ))

  jq -cn --arg id "$id" --arg label "$LABEL" --argjson shots "$shots" \
    --argjson passed "$passed" --argjson seconds "$secs" --arg ts "$(date -u +%FT%TZ)" \
    '{id: $id, label: $label, shots: $shots, passed: $passed, seconds: $seconds, ts: $ts}' >> "$RESULTS"
  log "$id [$LABEL]: shots=$shots passed=$passed (${secs}s)"

  git -C "$repo" worktree remove -f "$WT" 2>/dev/null || rm -rf "$WT"
  run_count=$((run_count + 1))
done < "$CORPUS"

log "done — $run_count task(s) measured at label '$LABEL' -> $RESULTS"
