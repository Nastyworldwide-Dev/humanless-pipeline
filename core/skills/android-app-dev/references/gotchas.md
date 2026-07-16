# Android Gotchas

Checklist the android-reviewer flags against. Organized by task area — read the
section matching what you're touching.

## Lifecycle & Leaks

- A `Context`/`Activity`/`View` stored in a singleton, companion object, or
  static field outlives the screen → leak. Use `applicationContext` for
  app-lifetime needs; never for UI/theme-dependent work.
- `BroadcastReceiver`/`SensorManager`/location callbacks registered in
  `onStart`/`onResume` must unregister in the mirror callback — asymmetric
  registration is the #1 leak source in Views code.
- ViewBinding in Fragments: clear the binding in `onDestroyView` (`_binding =
  null`) — Fragments outlive their views.
- `lateinit var` initialized in `onCreateView` but read from a coroutine that
  survives the view → `UninitializedPropertyAccessException` on rotation.

## Coroutines

- `GlobalScope` ignores lifecycle — work keeps running after the screen dies
  and holds references. `viewModelScope` / `lifecycleScope` only.
- `runBlocking` on the main thread = ANR by construction. It has no place in
  production Android code outside `main()` of a CLI tool or tests.
- A broad `catch (e: Exception)` inside a coroutine swallows
  `CancellationException` and breaks structured cancellation — re-throw it:
  `if (e is CancellationException) throw e`.
- `Dispatchers.Main.immediate` vs `Main`: posting from the main thread with
  `immediate` runs synchronously — ordering bugs when code assumed a post.
- Flows: `stateIn`/`shareIn` with `SharingStarted.Eagerly` keeps upstream
  alive forever; prefer `WhileSubscribed(5_000)`.

## Compose

- Side effects (analytics, navigation, toasts) directly in composition run on
  every recomposition — wrap in `LaunchedEffect(key)` / `DisposableEffect`.
- `collectAsState()` keeps collecting when the app is backgrounded;
  `collectAsStateWithLifecycle()` is the default choice.
- Unstable parameters (mutable lists, non-`@Immutable` classes, lambdas
  capturing changing state) defeat skipping → recomposition storms. Hoist and
  stabilize; check with the compose compiler metrics if perf regresses.
- `remember {}` without keys caches across recompositions but NOT across
  configuration changes — `rememberSaveable` for user-visible state.
- Navigation inside composition (not in an effect/callback) fires on every
  recomposition → back-stack spam.

## Manifest & Permissions

- `android:exported="true"` is required (and explicit) since API 31 for any
  component with an intent filter — but exporting without a permission guard
  makes it a public entry point. Every exported component needs a reason.
- Dangerous permissions (camera, location, contacts, …) need the runtime
  request flow — a manifest entry alone silently no-ops on M+.
- Foreground services: missing `foregroundServiceType` crashes on API 34+.
- `usesCleartextTraffic="true"` (or a permissive `network_security_config`)
  fails Play review and real security review alike — per-domain exceptions
  only, with justification.

## Data & Secrets

- Plain `SharedPreferences` is a world-readable-on-rooted-devices XML file —
  tokens/keys go in Android Keystore or `EncryptedSharedPreferences`.
- Room migrations: `fallbackToDestructiveMigration()` DROPS ALL TABLES on
  version mismatch. Fine for a cache DB; data loss for anything user-created.
- `@RawQuery` / `SupportSQLiteDatabase.execSQL` with string concatenation =
  SQL injection; bind arguments always.
- Logging PII (emails, tokens, precise location) survives in logcat on-device
  and in bug reports — mask before logging (the pipeline's logging convention
  applies: `Timber.d("[%s] ...", TAG, ...)`).
- `WebView.addJavascriptInterface` on content you don't fully control = remote
  code execution pre-API-17 semantics and data exfiltration after; avoid, or
  restrict to local trusted assets.

## Build, R8, Release

- R8 strips/renames anything not statically reachable: Gson/Moshi-reflection
  models, kotlinx-serialization with reflection, JNI callbacks need `-keep`
  rules — and the failure only appears in RELEASE builds. Always smoke-test
  `assembleRelease` output, not just debug.
- `versionCode` must strictly increase per release; Play rejects equal/lower.
  Decrementing `minSdk`/`targetSdk` casually breaks users and Play policy.
- Dynamic Gradle versions (`implementation("lib:+")`) make builds
  irreproducible — pin versions (version catalog preferred).
- `buildConfigField` strings are trivially extractable from the APK — they are
  configuration, not secret storage.

## Testing on a Headless VPS

- `testDebugUnitTest` runs on the JVM — always available.
- `connectedDebugAndroidTest` needs a device/emulator — on this VPS there is
  none; don't block the pipeline on instrumented tests, note them as
  not-run instead.
- Robolectric brings Android APIs to JVM tests when a class touches the
  framework — prefer extracting pure-Kotlin logic so plain JUnit suffices.
