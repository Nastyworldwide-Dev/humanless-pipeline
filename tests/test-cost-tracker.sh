#!/usr/bin/env bash
# Functional regression test for cost-tracker.sh + session-persist.sh.
#
# Regression guarded: the hook used to write to its own tables (tool_log/
# sessions) and only created them when the DB file was missing. The installer
# pre-creates the DB with the canonical schema (tool_usage/session_summary),
# so every insert failed silently inside a backgrounded block — 0 rows ever.
#
# This test pre-initializes the DB exactly like install.sh, fires the hooks
# like Claude Code would, and asserts rows actually land.

set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRACKER="$REPO_DIR/core/hooks/cost-tracker.sh"
PERSIST="$REPO_DIR/core/hooks/session-persist.sh"

TMP_HOME=$(mktemp -d)
trap 'rm -rf "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.claude/pipeline"
DB="$TMP_HOME/.claude/pipeline/cost-tracking.db"

# Canonical schema, verbatim from install.sh Step 8
sqlite3 "$DB" <<'SQL'
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

fail() { echo "FAIL: $1"; exit 1; }

# Fire the tracker like PostToolUse would, three tools
for tool in Bash Edit Read; do
    printf '{"tool_name":"%s","hook_event_name":"PostToolUse","cwd":"/tmp/proj"}' "$tool" \
        | HOME="$TMP_HOME" bash "$TRACKER" >/dev/null 2>&1
done

ROWS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM tool_usage;")
[ "$ROWS" = "3" ] || fail "expected 3 tool_usage rows, got $ROWS"

CALLS=$(sqlite3 "$DB" "SELECT tool_calls FROM session_summary;")
[ "$CALLS" = "3" ] || fail "expected session_summary.tool_calls=3, got '$CALLS'"

# Stop hook closes the session and writes the jsonl summary
HOME="$TMP_HOME" bash "$PERSIST" >/dev/null 2>&1

ENDED=$(sqlite3 "$DB" "SELECT COUNT(*) FROM session_summary WHERE ended_at IS NOT NULL;")
[ "$ENDED" = "1" ] || fail "session_summary.ended_at not set"

SUMMARY="$TMP_HOME/.claude/pipeline/learnings/sessions.jsonl"
[ -f "$SUMMARY" ] || fail "sessions.jsonl not written"
jq -e '.total_tools == 3 and .bash == 1 and .edit == 1 and .read == 1' "$SUMMARY" >/dev/null \
    || fail "sessions.jsonl content wrong: $(cat "$SUMMARY")"

# Self-heal: tracker must also work when the DB file does not exist yet,
# creating the CANONICAL schema (not a divergent one)
rm -f "$DB" "$TMP_HOME/.claude/pipeline/current-session.json"
printf '{"tool_name":"Write","hook_event_name":"PostToolUse"}' \
    | HOME="$TMP_HOME" bash "$TRACKER" >/dev/null 2>&1
ROWS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM tool_usage;" 2>/dev/null)
[ "$ROWS" = "1" ] || fail "self-heal path: expected 1 tool_usage row, got '$ROWS'"

echo "PASS: cost-tracker records to canonical schema (7 assertions)"
