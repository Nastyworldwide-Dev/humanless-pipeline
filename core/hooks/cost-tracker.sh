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
PROJECT_PATH=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
ERR_LOG="$PIPELINE_DIR/logs/cost-tracker.err"
mkdir -p "$PIPELINE_DIR/logs"

# SQL string literal escaping — tool names and paths come from the hook
# payload and may contain single quotes (e.g. a project dir with an apostrophe)
sql_esc() { local q="'"; printf '%s' "${1//$q/$q$q}"; }

# Ensure canonical schema (same as install.sh Step 8). IF NOT EXISTS makes
# this idempotent — must run even when the DB file already exists, otherwise
# an installer-created DB is never brought up to date and inserts fail.
sqlite3 "$DB_FILE" <<SQL 2>>"$ERR_LOG"
CREATE TABLE IF NOT EXISTS tool_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    session_id TEXT,
    tool_name TEXT NOT NULL,
    model TEXT,
    input_tokens INTEGER DEFAULT 0,
    output_tokens INTEGER DEFAULT 0,
    estimated_cost_usd REAL DEFAULT 0.0,
    project_path TEXT,
    duration_ms INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS session_summary (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT UNIQUE NOT NULL,
    started_at TEXT NOT NULL,
    ended_at TEXT,
    total_input_tokens INTEGER DEFAULT 0,
    total_output_tokens INTEGER DEFAULT 0,
    total_cost_usd REAL DEFAULT 0.0,
    tool_calls INTEGER DEFAULT 0,
    project_path TEXT
);
CREATE INDEX IF NOT EXISTS idx_tool_usage_session ON tool_usage(session_id);
CREATE INDEX IF NOT EXISTS idx_tool_usage_timestamp ON tool_usage(timestamp);
CREATE INDEX IF NOT EXISTS idx_session_summary_started ON session_summary(started_at);
SQL

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
    sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO session_summary (session_id, started_at, project_path) VALUES ('$(sql_esc "$SESSION_ID")', '$(date -Iseconds)', '$(sql_esc "$PROJECT_PATH")');" 2>>"$ERR_LOG"
fi

# Track this tool call
TOOL_COUNT=$((TOOL_COUNT + 1))
NOW=$(date -Iseconds)

# Update session file
STARTED_AT=$(jq -r '.started_at' "$SESSION_FILE" 2>/dev/null)
cat > "$SESSION_FILE" <<JSON
{"session_id": "$SESSION_ID", "started_at": "$STARTED_AT", "tool_count": $TOOL_COUNT, "last_tool": "$TOOL_NAME", "last_at": "$NOW"}
JSON

# Log to SQLite. Synchronous on purpose: two sub-ms statements, and a
# backgrounded block is exactly what hid the schema failure for weeks.
sqlite3 "$DB_FILE" "INSERT INTO tool_usage (session_id, tool_name, timestamp, project_path) VALUES ('$(sql_esc "$SESSION_ID")', '$(sql_esc "$TOOL_NAME")', '$NOW', '$(sql_esc "$PROJECT_PATH")');" 2>>"$ERR_LOG"
sqlite3 "$DB_FILE" "UPDATE session_summary SET tool_calls = tool_calls + 1 WHERE session_id = '$(sql_esc "$SESSION_ID")';" 2>>"$ERR_LOG"

# Suggest compaction at logical breakpoints
# Every 100 tool calls, suggest compaction
if [ $((TOOL_COUNT % 100)) -eq 0 ] && [ "$TOOL_COUNT" -gt 0 ]; then
    echo "{\"systemMessage\": \"Session has reached ${TOOL_COUNT} tool calls. Consider running /compact to free context space if you're at a logical breakpoint (e.g., finished research, completed a feature, done debugging).\"}"
fi

exit 0
