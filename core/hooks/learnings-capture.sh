#!/bin/bash
# SubagentStop hook — captures LEARNING: lines from agent output
# Appends structured JSON to learnings.jsonl (global + per-rig) and rows
# to learnings.db (schema matches install.sh). Fast-exits if no learnings.

PIPELINE_DIR="$HOME/.claude/pipeline"
LEARNINGS_DIR="$PIPELINE_DIR/learnings"
ERR_LOG="$PIPELINE_DIR/logs/learnings-capture.err"

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
[ "$EVENT" = "SubagentStop" ] || exit 0

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD_INPUT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
RESULT=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)

# Fast-exit if no LEARNING: lines in output
echo "$RESULT" | grep -q "^LEARNING:" || exit 0

# Detect rig (project) from git root, falling back to the session cwd
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
PROJECT_PATH="${GIT_ROOT:-$CWD_INPUT}"
RIG="global"
[ -n "$GIT_ROOT" ] && RIG=$(basename "$GIT_ROOT")

# Determine category from agent type
CATEGORY="general"
case "$AGENT_TYPE" in
  arch-reviewer) CATEGORY="architecture" ;;
  security-reviewer|security-checker) CATEGORY="security" ;;
  *reviewer*) CATEGORY="review_pattern" ;;
  tdd-runner) CATEGORY="test_failure_pattern" ;;
  deploy*) CATEGORY="deploy_pattern" ;;
esac

TIMESTAMP=$(date -Iseconds)
mkdir -p "$LEARNINGS_DIR" "$(dirname "$ERR_LOG")"

DB_FILE="$PIPELINE_DIR/learnings.db"
if [ ! -f "$DB_FILE" ]; then
  # Auto-create with the same schema install.sh provisions
  sqlite3 "$DB_FILE" "CREATE TABLE IF NOT EXISTS learnings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    session_id TEXT,
    category TEXT NOT NULL,
    subcategory TEXT,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    source TEXT,
    project_path TEXT,
    file_path TEXT,
    confidence REAL DEFAULT 0.8,
    times_applied INTEGER DEFAULT 0,
    last_applied TEXT
  );" 2>>"$ERR_LOG" || true
fi

# Extract and write each LEARNING: line
echo "$RESULT" | grep "^LEARNING:" | while IFS= read -r line; do
  RAW_TEXT="${line#LEARNING: }"

  # JSON-escaped variant for the .jsonl files
  JSON_TEXT=$(echo "$RAW_TEXT" | sed 's/\\/\\\\/g; s/"/\\"/g')
  ENTRY="{\"ts\":\"$TIMESTAMP\",\"source\":\"$AGENT_TYPE\",\"rig\":\"$RIG\",\"category\":\"$CATEGORY\",\"learning\":\"$JSON_TEXT\"}"

  # Append to global learnings
  echo "$ENTRY" >> "$LEARNINGS_DIR/learnings.jsonl"

  # Append to rig-specific learnings
  if [ "$RIG" != "global" ]; then
    echo "$ENTRY" >> "$LEARNINGS_DIR/${RIG}.jsonl"
  fi

  # SQL-escaped variants (truncate title BEFORE escaping so a doubled
  # quote is never cut in half)
  RAW_TITLE="${RAW_TEXT:0:120}"
  SQL_TITLE="${RAW_TITLE//\'/\'\'}"
  SQL_TEXT="${RAW_TEXT//\'/\'\'}"

  if [ -f "$DB_FILE" ]; then
    sqlite3 "$DB_FILE" "INSERT INTO learnings (timestamp, session_id, category, title, description, source, project_path, confidence)
      VALUES ('$TIMESTAMP', '$SESSION_ID', '$CATEGORY', '$SQL_TITLE', '$SQL_TEXT', '$AGENT_TYPE', '${PROJECT_PATH//\'/\'\'}', 0.5);" \
      2>>"$ERR_LOG" || true
  fi
done

# Rotation: keep last 500 entries per file
for f in "$LEARNINGS_DIR"/*.jsonl; do
  [ -f "$f" ] || continue
  LINE_COUNT=$(wc -l < "$f" 2>/dev/null || echo 0)
  if [ "$LINE_COUNT" -gt 500 ]; then
    tail -250 "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
  fi
done

exit 0
