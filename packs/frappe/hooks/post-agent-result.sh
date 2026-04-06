#!/bin/bash
# SubagentStop hook — pipeline chain enforcement
# Fires when tdd-runner, frappe-reviewer, or cross-app-impact agents complete
# Features: fix-loop circuit breaker, systematic debugging on test failure,
# verification before completion on test pass, pipeline event logging

# Source project detection library
LIB_DIR="$HOME/.claude/hooks/lib"
[ -f "$LIB_DIR/project-detect.sh" ] && source "$LIB_DIR/project-detect.sh"

# Source pipeline event logger
PIPELINE_SCRIPTS="$HOME/.claude/pipeline/scripts"
[ -f "$PIPELINE_SCRIPTS/log-event.sh" ] && source "$PIPELINE_SCRIPTS/log-event.sh"

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
[ "$EVENT" = "SubagentStop" ] || exit 0

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
RESULT=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')

# --- Fix-loop circuit breaker ---
FIX_LOOP_STATE="$HOME/.claude/pipeline/circuit/fix-loop.json"
MAX_FIX_CYCLES=3
DLQ_DIR="$HOME/.claude/pipeline/tasks/failed"

# Get current branch for loop tracking
BENCH="${PD_BENCH_ROOT:-${BENCH_ROOT:-$HOME/frappe-bench}}"
CURRENT_BRANCH=$(git -C "$BENCH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

increment_fix_counter() {
  mkdir -p "$(dirname "$FIX_LOOP_STATE")"
  if [ -f "$FIX_LOOP_STATE" ]; then
    STORED_BRANCH=$(jq -r '.branch // ""' "$FIX_LOOP_STATE" 2>/dev/null)
    CYCLE_COUNT=$(jq -r '.cycle_count // 0' "$FIX_LOOP_STATE" 2>/dev/null)
    if [ "$STORED_BRANCH" = "$CURRENT_BRANCH" ]; then
      CYCLE_COUNT=$((CYCLE_COUNT + 1))
    else
      CYCLE_COUNT=1
    fi
  else
    CYCLE_COUNT=1
  fi
  cat > "$FIX_LOOP_STATE" << FEOF
{
  "branch": "$CURRENT_BRANCH",
  "cycle_count": $CYCLE_COUNT,
  "first_cycle_ts": "$(jq -r '.first_cycle_ts // empty' "$FIX_LOOP_STATE" 2>/dev/null || date -Iseconds)",
  "last_cycle_ts": "$(date -Iseconds)"
}
FEOF
  echo "$CYCLE_COUNT"
}

check_circuit_breaker() {
  local cycle_count
  cycle_count=$(increment_fix_counter)
  if [ "$cycle_count" -ge "$MAX_FIX_CYCLES" ]; then
    mkdir -p "$DLQ_DIR"
    cat > "$DLQ_DIR/circuit-break-$(date +%s).json" << CBEOF
{
  "type": "circuit_break",
  "agent_type": "$AGENT_TYPE",
  "timestamp": "$(date -Iseconds)",
  "branch": "$CURRENT_BRANCH",
  "cycle_count": $cycle_count,
  "reason": "Fix loop exceeded $MAX_FIX_CYCLES cycles"
}
CBEOF
    echo '{"systemMessage": "CIRCUIT BREAK: Fix loop detected — '"$cycle_count"' fix-recommit cycles on branch '"$CURRENT_BRANCH"'. STOP automation. Report to user: the pipeline has looped '"$cycle_count"' times without resolution. Manual investigation needed. Check DLQ for details."}'
    return 1
  fi
  return 0
}

reset_fix_counter() {
  rm -f "$FIX_LOOP_STATE"
}

case "$AGENT_TYPE" in
  frappe-reviewer)
    NEXT_ACTION=$(echo "$RESULT" | grep -oP 'NEXT_ACTION:\s*\K\S+' | tail -1)
    if [ "$NEXT_ACTION" = "FIX_CRITICAL" ]; then
      if check_circuit_breaker; then
        type log_event &>/dev/null && log_event "post-agent-result:frappe-reviewer" "failed" '{"verdict":"FIX_CRITICAL"}'
        echo '{"systemMessage": "MANDATORY HOOK: Code review found CRITICAL issues. Fix them NOW, then re-commit. Do NOT deploy."}'
      fi
    elif [ -z "$NEXT_ACTION" ]; then
      if echo "$RESULT" | grep -qP '^CRITICAL:' && echo "$RESULT" | grep -A5 '^CRITICAL:' | grep -q '^\s*-'; then
        if check_circuit_breaker; then
          type log_event &>/dev/null && log_event "post-agent-result:frappe-reviewer" "failed" '{"verdict":"CRITICAL_FALLBACK"}'
          echo '{"systemMessage": "MANDATORY HOOK: Code review found CRITICAL issues. Fix them NOW, then re-commit. Do NOT deploy."}'
        fi
      else
        reset_fix_counter
        type log_event &>/dev/null && log_event "post-agent-result:frappe-reviewer" "passed" '{"verdict":"DEPLOY"}'
        echo '{"systemMessage": "MANDATORY HOOK: Code review PASSED. Run /deploy skill NOW. Execute immediately — do not ask user."}'
      fi
    else
      reset_fix_counter
      type log_event &>/dev/null && log_event "post-agent-result:frappe-reviewer" "passed" '{"verdict":"DEPLOY"}'
      echo '{"systemMessage": "MANDATORY HOOK: Code review PASSED. Run /deploy skill NOW. Execute immediately — do not ask user."}'
    fi
    ;;
  tdd-runner)
    if echo "$RESULT" | grep -qiE "(FAIL|error|failure)"; then
      if check_circuit_breaker; then
        type log_event &>/dev/null && log_event "post-agent-result:tdd-runner" "failed" '{"verdict":"FAIL"}'
        echo '{"systemMessage": "MANDATORY HOOK: Tests FAILED. Invoke the superpowers:systematic-debugging skill NOW with the test output before attempting any fix. Do NOT guess at fixes — follow the systematic debugging process. Do NOT commit."}'
      fi
    else
      reset_fix_counter
      type log_event &>/dev/null && log_event "post-agent-result:tdd-runner" "passed" '{"verdict":"PASS"}'
      echo '{"systemMessage": "MANDATORY HOOK: All tests PASSED. Before committing, invoke superpowers:verification-before-completion to verify all changes are correct and complete. After verification passes, commit your changes with a descriptive message. Do not ask user for confirmation."}'
    fi
    ;;
  cross-app-impact)
    if echo "$RESULT" | grep -qi "High Impact"; then
      type log_event &>/dev/null && log_event "post-agent-result:cross-app-impact" "failed" '{"verdict":"HIGH_IMPACT"}'
      echo '{"systemMessage": "MANDATORY HOOK: Cross-app impact analysis found HIGH IMPACT changes. STOP and report findings to user."}'
    else
      type log_event &>/dev/null && log_event "post-agent-result:cross-app-impact" "passed" '{}'
    fi
    ;;
esac

# DLQ capture for unhandled agent types
case "$AGENT_TYPE" in
  frappe-reviewer|tdd-runner|cross-app-impact) exit 0 ;;
esac
[ -z "$AGENT_TYPE" ] && exit 0

if echo "$RESULT" | grep -qP '(VERDICT:\s*(FAIL|CRITICAL|BLOCKED)|NEXT_ACTION:\s*FIX_CRITICAL|BLOCKING:\s*yes)'; then
  mkdir -p "$DLQ_DIR"
  TIMESTAMP=$(date +%s)
  cat > "$DLQ_DIR/${AGENT_TYPE}-${TIMESTAMP}.json" << EOF
{
  "type": "agent_failure",
  "agent_type": "$AGENT_TYPE",
  "timestamp": "$(date -Iseconds)",
  "verdict": "$(echo "$RESULT" | grep -oP '(NEXT_ACTION|VERDICT|BLOCKING):\s*\S+' | tail -1)",
  "error_summary": "$(echo "$RESULT" | grep -iE '(CRITICAL|FAIL|error)' | head -3 | tr '\n' ' ' | cut -c1-300)"
}
EOF
fi
