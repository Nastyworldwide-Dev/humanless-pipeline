---
name: new-feature
description: Full feature pipeline orchestrator — requirements → design → TDD → commit → review → deploy
---

# New Feature — Full Pipeline Orchestrator

Runs the complete feature development pipeline from requirement to deployment.

## Process

### Step 1: Requirements Gathering
- If the requirement is vague (< 2 sentences or uses words like "improve", "fix", "make better"):
  - Run `/grill-me` to interview the user and reach shared understanding
- If the requirement is clear and specific:
  - Proceed to Step 2

### Step 2: Scope Analysis
- Spawn `scope-analyzer` agent to map:
  - Affected files and modules
  - Dependencies between changed components
  - Risk areas (shared code, APIs, database schema)
- Review scope output before proceeding

### Step 3: Plan (fable)
- Spawn `planner` agent (model: fable — highest tier) with the scope analysis results
- Produces the full-lifecycle plan: assumptions, approach, numbered steps, risks,
  mockup gate decision, and the mandatory Pipeline Summary
- If the plan returns `NEEDS_CLARIFICATION`, resolve with the user before proceeding

### Step 4: Mockup (sonnet — UI features only)
- If the planner marked `MOCKUP GATE: REQUIRED`, spawn `mockup-builder` agent (model: sonnet)
- Mockup lands at `/tmp/mockup-<feature>.html` — single self-contained interactive HTML file
- **Get user sign-off on the mockup BEFORE any production code**
- Backend-only features (`MOCKUP GATE: NOT NEEDED`) skip straight to Step 5

### Step 5: Implementation Design
- Spawn `impl-designer` agent with the approved plan and scope analysis results
- Agent produces step-by-step implementation plan
- If scope is large (>10 files affected), also spawn `arch-reviewer` for architecture validation

### Step 6: Test Planning
- Spawn `test-planner` agent to identify:
  - Test cases needed for the new feature
  - Existing tests that might be affected
  - Coverage gaps

### Step 7: TDD Implementation
- Follow the `/tdd` skill for each component:
  1. Write failing test (RED)
  2. Implement minimal code (GREEN)
  3. Refactor
- Work through components in dependency order (leaf nodes first)

### Step 8: Commit
- Stage all changes (source + tests)
- Write conventional commit message: `feat(scope): description`
- Include `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
- Post-commit hooks will auto-trigger code review

### Step 9: Code Review (Auto-Triggered)
- `post-commit-review` hook spawns reviewers automatically
- `/requesting-code-review` skill dispatches appropriate agents
- Address any CRITICAL or HIGH findings before proceeding

### Step 10: Deploy (Auto-Triggered)
- After review passes, run `/deploy` skill
- Deploy strategy is auto-detected based on project type
- Verify deployment success

## Pipeline Formula
```
scope-analyzer → planner (fable) → mockup-builder (sonnet, UI only) → impl-designer → test-planner → /tdd → commit → review → /deploy
```
Orchestration (this skill + the main session) runs on fable; sub-stages run on
their pinned models (see Model Selection Matrix in CLAUDE.md).

## Failure Handling
- If any step fails, stop and report the failure
- Do NOT skip steps or proceed past failures
- Create a task in backlog for follow-up if needed
