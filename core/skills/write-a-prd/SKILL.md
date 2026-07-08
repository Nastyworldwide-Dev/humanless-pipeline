---
name: write-a-prd
description: Generate a Product Requirements Document as a GitHub issue from gathered requirements
---

# Write a PRD — Product Requirements Document Generator

Turn understanding (from `/grill-me` or clear user input) into a structured GitHub issue PRD.

## Process

### Step 1: Gather Context
- Review the requirement summary (from `/grill-me` or user input)
- Scan the codebase for related files: `Glob` for similar patterns
- Check git history for related changes: `git log --oneline --all --grep="{keyword}"`

### Step 2: Write the PRD

Structure the PRD as a GitHub issue body:

```markdown
## Problem Statement
[What problem does this solve? Why now?]

## Proposed Solution
[High-level approach — what will be built]

## Detailed Requirements

### Must Have (P0)
- [ ] [Specific, testable requirement]
- [ ] [Specific, testable requirement]

### Should Have (P1)
- [ ] [Requirement]

### Nice to Have (P2)
- [ ] [Requirement]

## Technical Approach
- **Affected files**: [list key files that will change]
- **New files needed**: [list any new files]
- **Data model changes**: [any schema/migration changes]
- **API changes**: [any new/modified endpoints]

## Acceptance Criteria
- [ ] [Criterion 1 — how to verify]
- [ ] [Criterion 2 — how to verify]

## Out of Scope
- [Explicitly excluded items]

## Dependencies
- [Any blocking items or related issues]
```

### Step 3: Review with User
- Present the PRD to the user
- Ask for corrections or additions
- Iterate until approved

### Step 4: Create GitHub Issue (Optional)
- If user confirms, create the issue:
  ```bash
  gh issue create --title "feat: {title}" --body "{prd_body}"
  ```
- Add appropriate labels: `feature`, `P0`/`P1`/`P2`
- Return the issue URL

### Step 5: Next Steps
- Suggest: "Run `/prd-to-issues` to break this into implementation tasks"
- Or: "Run `/new-feature` to start implementing directly"

## Rules
- Every requirement must be testable (has a clear pass/fail)
- Keep PRDs under 500 words — concise beats comprehensive
- Link to existing code/issues where relevant
- Don't include implementation details in requirements (that's the impl-designer's job)
