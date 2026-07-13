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

# SQL string literal escaping — session id is read from a JSON file on disk
q="'"; SESSION_ID_SQL="${SESSION_ID//$q/$q$q}"

NOW=$(date -Iseconds)

# Close out the session in DB
sqlite3 "$DB_FILE" "UPDATE session_summary SET ended_at = '$NOW' WHERE session_id = '$SESSION_ID_SQL';" 2>/dev/null

# Get final stats — totals live in session_summary, per-tool breakdown in tool_usage
STATS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*),
    COALESCE(SUM(tool_name = 'Bash'), 0),
    COALESCE(SUM(tool_name = 'Edit'), 0),
    COALESCE(SUM(tool_name = 'Write'), 0),
    COALESCE(SUM(tool_name = 'Read'), 0),
    COALESCE(SUM(tool_name IN ('Agent', 'Task')), 0)
    FROM tool_usage WHERE session_id = '$SESSION_ID_SQL';" 2>/dev/null)

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
