#!/bin/bash
# SubagentStop hook — captures LEARNING: lines from agent output
# Appends structured JSON to learnings.jsonl (global + per-rig)
# Fast-exits if no learnings detected

PIPELINE_DIR="$HOME/.claude/pipeline"
LEARNINGS_DIR="$PIPELINE_DIR/learnings"

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
[ "$EVENT" = "SubagentStop" ] || exit 0

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
RESULT=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)

# Fast-exit if no LEARNING: lines in output
echo "$RESULT" | grep -q "^LEARNING:" || exit 0

# Detect rig from agent type or project context
RIG="global"
case "$AGENT_TYPE" in
  *)
    # Try to detect project context from git
    GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    if [ -n "$GIT_ROOT" ]; then
      RIG=$(basename "$GIT_ROOT")
    fi
    ;;
esac

# Determine category from agent type
CATEGORY="general"
case "$AGENT_TYPE" in
  *reviewer*) CATEGORY="review_pattern" ;;
  tdd-runner) CATEGORY="test_failure_pattern" ;;
  deploy*) CATEGORY="deploy_pattern" ;;
  arch-reviewer) CATEGORY="architecture" ;;
  security-reviewer|security-checker) CATEGORY="security" ;;
esac

TIMESTAMP=$(date -Iseconds)
mkdir -p "$LEARNINGS_DIR"

# Extract and write each LEARNING: line
echo "$RESULT" | grep "^LEARNING:" | while IFS= read -r line; do
  LEARNING_TEXT="${line#LEARNING: }"
  # Escape for JSON
  LEARNING_TEXT=$(echo "$LEARNING_TEXT" | sed 's/\\/\\\\/g; s/"/\\"/g')

  ENTRY="{\"ts\":\"$TIMESTAMP\",\"source\":\"$AGENT_TYPE\",\"rig\":\"$RIG\",\"category\":\"$CATEGORY\",\"learning\":\"$LEARNING_TEXT\"}"

  # Append to global learnings
  echo "$ENTRY" >> "$LEARNINGS_DIR/learnings.jsonl"

  # Append to rig-specific learnings
  if [ "$RIG" != "global" ] && [ -d "$LEARNINGS_DIR" ]; then
    echo "$ENTRY" >> "$LEARNINGS_DIR/${RIG}.jsonl"
  fi

  # Write to SQLite (primary storage)
  DB_FILE="$PIPELINE_DIR/learnings.db"
  if [ ! -f "$DB_FILE" ]; then
    # Auto-create learnings DB
    sqlite3 "$DB_FILE" "CREATE TABLE IF NOT EXISTS learnings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp TEXT,
      source TEXT,
      rig TEXT,
      category TEXT,
      learning TEXT,
      confidence REAL DEFAULT 0.5
    );" 2>/dev/null || true
  fi
  if [ -f "$DB_FILE" ]; then
    sqlite3 "$DB_FILE" "INSERT INTO learnings (timestamp, source, rig, category, learning, confidence) VALUES ('$TIMESTAMP', '$AGENT_TYPE', '$RIG', '$CATEGORY', '$LEARNING_TEXT', 0.5);" 2>/dev/null || true
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
