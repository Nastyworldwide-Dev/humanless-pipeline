#!/usr/bin/env bash
# Post-Edit Auto-Formatting Hook — PostToolUse (Edit|Write)
# Runs the appropriate formatter immediately after file edits.
# Python: ruff format | JS/TS: npx biome format --write
#
# Exit 0 always (never blocks, formatting is best-effort)

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL_NAME" in
    Edit|Write) ;;
    *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE_PATH" ] || exit 0
[ -f "$FILE_PATH" ] || exit 0

# Skip non-source files
case "$FILE_PATH" in
    *.json|*.md|*.txt|*.yml|*.yaml|*.toml|*.cfg|*.ini|*.csv|*.html|*.css)
        exit 0
        ;;
    # Skip generated/vendor/node_modules
    */node_modules/*|*/dist/*|*/build/*|*/.git/*|*/vendor/*)
        exit 0
        ;;
    # Skip hook scripts themselves (they're bash, not Python/JS)
    */.claude/hooks/*)
        exit 0
        ;;
    # Skip test fixtures and snapshots
    */__snapshots__/*|*/fixtures/*)
        exit 0
        ;;
esac

# Determine formatter by file extension
case "$FILE_PATH" in
    *.py)
        # Python — use ruff format
        if command -v ruff &>/dev/null; then
            ruff format --quiet "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
    *.js|*.jsx|*.ts|*.tsx)
        # JS/TS — try biome first (faster), fall back to nothing
        # Find the nearest biome.json or biome.jsonc to determine if project uses biome
        DIR=$(dirname "$FILE_PATH")
        BIOME_CONFIG=""
        while [ "$DIR" != "/" ]; do
            if [ -f "$DIR/biome.json" ] || [ -f "$DIR/biome.jsonc" ]; then
                BIOME_CONFIG="$DIR"
                break
            fi
            DIR=$(dirname "$DIR")
        done

        if [ -n "$BIOME_CONFIG" ]; then
            # Project uses biome — format with it
            (cd "$BIOME_CONFIG" && npx biome format --write "$FILE_PATH" 2>/dev/null) || true
        fi
        ;;
    *.kt|*.kts)
        # Kotlin — use ktfmt if available
        if command -v ktfmt &>/dev/null; then
            ktfmt --kotlinlang-style "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
esac

exit 0
