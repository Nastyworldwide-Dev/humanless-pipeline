#!/bin/bash
# PreToolUse hook: TDD gate — blocks Edit/Write on source files without a test file
# Triggers on Edit/Write tools — blocks with exit 2 if no test file exists
# Enforces red-green-refactor: write the failing test first, then edit the source

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0

# Allow creating new files that don't exist yet (Write tool for new file)
# This fixes the chicken-egg problem: you need to create source files for new features
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [ "$TOOL_NAME" = "Write" ] && [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

filename=$(basename "$FILE_PATH")
dirname_path=$(dirname "$FILE_PATH")
basename_no_ext="${filename%.*}"
ext="${filename##*.}"

# Only check source files
case "$ext" in
  py|ts|tsx|kt) ;;
  *) exit 0 ;;
esac

# Skip config/non-code files
case "$filename" in
  hooks.py|__init__.py|conftest.py|setup.py|setup.cfg) exit 0 ;;
  *.d.ts) exit 0 ;;
esac

# Skip test files, test helpers, and E2E seeders
case "$filename" in
  test_*|*_test.*|*.test.*|*.spec.*|*Test.*) exit 0 ;;
  ui_test_*|*_test_helper*|*_test_helpers*|conftest_*) exit 0 ;;
esac

# Skip Cypress spec files
echo "$FILE_PATH" | grep -qE '\.cy\.(js|ts)$' && exit 0

# Skip patches/migrations directories
echo "$FILE_PATH" | grep -qE '(patches|migrations)/' && exit 0

# Skip virtual environments and node_modules
echo "$FILE_PATH" | grep -qE '/(env|\.venv|venv|node_modules)/' && exit 0

# Skip .claude directory (tooling, not project code)
echo "$FILE_PATH" | grep -qE '/\.claude/' && exit 0

# Skip upstream framework code (Frappe-specific, but harmless to keep)
echo "$FILE_PATH" | grep -qE '/apps/(frappe|erpnext|hrms|insights)/' && exit 0

# --- Check for corresponding test file ---
test_found=false
expected=""

case "$ext" in
  py)
    expected="test_${basename_no_ext}.py"
    [ -f "$dirname_path/test_${basename_no_ext}.py" ] && test_found=true
    [ -f "$dirname_path/tests/test_${basename_no_ext}.py" ] && test_found=true
    parent_dir=$(dirname "$dirname_path")
    [ -f "$parent_dir/tests/test_${basename_no_ext}.py" ] && test_found=true
    [ -f "$dirname_path/test_$(echo "$basename_no_ext" | tr '[:upper:]' '[:lower:]').py" ] && test_found=true
    ;;
  ts|tsx)
    expected="${basename_no_ext}.test.ts(x)"
    [ -f "$dirname_path/${basename_no_ext}.test.ts" ] && test_found=true
    [ -f "$dirname_path/${basename_no_ext}.test.tsx" ] && test_found=true
    [ -f "$dirname_path/${basename_no_ext}.spec.ts" ] && test_found=true
    [ -f "$dirname_path/${basename_no_ext}.spec.tsx" ] && test_found=true
    [ -f "$dirname_path/__tests__/${basename_no_ext}.test.ts" ] && test_found=true
    [ -f "$dirname_path/__tests__/${basename_no_ext}.test.tsx" ] && test_found=true
    ;;
  kt)
    expected="${basename_no_ext}Test.kt"
    test_path=$(echo "$dirname_path" | sed 's|/main/|/test/|')
    [ -f "$test_path/${basename_no_ext}Test.kt" ] && test_found=true
    test_path_android=$(echo "$dirname_path" | sed 's|/main/|/androidTest/|')
    [ -f "$test_path_android/${basename_no_ext}Test.kt" ] && test_found=true
    ;;
  js)
    expected="${basename_no_ext}.test.js or ${basename_no_ext}.cy.js"
    [ -f "$dirname_path/${basename_no_ext}.test.js" ] && test_found=true
    [ -f "$dirname_path/__tests__/${basename_no_ext}.test.js" ] && test_found=true
    # Cypress E2E specs count as valid tests for JS files
    for cy_dir in "$(dirname "$dirname_path")"/cypress/e2e/ "$dirname_path"/../../cypress/e2e/; do
      [ -f "${cy_dir}${basename_no_ext}.cy.js" ] 2>/dev/null && test_found=true
    done
    ;;
esac

if [ "$test_found" = false ]; then
  echo "TDD GATE: Edit blocked -- no test file found for ${filename}"
  echo "  Expected: ${expected}"
  echo "  Create the test file first (red-green-refactor), then edit the source."
  cat <<EOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "block", "reason": "TDD: No test file exists for ${filename} (expected ${expected}). Write the failing test first, then edit the source file."}}
EOF
  exit 2
fi

exit 0
