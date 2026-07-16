---
name: android-app-dev
description: Build and maintain Android apps (Kotlin, Jetpack Compose) correctly — module layout, manifest & permissions, coroutines/lifecycle, data layer, testing, detekt, release builds. Load references/gotchas.md before writing Android code.
---

# Android App Development

Process for building and maintaining Kotlin/Compose Android apps. The deep
gotcha list lives in `references/gotchas.md` — read the section matching your
task before coding.

## Step 1: Orient in the Project

```bash
./gradlew projects                 # module layout
cat app/build.gradle.kts           # compileSdk/minSdk/targetSdk, versionCode/Name, deps
cat app/src/main/AndroidManifest.xml
ls app/src/main/java app/src/test app/src/androidTest 2>/dev/null
```

- Identify the UI system first: `@Composable` grep hit → Compose; `res/layout/*.xml` → Views (many apps mix both).
- Find the theme source before any UI work: Compose `Theme.kt`/`Color.kt`/`Type.kt` or `res/values/{themes,colors}.xml` — new UI must use it, never hardcoded colors.
- Check for detekt config (`detekt.yml` / `config/detekt/`) — the pre-commit gate runs `./gradlew detekt --auto-correct` when present.

## Step 2: Architecture Conventions

- **UI → ViewModel → Repository → data source.** UI never touches the data layer directly.
- State flows down (`StateFlow`/Compose state), events flow up (lambdas/sealed events).
- One `ViewModel` per screen; expose a single immutable UI-state object where practical.
- Dependency injection: follow whatever the project already uses (Hilt/Koin/manual) — do not introduce a new DI framework into an existing app.

## Step 3: Coroutines & Lifecycle

- Scopes: `viewModelScope` in ViewModels, `lifecycleScope`/`repeatOnLifecycle` in UI, **never `GlobalScope`**.
- Blocking work (network/DB/file) on `Dispatchers.IO`; the main thread renders, nothing else.
- Collect flows in UI with `collectAsStateWithLifecycle()` (Compose) or `repeatOnLifecycle` (Views).
- Every register has an unregister; every listener has a lifecycle owner.

## Step 4: Manifest & Permissions

- New permission → runtime-request flow for dangerous permissions + a one-line rationale in the PR/commit body.
- `android:exported="true"` only with an intent filter you intend to be public, or a permission guard.
- Foreground services need `foregroundServiceType`; cleartext traffic stays off.

## Step 5: Data & Secrets

- Secrets never in code, `BuildConfig`, or plain `SharedPreferences` — use Keystore / `EncryptedSharedPreferences`.
- Room: schema change → bump `version` + provide a `Migration`; `fallbackToDestructiveMigration` never ships to production data.
- Parameterize all raw SQL; no string concatenation into queries.

## Step 6: TDD & Quality Gates

- Unit tests mirror the source path: `app/src/test/java/.../{Name}Test.kt` (the tdd-gate hook checks `test/` and `androidTest/` mirrors for `feat:`/`fix:` commits).
- Run locally what the gates run:

```bash
./gradlew detekt --auto-correct    # lint gate (when detekt config exists)
./gradlew testDebugUnitTest        # unit tests
./gradlew connectedDebugAndroidTest  # instrumented (device/emulator required — skip on headless VPS)
```

## Step 7: Commit → Review → Retry

Same pipeline as ERPNext apps, with Android-specific reviewers:

1. Commit (conventional message). The post-commit hook spawns **android-reviewer**
   (manifest/lifecycle/coroutines/Compose/data-safety checks), plus
   **design-reviewer** with android checks when UI files changed (and the
   MOCKUP CONTRACT when the plan has one), **security-reviewer** on
   auth/manifest/webview/crypto changes, and **dependency-checker** on Gradle
   dependency changes.
2. `NEXT_ACTION: FIX_CRITICAL` → fix the findings, re-commit — the hook
   re-triggers the review. Repeat until `NEXT_ACTION: DEPLOY`.
3. `NEXT_ACTION: DEPLOY` → the deploy skill's Android path runs:
   versionCode/versionName bump → detekt + unit tests → `assembleRelease` →
   APK archived to `~/android-releases/` → tag → push.

## Step 8: Release Checklist

- `versionCode` strictly increases; `versionName` follows semver-ish (feat → minor, fix → patch).
- R8/ProGuard: new reflection/serialization models need keep rules — test the release build, not just debug.
- Signed build requires the project's `signingConfig`; without one, `assembleRelease` produces an unsigned APK — say so in the report rather than shipping it silently.
