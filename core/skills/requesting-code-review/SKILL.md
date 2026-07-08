---
name: requesting-code-review
description: Dispatch code review by spawning reviewer agents based on changed files and project type
---

# Code Review — Multi-Agent Review Dispatch

Spawns appropriate reviewer agents based on what changed.

## Process

### Step 1: Gather the Diff
- Get the diff: `git diff HEAD~1..HEAD` (or `git diff --staged` if pre-commit)
- List changed files: `git diff HEAD~1..HEAD --name-only`
- Count lines changed: `git diff HEAD~1..HEAD --stat`

### Step 2: Classify Changed Files
Categorize each changed file:
- **Backend code**: `.py`, `.kt`, `.go`, `.java`
- **Frontend code**: `.ts`, `.tsx`, `.js`, `.jsx`, `.css`, `.scss`
- **Config/infra**: `.json`, `.yml`, `.yaml`, `.toml`, `.sh`
- **Docs**: `.md`, `.txt`, `.rst`
- **Tests**: files matching `test_*`, `*.test.*`, `*.spec.*`

### Step 3: Select Reviewers
Spawn agents based on classification:

| Changed files | Agent to spawn | Model |
|---|---|---|
| Any code files | `arch-reviewer` | opus |
| Frontend (`.tsx`, `.css`) | `design-reviewer` | sonnet |
| Auth, permissions, API routes | `security-checker` | sonnet |
| `package.json`, `requirements.txt`, `build.gradle` | `dependency-checker` | haiku |
| Frappe app files (`hooks.py`, doctype) | `frappe-reviewer` (if installed) | sonnet |

### Step 4: Spawn Agents in Parallel
- Use the Agent tool to spawn each selected reviewer
- Provide each agent with:
  - The full diff
  - List of changed files
  - The commit message for context
- Agents run concurrently for speed

### Step 5: Collect and Report Results
- Wait for all agents to complete
- Aggregate findings by severity: CRITICAL > HIGH > MEDIUM > LOW
- If any CRITICAL findings: flag for immediate fix before deploy
- If only LOW/MEDIUM: note them but proceed with deploy

### Step 6: Act on Results
- **CRITICAL**: Block deploy, fix the issues, re-commit
- **HIGH**: Fix before deploy if possible, otherwise create follow-up task
- **MEDIUM/LOW**: Log as suggestions, proceed with deploy

## Output Format
Report results as:
```
## Code Review Summary
- Reviewers: [list of agents spawned]
- Verdict: APPROVED | APPROVED_WITH_CHANGES | CHANGES_REQUIRED
- Critical: [count]
- High: [count]
- Findings: [bulleted list]
```
