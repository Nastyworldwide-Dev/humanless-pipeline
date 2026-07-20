# Spec: {feature-name}

STATUS: draft
<!-- draft → approved (plan-approve.sh validates this file when present) -->

## Requirements

Each requirement is ID'd and phrased so a test can check it mechanically —
"REQ-1: submitting X over limit Y fails with error Z", never "handle limits
properly". Requirements are the contract; the mapping below makes them the
test plan.

- REQ-1: {testable acceptance criterion}
- REQ-2: {testable acceptance criterion}

## Assumptions

Carried over from `.claude/plans/clarify-record.md` (auto mode) or the
interview. Reference them from requirements as (A-1).

- A-1: {assumed default + rationale}

## Constitution check

Validate every rule in `<repo>/.claude/constitution.md` against this spec.
The line below is machine-checked by plan-approve.sh when a constitution
exists — write it only after actually checking.

CONSTITUTION: PASS

## REQ ↔ Test mapping

Every REQ maps to ≥1 test (file path required; `::test_name` optional).
tdd-gate.sh BLOCKS feat/fix commits while any REQ here is unmapped or maps
to a missing file. Add rows as tests are written (red → green).

| REQ | Test |
|-----|------|
| REQ-1 | {tests/test_feature.py::test_criterion} |
| REQ-2 | {tests/test_feature.py::test_other} |

PROPERTY TESTS: REQUIRED
<!-- REQUIRED for logic-bearing changes (pricing, permissions, state
     transitions, parsing): at least one mapped test file must contain a
     property test (hypothesis @given / kotest checkAll / jqwik forAll).
     Unit tests are the agent's optimization target and overestimate
     correctness — 18-23% of unit-passing LLM code fails PBT.
     Non-logic work: PROPERTY TESTS: N/A (<reason>) -->

## Amendments

Review findings with defect class `spec` route BACK here — amend the
requirement (REQ-n+1 or edited REQ), re-approve the plan (hash re-arms),
then fix code. Never patch code past a wrong spec.

- {date} REQ-{n}: {what changed and which finding forced it}
