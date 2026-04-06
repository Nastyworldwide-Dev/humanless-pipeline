#!/usr/bin/env bash
# Session Persistence Hook — Stop
# Persists session summary to cost-tracking DB and writes final stats.
# Complements pre-compact-handoff.sh (which fires on /compact).
#
# Exit 0 always

PIPELINE_DIR="$HOME/.claude/pipeline"
DB_FILE="$PIPELINE_DIR/cost-tracking.db"
SESSION_FILE="$PIPELINE_DIR/current-session.json"

[ -f "$SESSION_FILE" ] || exit 0
[ -f "$DB_FILE" ] || exit 0

SESSION_ID=$(jq -r '.session_id // empty' "$SESSION_FILE" 2>/dev/null)
[ -n "$SESSION_ID" ] || exit 0

NOW=$(date -Iseconds)

# Close out the session in DB
sqlite3 "$DB_FILE" "UPDATE sessions SET ended_at = '$NOW' WHERE session_id = '$SESSION_ID';" 2>/dev/null

# Get final stats
STATS=$(sqlite3 "$DB_FILE" "SELECT tool_calls, bash_calls, edit_calls, write_calls, read_calls, agent_calls FROM sessions WHERE session_id = '$SESSION_ID';" 2>/dev/null)

if [ -n "$STATS" ]; then
    IFS='|' read -r TOTAL BASH EDIT WRITE READ AGENT <<< "$STATS"
    STARTED=$(jq -r '.started_at // "unknown"' "$SESSION_FILE" 2>/dev/null)

    # Write session summary to learnings dir for future reference
    mkdir -p "$PIPELINE_DIR/learnings"
    cat >> "$PIPELINE_DIR/learnings/sessions.jsonl" <<JSON
{"session_id":"$SESSION_ID","started":"$STARTED","ended":"$NOW","total_tools":$TOTAL,"bash":$BASH,"edit":$EDIT,"write":$WRITE,"read":$READ,"agent":$AGENT}
JSON
fi

# Clean up current session file
rm -f "$SESSION_FILE"

exit 0
