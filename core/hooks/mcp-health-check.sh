#!/usr/bin/env bash
# MCP Health Check Hook — SessionStart
# Validates that critical MCP servers and pipeline dependencies are available.
# Warns via systemMessage if any are unreachable.
#
# Exit 0 always (advisory only)

WARNINGS=""

# Check 1: Context Mode MCP (if installed)
# Dynamic Node.js path detection
NODE_BIN=$(which node 2>/dev/null || echo "")
if [ -n "$NODE_BIN" ]; then
    NODE_PREFIX=$(dirname "$(dirname "$NODE_BIN")")
    CONTEXT_MODE_PATH="${PIPELINE_NODE_MODULES:-$NODE_PREFIX/lib/node_modules}/context-mode"
    if [ -d "$CONTEXT_MODE_PATH" ]; then
        if [ ! -f "$CONTEXT_MODE_PATH/hooks/sessionstart.mjs" ]; then
            WARNINGS="${WARNINGS}\n  - Context Mode: hooks directory missing or incomplete"
        fi
    fi
    # Not installed is OK — it's optional
fi

# Check 2: Node.js available (needed for MCP)
if ! command -v node &>/dev/null; then
    WARNINGS="${WARNINGS}\n  - Node.js: NOT FOUND (required for MCP servers)"
fi

# Check 3: SQLite available (needed for learnings + cost tracking)
if ! command -v sqlite3 &>/dev/null; then
    WARNINGS="${WARNINGS}\n  - sqlite3: NOT FOUND (required for learnings and cost tracking)"
fi

# Check 4: Pipeline directory structure
PIPELINE_DIR="$HOME/.claude/pipeline"
if [ ! -d "$PIPELINE_DIR" ]; then
    WARNINGS="${WARNINGS}\n  - Pipeline directory missing: ${PIPELINE_DIR}"
    mkdir -p "$PIPELINE_DIR/learnings" 2>/dev/null
elif [ ! -d "$PIPELINE_DIR/learnings" ]; then
    WARNINGS="${WARNINGS}\n  - Learnings directory missing: ${PIPELINE_DIR}/learnings"
    mkdir -p "$PIPELINE_DIR/learnings" 2>/dev/null
fi

# Check 5: Critical databases exist
if [ ! -f "$PIPELINE_DIR/learnings.db" ]; then
    WARNINGS="${WARNINGS}\n  - Learnings DB missing (will be auto-created on first learning)"
fi
if [ ! -f "$PIPELINE_DIR/cost-tracking.db" ]; then
    WARNINGS="${WARNINGS}\n  - Cost tracking DB missing (will be auto-created on first tool call)"
fi

# Check 6: ruff available (Python formatter)
if ! command -v ruff &>/dev/null; then
    WARNINGS="${WARNINGS}\n  - ruff: NOT FOUND (Python formatting disabled)"
fi

# Check 7: jq available (needed by all hooks)
if ! command -v jq &>/dev/null; then
    WARNINGS="${WARNINGS}\n  - jq: NOT FOUND (CRITICAL -- all hooks depend on jq)"
fi

# Check 8: Hook scripts are executable
HOOKS_DIR="${PIPELINE_HOOKS_DIR:-$HOME/.claude/hooks}"
NON_EXEC=""
for hook in "$HOOKS_DIR"/*.sh; do
    [ -f "$hook" ] || continue
    if [ ! -x "$hook" ]; then
        NON_EXEC="${NON_EXEC} $(basename "$hook")"
    fi
done
if [ -n "$NON_EXEC" ]; then
    WARNINGS="${WARNINGS}\n  - Non-executable hooks:${NON_EXEC}"
    # Auto-fix
    chmod +x "$HOOKS_DIR"/*.sh 2>/dev/null
    WARNINGS="${WARNINGS} (auto-fixed)"
fi

# Report
if [ -n "$WARNINGS" ]; then
    echo "{\"systemMessage\": \"MCP/Pipeline Health Check:${WARNINGS}\nSome components may not function correctly. Address critical issues before proceeding.\"}"
else
    # Silent on success — don't clutter session start
    :
fi

exit 0
