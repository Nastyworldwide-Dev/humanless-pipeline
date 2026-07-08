---
name: release
description: Version bump, changelog, tag, and push for Node/generic projects
---

# Release — Version Management and Release

Handles version bumping, tagging, and pushing releases.

## Process

### Step 1: Determine Version Bump Type
Analyze commits since last tag:
```bash
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -n "$LAST_TAG" ]; then
  COMMITS=$(git log "$LAST_TAG"..HEAD --oneline)
else
  COMMITS=$(git log --oneline)
fi
```

Version bump rules:
- **major**: Any commit message contains `BREAKING CHANGE` or `!:` suffix
- **minor**: Any `feat:` commits
- **patch**: Only `fix:`, `chore:`, `refactor:`, `docs:`, etc.

### Step 2: Pre-Release Checks
- Ensure working tree is clean: `git status --porcelain`
- Ensure all tests pass: run project test suite
- Ensure on the correct branch (main/master/release)

### Step 3: Bump Version
Detect project type and bump accordingly:

**Node (package.json)**:
```bash
npm version {patch|minor|major} --no-git-tag-version
```

**Python (pyproject.toml / setup.cfg)**:
- Update version string in the config file

**Generic**:
- Create annotated git tag: `git tag -a v{version} -m "Release v{version}"`

### Step 4: Generate Changelog Entry
Create changelog from commits since last tag:
```
## v{version} — {date}

### Features
- {feat commit messages}

### Bug Fixes
- {fix commit messages}

### Other
- {other commit messages}
```

### Step 5: Commit and Tag
```bash
git add -A
git commit -m "chore(release): v{version}

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git tag -a "v{version}" -m "Release v{version}"
```

### Step 6: Push
```bash
git push --follow-tags
```

### Step 7: Report
Output the release summary:
- Version: `v{old}` → `v{new}`
- Commits included: `{count}`
- Tag: `v{version}`
- Push status: success/failure

## Rules
- Never release from a dirty working tree
- Always run tests before releasing
- Use semantic versioning (semver)
- Include Co-Authored-By in release commit
