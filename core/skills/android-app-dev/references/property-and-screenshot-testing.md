# Android Oracles Without an Emulator (property + mutation + screenshots)

This VPS has no emulator — and none is needed. Meta's ACH ran mutation-guided
test generation on 10,795 Android Kotlin classes as pure JVM unit tests
through CI (FSE 2025). Everything below runs in `./gradlew test`.

## Property tests (kotest / jqwik) — spec `PROPERTY TESTS: REQUIRED`

tdd-gate accepts markers `checkAll` / `forAll` / `@Property`.

```kotlin
// kotest
class PriceCalcTest : StringSpec({
    "discount never exceeds subtotal" {
        checkAll(Arb.positiveInt(1_000_000), Arb.int(0..100)) { cents, pct ->
            discount(cents, pct) shouldBeLessThanOrEqual cents
        }
    }
})
```

```kotlin
// jqwik
@Property
fun `parse then format is identity`(@ForAll amount: @BigRange(min = "0") BigDecimal) {
    parse(format(amount)) shouldBe amount
}
```

Target invariants: round-trips (parse/format, serialize/deserialize),
monotonicity, bounds (discount ≤ subtotal), state-machine transitions.

## Mutation floor (Pitest) — deploy-path gate

When the project applies the pitest plugin, the Android deploy path runs
`./gradlew pitest` after unit tests and treats a mutation score below the
configured floor as a gate failure (weak oracle: tests pass but kill few
mutants). Setup:

```kotlin
// build.gradle.kts (module)
plugins { id("info.solidsoft.pitest") version "1.15.0" }
pitest {
    targetClasses.set(listOf("com.example.domain.*"))  // domain logic only — not UI
    junit5PluginVersion.set("1.2.1")
    mutationThreshold.set(60)   // the floor; raise as the suite hardens
}
```

Not configured → the deploy report says `MUTATION: not-configured` (visible,
never silent). Scope to domain/logic modules; mutating Compose UI is noise.

## Screenshot evidence (Roborazzi) — rendered proof for design review

Robolectric renders Compose on the host JVM; Roborazzi pixel-diffs it:

```kotlin
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CheckoutScreenshotTest {
    @get:Rule val composeRule = createComposeRule()

    @Test fun checkout_default() {
        composeRule.setContent { CheckoutScreen(sampleState) }
        composeRule.onRoot().captureRoboImage()   // ./gradlew recordRoborazziDebug / verifyRoborazziDebug
    }
}
```

Pair with ComposablePreviewScanner to turn every `@Preview` into a screenshot
test automatically. This gives design-reviewer rendered evidence instead of
judging Compose code as text.
