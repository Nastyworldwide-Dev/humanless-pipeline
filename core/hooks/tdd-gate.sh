#!/bin/bash
# PreToolUse hook: blocks feat:/fix: commits if test files are missing
# Only checks test file EXISTENCE (fast) — not execution
# Exit 0 = allow, Exit 2 = block

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

# --- Extract commit type from command (handles heredoc + simple -m) ---
COMMIT_TYPE=$(echo "$COMMAND" | grep -oP '\b(feat|fix|chore|refactor|docs|test|style|perf|ci|build|revert)\s*[\(:]' | head -1 | sed 's/[:(].*//')

# Only enforce on feat: and fix: commits
case "$COMMIT_TYPE" in
  feat|fix) ;;
  *) exit 0 ;;  # chore, refactor, docs, test, style, etc. — skip
esac

# --- Get CWD and staged files ---
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# Find git root
GIT_ROOT=$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null)
[ -z "$GIT_ROOT" ] && exit 0

# Get staged code files (exclude configs, tests themselves, and non-code)
STAGED_FILES=$(cd "$GIT_ROOT" && git diff --cached --name-only 2>/dev/null || true)
[ -z "$STAGED_FILES" ] && exit 0

MISSING_TESTS=""

while IFS= read -r filepath; do
  [ -z "$filepath" ] && continue
  filename=$(basename "$filepath")
  dirname_path=$(dirname "$filepath")
  basename_no_ext="${filename%.*}"
  ext="${filename##*.}"

  # Skip config/non-code files
  case "$filename" in
    hooks.py|__init__.py|conftest.py|setup.py|setup.cfg) continue ;;
    *.json|*.md|*.yml|*.yaml|*.toml|*.cfg|*.ini|*.txt|*.csv) continue ;;
    *.d.ts) continue ;;
  esac

  # Skip test files themselves
  case "$filename" in
    test_*|*_test.*|*.test.*|*.spec.*|*Test.*) continue ;;
  esac

  # Skip migration/patch files
  echo "$filepath" | grep -qE '(patches|migrations)/' && continue

  # Skip virtual environments and node_modules
  echo "$filepath" | grep -qE '/(env|\.venv|venv|node_modules)/' && continue

  # Skip .claude directory
  echo "$filepath" | grep -qE '/\.claude/' && continue

  # Skip upstream framework apps (Frappe-specific, conditional)
  echo "$filepath" | grep -qE '/apps/(frappe|erpnext|hrms|insights)/' && continue

  # --- Check for corresponding test file ---
  case "$ext" in
    py)
      # Python: look for test_{basename}.py in same dir or tests/ subdir
      test_found=false
      [ -f "$GIT_ROOT/$dirname_path/test_${basename_no_ext}.py" ] && test_found=true
      [ -f "$GIT_ROOT/$dirname_path/tests/test_${basename_no_ext}.py" ] && test_found=true
      # Also check parent tests/ dir
      parent_dir=$(dirname "$dirname_path")
      [ -f "$GIT_ROOT/$parent_dir/tests/test_${basename_no_ext}.py" ] && test_found=true
      # Case-insensitive variant
      [ -f "$GIT_ROOT/$dirname_path/test_$(echo "$basename_no_ext" | tr '[:upper:]' '[:lower:]').py" ] && test_found=true

      if [ "$test_found" = false ]; then
        MISSING_TESTS="${MISSING_TESTS}\n  $filepath -> expected test_${basename_no_ext}.py"
      fi
      ;;

    ts|tsx)
      # TypeScript: look for {basename}.test.ts, {basename}.spec.ts, or __tests__/{basename}.test.ts
      test_found=false
      [ -f "$GIT_ROOT/$dirname_path/${basename_no_ext}.test.ts" ] && test_found=true
      [ -f "$GIT_ROOT/$dirname_path/${basename_no_ext}.test.tsx" ] && test_found=true
      [ -f "$GIT_ROOT/$dirname_path/${basename_no_ext}.spec.ts" ] && test_found=true
      [ -f "$GIT_ROOT/$dirname_path/${basename_no_ext}.spec.tsx" ] && test_found=true
      [ -f "$GIT_ROOT/$dirname_path/__tests__/${basename_no_ext}.test.ts" ] && test_found=true
      [ -f "$GIT_ROOT/$dirname_path/__tests__/${basename_no_ext}.test.tsx" ] && test_found=true

      if [ "$test_found" = false ]; then
        MISSING_TESTS="${MISSING_TESTS}\n  $filepath -> expected ${basename_no_ext}.test.ts(x)"
      fi
      ;;

    kt)
      # Kotlin: look for {basename}Test.kt in test mirror directory
      test_found=false
      test_path=$(echo "$dirname_path" | sed 's|/main/|/test/|')
      [ -f "$GIT_ROOT/$test_path/${basename_no_ext}Test.kt" ] && test_found=true
      # Also check androidTest
      test_path_android=$(echo "$dirname_path" | sed 's|/main/|/androidTest/|')
      [ -f "$GIT_ROOT/$test_path_android/${basename_no_ext}Test.kt" ] && test_found=true

      if [ "$test_found" = false ]; then
        MISSING_TESTS="${MISSING_TESTS}\n  $filepath -> expected ${basename_no_ext}Test.kt"
      fi
      ;;

    js)
      # JS: check for .test.js or .cy.js (Cypress E2E)
      test_found=false
      [ -f "$GIT_ROOT/$dirname_path/${basename_no_ext}.test.js" ] && test_found=true
      [ -f "$GIT_ROOT/$dirname_path/__tests__/${basename_no_ext}.test.js" ] && test_found=true
      # Also accept Cypress E2E specs as valid tests for JS files
      for cy_dir in "$GIT_ROOT"/cypress/e2e/ "$GIT_ROOT"/*/cypress/e2e/; do
        [ -f "${cy_dir}${basename_no_ext}.cy.js" ] 2>/dev/null && test_found=true
      done

      if [ "$test_found" = false ]; then
        MISSING_TESTS="${MISSING_TESTS}\n  $filepath -> expected ${basename_no_ext}.test.js or ${basename_no_ext}.cy.js"
      fi
      ;;
  esac

  # --- Assertion quality check: stub tests = no tests ---
  if [ "$test_found" = true ]; then
    ASSERTION_COUNT=0
    case "$ext" in
      py)
        for tfile in "$GIT_ROOT/$dirname_path/test_${basename_no_ext}.py" \
                      "$GIT_ROOT/$dirname_path/tests/test_${basename_no_ext}.py" \
                      "$GIT_ROOT/$(dirname "$dirname_path")/tests/test_${basename_no_ext}.py"; do
          if [ -f "$tfile" ]; then
            ASSERTION_COUNT=$(grep -cE 'assert|self\.assert|assertEqual|assertRaises|assertIn|assertTrue|assertFalse|pytest\.raises' "$tfile" 2>/dev/null || echo 0)
            break
          fi
        done
        ;;
      ts|tsx)
        for tfile in "$GIT_ROOT/$dirname_path/${basename_no_ext}.test.ts" \
                      "$GIT_ROOT/$dirname_path/${basename_no_ext}.test.tsx" \
                      "$GIT_ROOT/$dirname_path/${basename_no_ext}.spec.ts" \
                      "$GIT_ROOT/$dirname_path/${basename_no_ext}.spec.tsx"; do
          if [ -f "$tfile" ]; then
            ASSERTION_COUNT=$(grep -cE 'expect\(|assert\.|toBe|toEqual|toThrow|toHaveBeenCalled' "$tfile" 2>/dev/null || echo 0)
            break
          fi
        done
        ;;
      js)
        for tfile in "$GIT_ROOT/$dirname_path/${basename_no_ext}.test.js" \
                      "$GIT_ROOT/$dirname_path/__tests__/${basename_no_ext}.test.js"; do
          if [ -f "$tfile" ]; then
            ASSERTION_COUNT=$(grep -cE 'expect\(|assert\.|toBe|toEqual|toThrow|toHaveBeenCalled' "$tfile" 2>/dev/null || echo 0)
            break
          fi
        done
        ;;
      kt)
        tfile="$GIT_ROOT/$(echo "$dirname_path" | sed 's|/main/|/test/|')/${basename_no_ext}Test.kt"
        if [ -f "$tfile" ]; then
          ASSERTION_COUNT=$(grep -cE 'assert|assertEquals|assertThrows|verify\(' "$tfile" 2>/dev/null || echo 0)
        fi
        ;;
    esac
    if [ "$ASSERTION_COUNT" -eq 0 ]; then
      MISSING_TESTS="${MISSING_TESTS}\n  $filepath -> test file exists but has 0 assertions (stub). Write real tests!"
    fi
  fi

done <<< "$STAGED_FILES"

# --- Verdict ---
if [ -n "$MISSING_TESTS" ]; then
  echo "=========================================="
  echo "  COMMIT BLOCKED -- TDD gate: missing tests"
  echo "=========================================="
  echo -e "Commit type '$COMMIT_TYPE:' requires test files for changed code."
  echo -e "\nMissing test files:$MISSING_TESTS"
  echo ""
  echo "Options:"
  echo "  1. Create the missing test files (TDD: write failing test first)"
  echo "  2. Use a different commit type (chore:/refactor:/docs:) if no tests needed"
  echo "  3. User can say 'skip tests' to bypass"
  exit 2
fi

exit 0
