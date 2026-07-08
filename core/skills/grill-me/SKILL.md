---
name: grill-me
description: Interview the user exhaustively to reach shared understanding of requirements before implementation
---

# Grill Me — Requirements Interview

Systematically interview the user to turn vague ideas into concrete, implementable requirements.

## Process

### Step 1: Initial Understanding
- Read the user's initial request carefully
- Identify what is clear vs what is ambiguous
- Note any assumptions you're making

### Step 2: Ask Clarifying Questions (Round 1 — Scope)
Ask these in a single message:
1. **What** exactly should this do? (specific behavior, not goals)
2. **Who** will use this? (user type, permissions needed)
3. **Where** does this live in the codebase? (which module/app/service)
4. **What exists today?** (is this new or modifying existing behavior)

### Step 3: Ask Technical Questions (Round 2 — Design)
Based on Round 1 answers:
1. **Data model**: What data does this need? New fields/tables or existing?
2. **API surface**: Any new endpoints or UI pages?
3. **Integration**: Does this touch external services or other modules?
4. **Edge cases**: What happens when input is invalid/missing/unexpected?

### Step 4: Ask Priority Questions (Round 3 — Constraints)
1. **Must-have vs nice-to-have**: Which parts are essential for v1?
2. **Performance**: Any latency or throughput requirements?
3. **Security**: Any auth, permissions, or data sensitivity concerns?
4. **Timeline**: Is this blocking something else?

### Step 5: Summarize Understanding
Present back to the user:
```
## Requirement Summary
- **Feature**: [one-line description]
- **Scope**: [files/modules affected]
- **Behavior**: [bullet list of specific behaviors]
- **Acceptance criteria**: [how to verify it works]
- **Out of scope**: [explicitly excluded items]
- **Assumptions**: [things you're assuming — ask user to confirm]
```

### Step 6: Confirm or Iterate
- Ask: "Does this capture your intent? Anything missing or wrong?"
- If corrections needed: update the summary and re-confirm
- If confirmed: proceed to `/write-a-prd` or `/new-feature`

## Rules
- Ask questions in batches (3-5 at a time), not one by one
- Don't assume — if something is unclear, ask
- Focus on BEHAVIOR not implementation details
- Stop after 3 rounds of questions maximum — if still unclear, summarize what you know and flag gaps
