#!/bin/bash
# PostToolUse:Write — auto-creates test stub when a NEW source file is written
# Mirrors tdd-gate.sh file detection logic so stubs satisfy the gate
# Exit 0 always (advisory hook, never blocks)

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Only act on actual files that exist
[ -f "$FILE_PATH" ] || exit 0

FILENAME=$(basename "$FILE_PATH")
EXT="${FILENAME##*.}"
BASENAME="${FILENAME%.*}"
DIRNAME=$(dirname "$FILE_PATH")

# --- Skip non-code files ---
case "$FILENAME" in
  hooks.py|__init__.py|conftest.py|setup.py|setup.cfg) exit 0 ;;
  *.json|*.md|*.yml|*.yaml|*.toml|*.cfg|*.ini|*.txt|*.csv) exit 0 ;;
  *.d.ts) exit 0 ;;
esac

# Only act on code files
case "$EXT" in
  py|ts|tsx|js|kt) ;;
  *) exit 0 ;;
esac

# --- Skip test files themselves ---
case "$FILENAME" in
  test_*|*_test.*|*.test.*|*.spec.*|*Test.*) exit 0 ;;
esac

# --- Skip paths that don't need tests ---
echo "$FILE_PATH" | grep -qE '(patches|migrations)/' && exit 0
echo "$FILE_PATH" | grep -qE '/(env|\.venv|venv|node_modules)/' && exit 0
echo "$FILE_PATH" | grep -qE '/\.claude/' && exit 0
echo "$FILE_PATH" | grep -qE '/apps/(frappe|erpnext|hrms|insights)/' && exit 0

# --- Determine test file path ---
TEST_PATH=""
case "$EXT" in
  py)
    TEST_PATH="$DIRNAME/test_${BASENAME}.py"
    ;;
  ts)
    TEST_PATH="$DIRNAME/${BASENAME}.test.ts"
    ;;
  tsx)
    TEST_PATH="$DIRNAME/${BASENAME}.test.tsx"
    ;;
  js)
    TEST_PATH="$DIRNAME/${BASENAME}.test.js"
    ;;
  kt)
    TEST_DIR=$(echo "$DIRNAME" | sed 's|/main/|/test/|')
    TEST_PATH="$TEST_DIR/${BASENAME}Test.kt"
    ;;
esac

[ -z "$TEST_PATH" ] && exit 0

# --- Only create if test does NOT already exist ---
[ -f "$TEST_PATH" ] && exit 0

# Also check alternative locations
case "$EXT" in
  py)
    [ -f "$DIRNAME/tests/test_${BASENAME}.py" ] && exit 0
    PARENT=$(dirname "$DIRNAME")
    [ -f "$PARENT/tests/test_${BASENAME}.py" ] && exit 0
    ;;
  ts|tsx)
    [ -f "$DIRNAME/${BASENAME}.spec.ts" ] && exit 0
    [ -f "$DIRNAME/${BASENAME}.spec.tsx" ] && exit 0
    [ -f "$DIRNAME/__tests__/${BASENAME}.test.ts" ] && exit 0
    [ -f "$DIRNAME/__tests__/${BASENAME}.test.tsx" ] && exit 0
    ;;
  js)
    [ -f "$DIRNAME/__tests__/${BASENAME}.test.js" ] && exit 0
    ;;
  kt)
    TEST_DIR_ANDROID=$(echo "$DIRNAME" | sed 's|/main/|/androidTest/|')
    [ -f "$TEST_DIR_ANDROID/${BASENAME}Test.kt" ] && exit 0
    ;;
esac

# --- Create parent directory if needed ---
mkdir -p "$(dirname "$TEST_PATH")"

# --- Write stub with deliberately failing assertion ---
case "$EXT" in
  py)
    CLASS_NAME=$(echo "$BASENAME" | sed 's/_\([a-z]\)/\U\1/g; s/^\([a-z]\)/\U\1/')
    cat > "$TEST_PATH" << PYEOF
import frappe
from frappe.tests.utils import FrappeTestCase


class Test${CLASS_NAME}(FrappeTestCase):
    """Tests for ${BASENAME} — auto-generated stub. Replace with real tests."""

    def test_placeholder(self):
        """TODO: Replace with a real test that fails first (red phase)."""
        self.assertTrue(False, "Stub test — write a real failing test before implementing")
PYEOF
    ;;

  ts|tsx)
    cat > "$TEST_PATH" << TSEOF
import { describe, it, expect } from 'vitest'

describe('${BASENAME}', () => {
  it('should be implemented (stub — replace with real test)', () => {
    // TODO: Replace with a real failing test first (red-green-refactor)
    expect(true).toBe(false)
  })
})
TSEOF
    ;;

  js)
    cat > "$TEST_PATH" << JSEOF
// Auto-generated test stub for ${FILENAME}
// TODO: Replace with real QUnit or Cypress tests

QUnit.module('${BASENAME}', function () {
  QUnit.test('placeholder — replace with real test', function (assert) {
    assert.ok(false, 'Stub test — write a real failing test before implementing')
  })
})
JSEOF
    ;;

  kt)
    cat > "$TEST_PATH" << KTEOF
import org.junit.Test
import org.junit.Assert.*

class ${BASENAME}Test {

    @Test
    fun placeholder_replaceWithRealTest() {
        // TODO: Replace with a real failing test (red-green-refactor)
        fail("Stub test — write a real failing test before implementing")
    }
}
KTEOF
    ;;
esac

echo "{\"systemMessage\": \"Auto-stub created: ${TEST_PATH}. This stub has a deliberately FAILING test. Write the REAL failing test now (red phase), then implement the feature (green phase). Do NOT commit with the stub assertion still in place.\"}"
exit 0
