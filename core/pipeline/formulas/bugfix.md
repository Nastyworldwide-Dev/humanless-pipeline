# Bugfix Formula

## Pipeline: investigate -> reproduce -> tdd-red -> fix -> commit -> review -> deploy

### Variables
- **project**: Target project/package
- **title**: Bug description
- **description**: Steps to reproduce, expected vs actual behavior
- **file_hints**: Suspected files

### Steps

1. **Investigate** -- Read error logs, trace code path, identify root cause
2. **Reproduce** -- Write a test that reproduces the exact failure (red)
3. **Fix** -- Implement minimal fix to make test pass (green)
4. **Verify** -- Run full test suite, no regressions
5. **Commit** -- fix: conventional commit
6. **Review** -- code-reviewer + domain reviewers auto-fire
7. **Deploy** -- project-type-specific deploy skill

### Constraints
- Fix root cause, not symptoms
- Always write regression test first
- Check git blame for original intent before changing logic
- Minimal change -- don't refactor surrounding code
