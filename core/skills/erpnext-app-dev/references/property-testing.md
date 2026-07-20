# Property-Based Testing in Frappe (hypothesis + FrappeTestCase)

Why: unit tests are the agent's own optimization target — 18–23% of
unit-test-passing LLM code fails property-based testing outright. For
logic-bearing Frappe code (pricing, rounding, permission scoping, doc-state
transitions), the spec's `PROPERTY TESTS: REQUIRED` line makes ≥1 property
test mandatory (tdd-gate blocks otherwise; marker: `@given`).

## Pattern: hypothesis inside FrappeTestCase

FrappeTestCase wraps each test in a rolled-back transaction — exactly the
isolation hypothesis needs for its many examples per test.

```python
from frappe.tests.utils import FrappeTestCase
from hypothesis import given, settings, strategies as st

AMOUNTS = st.decimals(min_value=0, max_value=10_000_000, places=2)

class TestCreditLimit(FrappeTestCase):
    @settings(max_examples=50, deadline=None)  # deadline=None: DB calls are slow
    @given(exposure=AMOUNTS, total=AMOUNTS, limit=AMOUNTS)
    def test_block_iff_over_limit(self, exposure, total, limit):
        # Invariant, not an example: block ⇔ exposure + total > limit > 0
        blocked = would_block(exposure, total, limit)
        assert blocked == (limit > 0 and exposure + total > limit)
```

Rules of thumb:
- Test the INVARIANT (round-trip, monotonicity, conservation, permission
  boundary), not re-derived example values.
- `deadline=None` + modest `max_examples` (25–50) when the property touches
  the DB; pure-function properties can run hundreds.
- Never `@given` on values that create submitted docs per example unless the
  property is about submission — build cheap in-memory calls where possible.
- Good Frappe invariants: exposure calc ignores `docstatus != 1`; rounding
  never changes grand totals by > 0.01; a user without role R can never
  read doc D (permission scoping); state machine only moves along allowed
  transitions.

## Declarative fixtures (determinism)

Never improvise `frappe.get_doc({...}).insert()` chains per test. Declare:

```python
# in the test module
EXTRA_TEST_RECORD_DEPENDENCIES = ["Customer", "Item"]   # auto-loads their test records
IGNORE_TEST_RECORD_DEPENDENCIES = ["Company"]           # skip auto-load when unwanted
```

Test records live in `test_records.json` next to the DocType and load once,
deterministically, before the case runs. Imperative setup is the #1 source of
flaky/order-dependent Frappe tests.
