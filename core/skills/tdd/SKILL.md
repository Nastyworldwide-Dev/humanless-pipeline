---
name: tdd
description: Red-green-refactor TDD workflow — write failing test first, then implement, then refactor
---

# TDD — Test-Driven Development Workflow

Follow the red-green-refactor cycle for every code change.

## Process

### Step 1: Understand the Requirement
- Read the requirement or bug description carefully
- Identify the behavior to test (inputs, expected outputs, edge cases)
- Determine which test framework to use based on project type

### Step 2: Write the Failing Test (RED)
- Create the test file in the correct location:
  - **Python**: `test_{module}.py` in same dir or `tests/` subdir
  - **TypeScript**: `{module}.test.ts` next to source or in `__tests__/`
  - **Kotlin**: `{Module}Test.kt` in `src/test/` mirror path
  - **JavaScript**: `{module}.test.js` next to source or in `__tests__/`
- Write a test that describes the expected behavior
- The test MUST fail — run it to confirm RED status
- If the test passes immediately, your test isn't testing the right thing

### Step 3: Run the Test to Confirm RED
- **Python**: `python -m pytest {test_file} -x -v`
- **TypeScript/JS**: `npx vitest run {test_file}` or `npx jest {test_file}`
- **Kotlin**: `./gradlew test --tests "{TestClass}"`
- Confirm the test fails with the expected error
- If it fails for the wrong reason, fix the test first

### Step 4: Write Minimal Implementation (GREEN)
- Write the simplest code that makes the test pass
- Do NOT add extra functionality, error handling, or optimizations yet
- Run the test again — it MUST pass now
- If it doesn't pass, fix the implementation (not the test)

### Step 5: Run All Related Tests
- Run the full test suite for the module/package
- Ensure no existing tests broke
- If something broke, fix it before moving on

### Step 6: Refactor (REFACTOR)
- Clean up the implementation: remove duplication, improve naming, simplify
- Run tests after every refactor step — they must stay GREEN
- Do NOT change behavior during refactoring

### Step 7: Commit
- Stage both test and source files
- Use `feat:` or `fix:` commit type (TDD gate will see matching test files)
- Include `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`

## Rules
- Never skip the RED step — if you can't write a failing test, you don't understand the requirement
- One test at a time — don't batch multiple behaviors into one cycle
- Tests should be fast (< 5 seconds each)
- Test behavior, not implementation details
