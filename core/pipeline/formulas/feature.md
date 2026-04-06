# Feature Formula

## Pipeline: scope -> impl -> tdd -> commit -> review -> deploy

### Variables
- **project**: Target project/package
- **title**: Feature title
- **description**: What to build
- **file_hints**: Suggested files/directories to modify
- **acceptance_criteria**: Definition of done

### Steps

1. **Scope Analysis** -- Run scope-analyzer to map affected files, modules, dependencies
2. **Implementation Design** -- Run impl-designer for step-by-step approach
3. **TDD Red** -- Write failing test first
4. **TDD Green** -- Implement minimal code to pass test
5. **TDD Refactor** -- Clean up, follow coding standards
6. **Commit** -- Conventional commit with Co-Authored-By
7. **Review** -- code-reviewer + domain reviewers auto-fire
8. **Deploy** -- project-type-specific deploy skill

### Constraints
- Follow project/framework conventions
- Parameterized queries only (no string interpolation in SQL)
- Use migration files for schema changes (not manual DB changes)
- Tests required for feat: commits
