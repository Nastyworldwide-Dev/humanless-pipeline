#!/bin/bash
# run-eval.sh — replay one corpus task against a repo worktree and score it.
# SWE-bench pattern: worktree at the task's base commit, headless agent gets
# the reconstructed prompt, then the REFERENCE commit's test files are grafted
# in and executed as the oracle. Green = future tests pass on the agent's fix.
#
# Usage: run-eval.sh <corpus.json> [--keep]
# Appends a JSONL row to ~/.claude/pipeline/evals/results.jsonl:
#   {task, stack, green, env_error, commits, num_turns, cost_usd, duration_s, ts, run_dir}
set -u

CORPUS="${1:?usage: run-eval.sh <corpus.json> [--keep]}"
KEEP="${2:-}"
EVALS_DIR="$HOME/.claude/pipeline/evals"
mkdir -p "$EVALS_DIR/runs"

jqf() { jq -r "$1" "$CORPUS"; }
ID=$(jqf '.id'); REPO=$(jqf '.repo'); STACK=$(jqf '.stack')
BASE=$(jqf '.base'); REF=$(jqf '.ref')
TIMEOUT_MIN=$(jqf '.timeout_min // 25'); MAX_TURNS=$(jqf '.max_turns // 60')
SETUP_CMD=$(jqf '.setup_cmd // empty'); CHECK_CMD=$(jqf '.check_cmd')
PROMPT=$(jqf '.prompt')

TS=$(date -u +%Y%m%dT%H%M%SZ)
WT="$EVALS_DIR/runs/${ID}-${TS}"
log() { echo "[eval:$ID] $*"; }

log "worktree at ${BASE:0:10} from $REPO"
git -C "$REPO" worktree add --detach "$WT" "$BASE" >/dev/null 2>&1 || { log "FATAL worktree add failed"; exit 1; }

cleanup() {
  if [ "$KEEP" != "--keep" ]; then
    git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1
  else
    log "kept: $WT"
  fi
}
trap cleanup EXIT

# Approval ceremony is off in eval worktrees (no human present to approve a
# plan); every other hook fires normally — the eval measures implementation
# + review loop, not the approval ritual.
mkdir -p "$WT/.claude/plans" && touch "$WT/.claude/plans/.plan-gate-off"

ENV_ERROR=""
if [ -n "$SETUP_CMD" ]; then
  if ! (cd "$WT" && bash -c "$SETUP_CMD") > "$WT/.eval-setup.log" 2>&1; then
    ENV_ERROR="setup_cmd failed: $(tail -2 "$WT/.eval-setup.log" | tr '\n' ' ')"
    log "ENV ERROR — $ENV_ERROR"
  fi
fi

COST="null"; TURNS="null"; DURATION=0
if [ -z "$ENV_ERROR" ]; then
  log "running headless agent (max ${TIMEOUT_MIN}m, ${MAX_TURNS} turns)"
  T0=$(date +%s)
  AGENT_OUT=$(cd "$WT" && EVAL_MODE=1 timeout "$((TIMEOUT_MIN * 60))" \
    claude -p "$PROMPT" --output-format json --max-turns "$MAX_TURNS" \
    --dangerously-skip-permissions 2>"$WT/.eval-agent.err")
  AGENT_RC=$?
  DURATION=$(( $(date +%s) - T0 ))
  echo "$AGENT_OUT" > "$WT/.eval-agent.json"
  COST=$(echo "$AGENT_OUT" | jq -r '.total_cost_usd // "null"' 2>/dev/null || echo null)
  TURNS=$(echo "$AGENT_OUT" | jq -r '.num_turns // "null"' 2>/dev/null || echo null)
  [ $AGENT_RC -ne 0 ] && log "agent exit $AGENT_RC (timeout=124)"
fi

# Graft the reference oracle tests over whatever the agent wrote, then check.
GREEN=false
if [ -z "$ENV_ERROR" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    mkdir -p "$WT/$(dirname "$f")"
    git -C "$REPO" show "$REF:$f" > "$WT/$f" 2>/dev/null || {
      ENV_ERROR="oracle file missing in ref: $f"; break; }
  done < <(jq -r '.oracle_files[]?' "$CORPUS")
fi
if [ -z "$ENV_ERROR" ]; then
  if (cd "$WT" && timeout 900 bash -c "$CHECK_CMD") > "$WT/.eval-check.log" 2>&1; then
    GREEN=true
  fi
  log "oracle: $([ "$GREEN" = true ] && echo GREEN || echo "RED — $(tail -2 "$WT/.eval-check.log" | tr '\n' ' ' | head -c 160)")"
fi

COMMITS=$(git -C "$WT" rev-list --count HEAD "^$BASE" 2>/dev/null || echo 0)

jq -cn \
  --arg task "$ID" --arg stack "$STACK" --arg ts "$TS" --arg run_dir "$WT" \
  --arg env_error "$ENV_ERROR" \
  --argjson green "$GREEN" --argjson commits "${COMMITS:-0}" \
  --argjson duration "$DURATION" \
  --argjson cost "$( [ "$COST" = "null" ] && echo null || echo "$COST" )" \
  --argjson turns "$( [ "$TURNS" = "null" ] && echo null || echo "$TURNS" )" \
  '{task:$task, stack:$stack, green:$green, env_error:(if $env_error=="" then null else $env_error end),
    commits:$commits, num_turns:$turns, cost_usd:$cost, duration_s:$duration, ts:$ts, run_dir:$run_dir}' \
  | tee -a "$EVALS_DIR/results.jsonl"

[ "$GREEN" = true ]
