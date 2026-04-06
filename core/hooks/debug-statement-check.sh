#!/usr/bin/env bash
# Debug Statement Detection Hook — PostToolUse (Edit|Write)
# Warns when debug statements (console.log, print, debugger, breakpoint) appear
# in production code. Does NOT block — just warns via systemMessage.
#
# Exit 0 always (advisory only)

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL_NAME" in
    Edit|Write) ;;
    *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE_PATH" ] || exit 0
[ -f "$FILE_PATH" ] || exit 0

# Skip test files, fixtures, config, hooks, and non-source files
case "$FILE_PATH" in
    */test_*|*/tests/*|*_test.py|*.test.js|*.test.ts|*.spec.js|*.spec.ts)
        exit 0 ;;
    */.claude/hooks/*|*/node_modules/*|*/dist/*|*/.git/*)
        exit 0 ;;
    *.json|*.md|*.txt|*.yml|*.yaml|*.toml|*.cfg|*.ini|*.csv|*.html|*.css|*.sh)
        exit 0 ;;
esac

# Get the content that was written/edited
if [ "$TOOL_NAME" = "Write" ]; then
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
elif [ "$TOOL_NAME" = "Edit" ]; then
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
fi

[ -n "$CONTENT" ] || exit 0

WARNINGS=""

# Python debug statements
case "$FILE_PATH" in
    *.py)
        if echo "$CONTENT" | grep -qP '^\s*print\(' 2>/dev/null; then
            WARNINGS="${WARNINGS}\n  - print() found -- use logging.getLogger(__name__).info() or structured logger instead"
        fi
        if echo "$CONTENT" | grep -qP '^\s*breakpoint\(\)' 2>/dev/null; then
            WARNINGS="${WARNINGS}\n  - breakpoint() found (remove before committing)"
        fi
        if echo "$CONTENT" | grep -qP '^\s*import\s+pdb|^\s*pdb\.set_trace' 2>/dev/null; then
            WARNINGS="${WARNINGS}\n  - pdb debugger found (remove before committing)"
        fi
        if echo "$CONTENT" | grep -qP '^\s*import\s+ipdb|^\s*ipdb\.set_trace' 2>/dev/null; then
            WARNINGS="${WARNINGS}\n  - ipdb debugger found (remove before committing)"
        fi
        ;;
esac

# JavaScript/TypeScript debug statements
case "$FILE_PATH" in
    *.js|*.jsx|*.ts|*.tsx)
        # Bare console.log without module prefix
        if echo "$CONTENT" | grep -qP '^\s*console\.log\(' 2>/dev/null; then
            WARNINGS="${WARNINGS}\n  - console.log() found -- use console.info('[ModuleName]', ...) for structured logging"
        fi
        # console.debug and console.trace (dev-only)
        if echo "$CONTENT" | grep -qP '^\s*console\.(debug|trace|dir)\(' 2>/dev/null; then
            WARNINGS="${WARNINGS}\n  - console.debug/trace/dir found -- remove before committing or use log.debug()"
        fi
        if echo "$CONTENT" | grep -qP '^\s*debugger\s*;?' 2>/dev/null; then
            WARNINGS="${WARNINGS}\n  - debugger statement found (remove before committing)"
        fi
        if echo "$CONTENT" | grep -qP '^\s*alert\(' 2>/dev/null; then
            WARNINGS="${WARNINGS}\n  - alert() found (use proper UI feedback instead)"
        fi
        ;;
esac

# Kotlin debug statements
case "$FILE_PATH" in
    *.kt|*.kts)
        if echo "$CONTENT" | grep -qP '^\s*println\(' 2>/dev/null; then
            WARNINGS="${WARNINGS}\n  - println() found (use Timber or proper logging)"
        fi
        ;;
esac

if [ -n "$WARNINGS" ]; then
    echo "{\"systemMessage\": \"Debug statements detected in ${FILE_PATH}:${WARNINGS}\nThese should be removed before committing. Use proper logging instead.\"}"
fi

exit 0
