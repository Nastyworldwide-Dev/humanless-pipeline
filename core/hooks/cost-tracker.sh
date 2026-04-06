#!/usr/bin/env bash
# Cost/Token Tracking Hook — PostToolUse (wildcard)
# Tracks tool usage count per session. Logs to SQLite for historical analysis.
# Also emits a systemMessage suggesting compaction at logical breakpoints.
#
# Storage: $HOME/.claude/pipeline/cost-tracking.db
# Exit 0 always (never blocks)

PIPELINE_DIR="$HOME/.claude/pipeline"
DB_FILE="$PIPELINE_DIR/cost-tracking.db"
SESSION_FILE="$PIPELINE_DIR/current-session.json"

mkdir -p "$PIPELINE_DIR"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)

# Initialize DB if needed
if [ ! -f "$DB_FILE" ]; then
    sqlite3 "$DB_FILE" <<SQL
CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT UNIQUE,
    started_at TEXT,
    ended_at TEXT,
    tool_calls INTEGER DEFAULT 0,
    bash_calls INTEGER DEFAULT 0,
    edit_calls INTEGER DEFAULT 0,
    write_calls INTEGER DEFAULT 0,
    read_calls INTEGER DEFAULT 0,
    agent_calls INTEGER DEFAULT 0,
    other_calls INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS tool_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,
    tool_name TEXT,
    timestamp TEXT
);
CREATE INDEX IF NOT EXISTS idx_tool_log_session ON tool_log(session_id);
CREATE INDEX IF NOT EXISTS idx_sessions_started ON sessions(started_at);
SQL
fi

# Get or create session ID
if [ -f "$SESSION_FILE" ]; then
    SESSION_ID=$(jq -r '.session_id // empty' "$SESSION_FILE" 2>/dev/null)
    TOOL_COUNT=$(jq -r '.tool_count // 0' "$SESSION_FILE" 2>/dev/null)
else
    SESSION_ID=""
    TOOL_COUNT=0
fi

if [ -z "$SESSION_ID" ]; then
    SESSION_ID="session_$(date +%Y%m%d_%H%M%S)_$$"
    TOOL_COUNT=0
    cat > "$SESSION_FILE" <<JSON
{"session_id": "$SESSION_ID", "started_at": "$(date -Iseconds)", "tool_count": 0}
JSON
    sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO sessions (session_id, started_at) VALUES ('$SESSION_ID', '$(date -Iseconds)');"
fi

# Track this tool call
TOOL_COUNT=$((TOOL_COUNT + 1))
NOW=$(date -Iseconds)

# Update session file
STARTED_AT=$(jq -r '.started_at' "$SESSION_FILE" 2>/dev/null)
cat > "$SESSION_FILE" <<JSON
{"session_id": "$SESSION_ID", "started_at": "$STARTED_AT", "tool_count": $TOOL_COUNT, "last_tool": "$TOOL_NAME", "last_at": "$NOW"}
JSON

# Log to SQLite (async to avoid blocking)
{
    sqlite3 "$DB_FILE" "INSERT INTO tool_log (session_id, tool_name, timestamp) VALUES ('$SESSION_ID', '$TOOL_NAME', '$NOW');"

    # Update session counters
    COLUMN="other_calls"
    case "$TOOL_NAME" in
        Bash) COLUMN="bash_calls" ;;
        Edit) COLUMN="edit_calls" ;;
        Write) COLUMN="write_calls" ;;
        Read) COLUMN="read_calls" ;;
        Agent) COLUMN="agent_calls" ;;
    esac
    sqlite3 "$DB_FILE" "UPDATE sessions SET tool_calls = tool_calls + 1, ${COLUMN} = ${COLUMN} + 1 WHERE session_id = '$SESSION_ID';"
} &

# Suggest compaction at logical breakpoints
# Every 100 tool calls, suggest compaction
if [ $((TOOL_COUNT % 100)) -eq 0 ] && [ "$TOOL_COUNT" -gt 0 ]; then
    echo "{\"systemMessage\": \"Session has reached ${TOOL_COUNT} tool calls. Consider running /compact to free context space if you're at a logical breakpoint (e.g., finished research, completed a feature, done debugging).\"}"
fi

exit 0
