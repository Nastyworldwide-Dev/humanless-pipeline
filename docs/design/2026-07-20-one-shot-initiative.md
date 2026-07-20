> **Status: IMPLEMENTED** (2026-07-20). This is the approved plan preserved as
> a design doc. Delivery: phases 1–5 + 7 + context-packet half of 6 in commits
> `96d99be..bacde7e` (this repo); phase 8 shipped as Superset desktop
> **v1.17.525** (superset `9e3aa0c2`). The CLAUDE.md-stack prune (phase 6,
> item 19) remains gated on an eval baseline per the Sequencing section.
> Research basis: 2026-07-19 deep-research run, 23/25 claims verified.

# Plan: Humanless Pipeline — 1–2-Shot Initiative

Goal: cut median shots-to-green from "many" to ≤2 by (a) grounding every verdict
in execution, (b) making specs testable artifacts with routed back-edges, and
(c) measuring every gate change against a private eval corpus. Backed by the
2026-07-19 deep-research run (23/25 claims verified; see memory
`project_pipeline_oneshot_research.md`) plus local diagnosis of the auto-mode
clarify gap.

MOCKUP: /root/mockups/mockup-pipeline-oneshot-walkthrough.html
(interactive 8-step walkthrough of a dummy ERP task — credit-limit check —
through every upgraded stage, with dummy artifacts: assumption ledger, REQ spec,
traceability table, pre-gate output, classified findings, retro, eval dashboard.
Companion overview: /root/mockups/mockup-pipeline-oneshot-upgrades.html)

MOCKUP (Phase 8 — desktop UI, design contract):
/root/mockups/mockup-desktop-pipeline-page.html
(final-design-fidelity Pipeline page in the Superset desktop's real dark
editorial theme, built by mockup-builder from apps/desktop globals.css via the
/root/superset/.claude/design-tokens.css snapshot; render-verified by
screenshot: run list, stage flow with Review→Spec back-edge arc,
Ledger/Findings/Spec/Eval tabs, "Needs your answer" panel with working
answer-and-resume interaction, eval charts in the app's gold accent.)

## Assumptions

- A-1: All edits land in `/root/humanless-pipeline/core` (agents/hooks/skills are
  symlinked from `~/.claude`) — no superset/ERP repo changes except where noted.
- A-2: "Auto mode" is signaled by `PIPELINE_AUTONOMOUS=1` exported by whatever
  launches unattended sessions (task pipeline, tmux agent launcher); interactive
  sessions lack it.
- A-3: Reviewer re-tiering targets sonnet for reviewers, opus stays for verifier
  (refuted cheap-judge claim; deterministic pre-gates absorb the volume cost).
- A-4: Eval corpus is built from past tasks in next-nsty_custom + superset git
  history; 15–30 tasks is enough for directional deltas.

## Phase 1 — Verdict integrity (upgrades 1–3)

1. `core/agents/code-reviewer.md`, `frappe-reviewer.md`, `android-reviewer.md`,
   `verifier.md`: add EXECUTION-REQUIRED mandate — run tests/typecheck (and for
   Frappe: `bench run-tests`; Android: `gradlew test`) before any verdict; a
   text-only review is invalid output. → verify: prompt contains the mandate;
   dry-run review on a sample commit shows test execution in transcript.
2. Same files: enforce structured finding schema — file/line anchor, concrete
   failure scenario, explicit NEXT_ACTION, `defect_class` field
   (spec|plan|implementation|test). → verify: sample review emits parseable
   findings; malformed output triggers one bounded retry.
3. Model pins: `code-reviewer.md`, `tdd-runner.md` haiku→sonnet.
   → verify: frontmatter matches; Model Selection Matrix in global CLAUDE.md
   updated to match.
4. `core/hooks/post-commit-review.sh`: run deterministic pre-gates (lint,
   typecheck; Frappe: schema validate + migrate check; via new
   `core/hooks/lib/pre-gates.sh`) BEFORE spawning reviewers; pre-gate failure
   short-circuits with the failure output (no LLM spend). → verify: commit with
   a lint error never spawns a reviewer.

## Phase 2 — Auto-mode clarify / self-grill (upgrade 8)

5. `core/skills/grill-me/SKILL.md`: add autonomous branch — when
   `PIPELINE_AUTONOMOUS=1`, self-interrogate against repo + wiki + git history;
   classify each question RESOLVED (evidence) / ASSUMED (default + rationale) /
   BLOCKER; write `.claude/plans/clarify-record.md`. BLOCKERs park the task to
   backlog with open questions. → verify: headless run on a vague dummy task
   produces the ledger; a planted unanswerable question parks the task.
6. `core/skills/new-feature/SKILL.md`: autonomous variants for its three human
   gates (interview → self-grill; NEEDS_CLARIFICATION → ledger or park; mockup
   sign-off → render + screenshot self-check, tagged "pending human review").
7. `core/hooks/plan-approve.sh`: in auto mode require `clarify-record.md` to
   exist and contain zero unresolved BLOCKERs. → verify: approval refused
   without ledger.
8. `core/hooks/requirement-interpreter.sh`: also screen backlog task pickup
   (today it only screens typed prompts); in auto mode route to self-grill
   instead of "ask the user".

## Phase 3 — Spec-driven core (upgrade 6 + SDD)

9. New spec template `core/templates/spec.md`: numbered testable REQ-n
   acceptance criteria, linked assumption ledger, constitution checklist.
   `planner.md` emits it alongside the plan.
10. Extract `constitution.md` (per-repo hard invariants) out of the CLAUDE.md
    stack; spec validated against it in plan-approve.
11. `core/hooks/plan-approve.sh`: add /analyze-style consistency pass — every
    REQ covered by ≥1 planned task, no orphan tasks, checklist complete
    (deterministic script, not an LLM call). → verify: spec with an uncovered
    REQ is refused.
12. `core/hooks/tdd-gate.sh`: traceability check — every REQ maps to ≥1 test
    (mapping table in the spec); require ≥1 property test when logic-bearing
    files change (server `.py` / domain `.kt`). → verify: unmapped REQ blocks
    commit; mapping satisfies it.

## Phase 4 — Back-edges (tier 2)

13. `post-commit-review.sh`: route findings by `defect_class` —
    implementation/test → executor retry loop (as today); spec/plan → re-arm
    plan gate, require spec amendment + hash re-approval before the fix
    commit. → verify: simulated spec-defect finding re-arms the gate.
14. New `core/hooks/retro-capture.sh` (task completion): spawn cheap retro agent
    → classify why shots 2..n happened (spec gap / missing context / oracle gap
    / flaky env / other), append learning to wiki + row to
    `~/.claude/pipeline/telemetry/tasks.csv`. → verify: CSV row appears after a
    ≥2-shot task; learning file updated.
15. Deploy-verify back-edge: after auto-deploy, run the project verify/smoke
    step; failure files a task + flags the deploy (Frappe: bench smoke; desktop:
    existing verify path). → verify: planted post-deploy failure creates a task.

## Phase 5 — Oracle strengthening, stack-specific (upgrades 4–5)

16. Frappe: `pre-gates.sh` gains DocType JSON schema validation +
    `bench --site <site> migrate` success check + app-scoped
    `bench run-tests`; erpnext-app-dev skill documents hypothesis-in-
    FrappeTestCase property patterns + declarative test-record fixtures.
17. Android: add Pitest to the android deploy path (mutation floor on changed
    modules); android-app-dev skill gains kotest/jqwik property-test patterns
    + Roborazzi JVM screenshot option. All JVM — no emulator. → verify: sample
    Kotlin module runs Pitest in CI path.

## Phase 6 — Context diet + packets (upgrade 7) — AFTER eval baseline exists

18. Scout-assembled context packet per task (relevant files, invariants,
    matching wiki gotchas) injected into executor spec.
19. Prune global CLAUDE.md stack to tooling + invariants + gate mechanics;
    move narrative/gotchas to wiki retrieval. Gated on Phase 7 baseline so the
    cut is measured, not vibes. → verify: eval delta not negative.

## Phase 7 — Eval harness (tier 2, meta-loop) — built early, runs throughout

20. `core/eval/`: corpus builder (mine git history for 15–30 completed tasks
    with known-good diffs), runner (replay task on a branch per pipeline
    revision, record shots-to-green + which gate caught what), report
    (markdown + the two dashboard charts). → verify: baseline run completes on
    ≥15 tasks and emits the report.
21. Rule: every subsequent phase lands only with an eval run attached
    (before/after delta in the commit message).

## Phase 8 — Desktop Pipeline UI (design contract: mockup above)

22. `packages/host-service`: new pipeline router — list runs (backlog / running
    / green, from `~/.claude/pipeline/tasks/*` + telemetry CSV), run detail
    (clarify-record, spec, findings JSON, stage states), and a parked-task
    answer endpoint (writes answers into the task file, merges them into the
    ledger, moves the task back to the queue). memberId-scoped like every other
    router: members see only their own runs, admins see all. → verify: scoping
    test — a member token cannot read or answer another member's run.
23. `apps/desktop`: Pipeline page implementing the approved mockup — sidebar
    entry, run list with status badges, stage flow with the Review→Spec
    back-edge, Ledger/Findings/Spec/Eval tabs, "Needs your answer" panel.
    Live updates via tRPC subscription using `observable()` (trpc-electron
    rule). → verify: `bun run typecheck --filter=@superset/desktop`;
    design-reviewer MOCKUP CONTRACT check against
    /root/mockups/mockup-desktop-pipeline-page.html.
24. Answer-and-resume end-to-end: desktop → host-service → task file updated →
    self-grill merges answers into the assumption ledger → task resumes.
    → verify: a parked dummy task resumes after answering in the UI.
25. Eval tab wiring: `core/eval` emits `report.json` alongside the markdown;
    host-service serves it; desktop renders the two charts per the mockup's
    chart spec. → verify: dummy report.json renders both charts.

Phase 8 ships as a desktop release via `./scripts/build-and-deploy-desktop.sh`
(auto-deploy policy, changelog entry included).

## Sequencing

Phase 1 → Phase 2 → Phase 7 baseline → Phases 3–4 → Phase 5 → Phase 6 →
Phase 8. (Eval baseline early so SDD/back-edge phases are measured against it;
the desktop UI lands last because it displays the artifacts Phases 2–4 and 7
produce — pulling it earlier just means empty screens.)

## Risks

- Reviewer execution raises per-review latency/cost — offset by pre-gate
  short-circuit (lint failures no longer reach LLM review).
- Property tests on legacy Frappe logic may surface pre-existing bugs — triage
  as findings, don't block the phase on them.
- Eval replay on ERP needs an isolated bench site — reuse CI site pattern from
  next-nsty_custom.
- AGENTS.md-pruning evidence is Python-heavy/preprint — hence Phase 6 is
  measured-only.
- Shared `~/mockups` was wiped by a concurrent session during this planning
  session (restored from context). Adopt per-repo subdirs
  (`~/mockups/<repo>/`) as a small hardening item in Phase 2; plan-approve and
  mockup-builder accept both layouts during transition.

## EXPECTED OUTPUT

- Unattended tasks behave exactly as the walkthrough mockup demonstrates
  (open /root/mockups/mockup-pipeline-oneshot-walkthrough.html): backlog task →
  assumption ledger → REQ spec → traceability gate → deterministic pre-gates →
  execution-grounded review with classified, routed findings → retro entry.
- New on-disk artifacts per task: `clarify-record.md`, `spec-<task>.md` with
  REQ↔test mapping, telemetry rows in `~/.claude/pipeline/telemetry/tasks.csv`.
- Reviewers never verdict without running the code; spec-defect findings amend
  the spec instead of silently patching code.
- `core/eval/report.md` after each phase: shots-to-green trend + rerun-cause
  histogram (real versions of the mockup's dummy charts) proving/refuting each
  phase's impact.
- Ships as commits to /root/humanless-pipeline (hooks/skills/agents are
  symlinked live — no deploy step; ERP/Android repos pick changes up on next
  session).
- Phase 8: a "Pipeline" page in the Superset desktop app matching the approved
  mockup — watch runs live, read ledgers/specs/findings, answer BLOCKER
  questions from the UI to un-park tasks, and see the real eval charts. Ships
  as a desktop release via the auto-deploy script with a changelog entry.

## Pipeline Summary

requirements (this plan + research memory) → planning: inline (Advisor, fable)
→ mockup: BUILT — /root/mockups/mockup-pipeline-oneshot-walkthrough.html
(render-verified via agent-browser screenshots) → workspace: /root/humanless-
pipeline direct (symlinked live) → TDD: hook changes get fixture-driven bash
tests (verify.sh pattern); skills/agents are markdown (chore-prefix) → auto-
commit per phase (conventional commits) → auto-review via post-commit hook
(the Phase-1-upgraded reviewers review later phases) → deploy: none needed
(symlinks); eval run attached per phase → EXPECTED OUTPUT above.
