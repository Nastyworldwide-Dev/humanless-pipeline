#!/usr/bin/env bash
# Logging Gate Hook — PreToolUse (Edit|Write)
# Blocks edits that add functions >5 lines without logging statements.
# Enforces mandatory logging for humanless pipeline observability.
#
# Exit 2 = block (missing logging)
# Exit 0 = pass

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL_NAME" in
    Edit|Write) ;;
    *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE_PATH" ] || exit 0
[ -f "$FILE_PATH" ] || exit 0

# --- Exclusions ---

# Skip test files
case "$FILE_PATH" in
    */test_*|*/tests/*|*_test.py|*.test.js|*.test.ts|*.test.tsx|*.spec.js|*.spec.ts|*.spec.tsx|*Test.kt)
        exit 0 ;;
esac

# Skip config, types, styles, generated, non-source
case "$FILE_PATH" in
    *.json|*.yml|*.yaml|*.toml|*.md|*.txt|*.cfg|*.ini|*.csv|*.html|*.css|*.scss|*.sh|*.sql)
        exit 0 ;;
    *.d.ts)
        exit 0 ;;
    */node_modules/*|*/dist/*|*/.git/*|*/__pycache__/*|*/migrations/*)
        exit 0 ;;
    */.claude/hooks/*|*/.claude/skills/*|*/.claude/templates/*)
        exit 0 ;;
esac

# Skip init/re-export files
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
    __init__.py|index.ts|index.js|index.tsx)
        exit 0 ;;
esac

# Skip small files (<10 lines)
TOTAL_LINES=$(wc -l < "$FILE_PATH" 2>/dev/null || echo "0")
[ "$TOTAL_LINES" -ge 10 ] 2>/dev/null || exit 0

# --- Get new content being written ---
if [ "$TOOL_NAME" = "Write" ]; then
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
elif [ "$TOOL_NAME" = "Edit" ]; then
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
fi

[ -n "$CONTENT" ] || exit 0

# --- Detect language and check functions ---
EXT="${FILE_PATH##*.}"
MISSING_FUNCS=""

check_python() {
    local content="$1"
    local in_func=false
    local func_name=""
    local func_lines=0
    local has_logging=false

    while IFS= read -r line; do
        # Detect new function definition
        if echo "$line" | grep -qP '^\s*def\s+\w+\s*\(' 2>/dev/null; then
            # Check previous function if it was being tracked
            if [ "$in_func" = true ] && [ "$func_lines" -gt 5 ] && [ "$has_logging" = false ]; then
                MISSING_FUNCS="${MISSING_FUNCS}\n  - Python function '${func_name}' (${func_lines} lines) has no logging"
            fi
            func_name=$(echo "$line" | grep -oP 'def\s+\K\w+' 2>/dev/null)
            in_func=true
            func_lines=0
            has_logging=false
            continue
        fi

        if [ "$in_func" = true ]; then
            func_lines=$((func_lines + 1))
            # Check for logging calls (generic Python logging patterns)
            if echo "$line" | grep -qP 'logger\.|logging\.|log\.(info|warn|error|debug|warning|critical)|\.log_error|\.throw|\.msgprint' 2>/dev/null; then
                has_logging=true
            fi
            # Detect end of function (next top-level def/class or blank line pattern)
            if echo "$line" | grep -qP '^(def |class |$)' 2>/dev/null && [ "$func_lines" -gt 1 ]; then
                if [ "$func_lines" -gt 5 ] && [ "$has_logging" = false ]; then
                    MISSING_FUNCS="${MISSING_FUNCS}\n  - Python function '${func_name}' (${func_lines} lines) has no logging"
                fi
                # Reset if it's a new function
                if echo "$line" | grep -qP '^def\s+\w+' 2>/dev/null; then
                    func_name=$(echo "$line" | grep -oP 'def\s+\K\w+' 2>/dev/null)
                    func_lines=0
                    has_logging=false
                else
                    in_func=false
                fi
            fi
        fi
    done <<< "$content"

    # Check last function
    if [ "$in_func" = true ] && [ "$func_lines" -gt 5 ] && [ "$has_logging" = false ]; then
        MISSING_FUNCS="${MISSING_FUNCS}\n  - Python function '${func_name}' (${func_lines} lines) has no logging"
    fi
}

check_javascript() {
    local content="$1"
    local in_func=false
    local func_name=""
    local func_lines=0
    local has_logging=false
    local brace_depth=0

    while IFS= read -r line; do
        # Detect function definitions
        if echo "$line" | grep -qP '(function\s+\w+|(?:const|let|var)\s+\w+\s*=\s*(?:async\s+)?(?:function|\())' 2>/dev/null; then
            if [ "$in_func" = true ] && [ "$func_lines" -gt 5 ] && [ "$has_logging" = false ]; then
                MISSING_FUNCS="${MISSING_FUNCS}\n  - JS/TS function '${func_name}' (${func_lines} lines) has no logging"
            fi
            func_name=$(echo "$line" | grep -oP '(function\s+\K\w+|(?:const|let|var)\s+\K\w+)' 2>/dev/null | head -1)
            in_func=true
            func_lines=0
            has_logging=false
            continue
        fi

        if [ "$in_func" = true ]; then
            func_lines=$((func_lines + 1))
            # Check for logging calls (structured logging, NOT bare console.log)
            if echo "$line" | grep -qP 'log\.(info|warn|error|debug)|console\.(error|warn|info)|createLogger|Logger' 2>/dev/null; then
                has_logging=true
            fi
        fi
    done <<< "$content"

    if [ "$in_func" = true ] && [ "$func_lines" -gt 5 ] && [ "$has_logging" = false ]; then
        MISSING_FUNCS="${MISSING_FUNCS}\n  - JS/TS function '${func_name}' (${func_lines} lines) has no logging"
    fi
}

check_kotlin() {
    local content="$1"
    local in_func=false
    local func_name=""
    local func_lines=0
    local has_logging=false

    while IFS= read -r line; do
        if echo "$line" | grep -qP '^\s*(private |public |internal |protected |override )*fun\s+\w+' 2>/dev/null; then
            if [ "$in_func" = true ] && [ "$func_lines" -gt 5 ] && [ "$has_logging" = false ]; then
                MISSING_FUNCS="${MISSING_FUNCS}\n  - Kotlin function '${func_name}' (${func_lines} lines) has no logging"
            fi
            func_name=$(echo "$line" | grep -oP 'fun\s+\K\w+' 2>/dev/null)
            in_func=true
            func_lines=0
            has_logging=false
            continue
        fi

        if [ "$in_func" = true ]; then
            func_lines=$((func_lines + 1))
            if echo "$line" | grep -qP 'Timber\.|Log\.(d|i|w|e|v)\(' 2>/dev/null; then
                has_logging=true
            fi
        fi
    done <<< "$content"

    if [ "$in_func" = true ] && [ "$func_lines" -gt 5 ] && [ "$has_logging" = false ]; then
        MISSING_FUNCS="${MISSING_FUNCS}\n  - Kotlin function '${func_name}' (${func_lines} lines) has no logging"
    fi
}

# --- Run check based on language ---
case "$EXT" in
    py)
        check_python "$CONTENT"
        ;;
    js|jsx|ts|tsx)
        check_javascript "$CONTENT"
        ;;
    kt|kts)
        check_kotlin "$CONTENT"
        ;;
    *)
        exit 0
        ;;
esac

# --- Report ---
if [ -n "$MISSING_FUNCS" ]; then
    cat <<EOF
{"decision": "block", "reason": "Logging gate: Functions >5 lines must include logging for pipeline observability.${MISSING_FUNCS}\n\nAdd one of:\n  Python: logger.info(...) or logging.getLogger(__name__).info(...)\n  JS/TS: console.info('[Module]', ...) or log.info(...)\n  Kotlin: Timber.d(...)"}
EOF
    exit 2
fi

exit 0
