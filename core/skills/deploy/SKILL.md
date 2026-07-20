---
name: deploy
description: Auto-deploy based on detected project type — Frappe, monorepo, Node, Electron, Android, or generic
---

# Deploy — Project-Aware Auto-Deploy

Detects project type and runs the appropriate deploy strategy.

## Process

### Step 0: Authorization Check
Before running any deploy commands, the `deploy-gate.sh` PreToolUse hook automatically checks
if the current user is in `admin_users` in `~/.claude/config/deploy-permissions.json`.
- If authorized: proceed to Step 1.
- If blocked: the hook writes a pending record to `~/.claude/pipeline/deploy-pending/` and
  instructs you to notify the admin. Follow the notification instruction in the block message.
  Do NOT attempt to bypass the gate. Report to the user: "Deploy blocked pending admin approval."

### Step 1: Detect Project Type
Check for marker files (walk up from CWD):
- `sites/common_site_config.json` + `apps/` → **Frappe bench**
- `turbo.json` + `bun.lock` → **Bun monorepo**
- `electron-builder.yml` → **Electron app**
- `build.gradle.kts` + `app/src/` → **Android**
- `package.json` (standalone) → **Node app**
- None of the above → **Generic** (commit + push only)

### Step 2: Run Pre-Deploy Checks
- Ensure all tests pass: run the project's test suite
- Ensure no uncommitted changes: `git status --porcelain`
- Ensure branch is up to date: `git pull --rebase`

### Step 3: Deploy by Type

#### Frappe App
1. **Version bump**: Determine bump type from commits since last tag:
   - `BREAKING CHANGE` or `!:` → **major**
   - Any `feat:` → **minor**
   - Only `fix:`, `chore:`, `refactor:`, `docs:` → **patch**
   ```bash
   LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
   if [ -n "$LAST_TAG" ]; then
     COMMITS=$(git log "$LAST_TAG"..HEAD --oneline)
   else
     COMMITS=$(git log --oneline -20)
   fi
   ```
2. **Update version** in `{app}/__init__.py` (`__version__ = "x.y.z"`):
   ```bash
   # Parse current version, increment, and write back
   sed -i "s/__version__ = \".*\"/__version__ = \"${NEW_VERSION}\"/" {app}/__init__.py
   ```
3. **Commit version bump**:
   ```bash
   git add {app}/__init__.py
   git commit -m "chore(release): v${NEW_VERSION}

   Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
   ```
4. **Tag**: `git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"`
5. **Push with tags**: `git push --follow-tags`
6. **Migrate** (if bench is available on this machine):
   - Identify site from `currentsite.txt`
   - `bench --site {site} migrate`
   - `bench --site {site} clear-cache`
7. **Report**: version change, tag, push status, migration status

#### Bun Monorepo
1. Install: `bun install`
2. Build: `bunx turbo run build`
3. Test: `bunx turbo run test`
4. Push: `git push`
5. If CI/CD is configured, the push triggers deployment

#### Node App
1. Test: `npm test` or `bun test`
2. Version bump: `npm version patch|minor|major` (based on commit types)
3. Push with tags: `git push --follow-tags`

#### Electron App
1. Build: `npm run build` or `electron-builder`
2. Test: `npm test`
3. Push: `git push --follow-tags`

#### Android App
Mirrors the Frappe flow (version bump → gates → build → tag → push), with Gradle in place of bench:
1. **Version bump** in `app/build.gradle.kts`: increment `versionCode` by 1;
   bump `versionName` using the same commit-type rules as Frappe
   (`feat:` → minor, otherwise patch; `BREAKING CHANGE` → major).
2. **Quality gates** (stop on failure, report verbatim):
   ```bash
   ./gradlew detekt            # only when detekt config exists
   ./gradlew testDebugUnitTest
   ./gradlew pitest            # only when pitest plugin configured — mutation
                               # floor on domain modules; below-threshold FAILS
                               # the gate. Not configured -> report
                               # "MUTATION: not-configured" (never silent).
   ```
   (`connectedDebugAndroidTest` needs a device/emulator — skip on a headless
   VPS and note it as not-run. Everything above is pure JVM.)
3. **Build**: `./gradlew assembleRelease`. If the project has no
   `signingConfig`, the APK is UNSIGNED — say so explicitly in the report,
   never silently.
4. **Archive artifact**: `mkdir -p ~/android-releases && cp
   app/build/outputs/apk/release/*.apk
   ~/android-releases/{project}-v${NEW_VERSION}.apk`
5. **Commit version bump**: `chore(release): v${NEW_VERSION}` (with Co-Authored-By)
6. **Tag + push**: `git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}" && git push --follow-tags`
7. **Report**: version, artifact path, signed/unsigned, test summary.

#### Generic
1. `git push`
2. Report: "No project-specific deploy strategy detected. Code pushed."

### Step 4: Post-Deploy Verification (back-edge — MANDATORY, not passive)
Actively drive the deployed artifact; reading logs alone is not verification:
- **Frappe**: `bench --site {site} migrate` exit code + hit one changed endpoint/page
  (agent-browser or `bench execute`) and confirm the changed behavior responds
- **Electron/desktop**: SHA-512 of the shipped artifact + service healthcheck
  (the build-and-deploy script's checks count)
- **Android**: APK exists in `~/android-releases/` and `aapt dump badging` (when
  available) shows the new versionCode
- **Node/monorepo**: hit the service healthcheck or run the smoke script if one exists

On verification FAILURE — the back-edge fires:
1. File a task: write `~/.claude/pipeline/tasks/backlog/task-$(date +%s).md` with
   `status: backlog`, the failure output, and the deployed version — the pipeline
   picks it up as a first-class task
2. Flag the deploy in the report as SHIPPED-BUT-UNVERIFIED or roll back (below)
3. Emit a `LEARNING:` line if a gate should have caught this pre-deploy
- Log the deploy event for cost tracking

## Rollback
If deployment fails:
1. **Frappe**: `bench --site {site} restore {backup_path}`
2. **Node/Electron**: `git revert HEAD && git push`
3. **Android**: `git revert HEAD && git push` — the previous APK stays in `~/android-releases/`; reinstall it on devices if one already shipped
4. **Generic**: `git revert HEAD && git push`
