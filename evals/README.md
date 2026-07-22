# Evals — the pipeline's yardstick (L5)

Replays real completed tasks against the harness and scores them. Every
harness change re-runs the baseline; green-rate up / cost down = the change
earned its keep. This is what makes R2–R7 measurable instead of vibes.

## How it works (SWE-bench pattern)

1. `corpus/<task>.json` pins a real historical task: the repo, the commit
   BEFORE the fix (`base`), the real fix commit (`ref`), a prompt
   reconstructed as the user would have asked it, and the ref commit's test
   files as the oracle.
2. `run-eval.sh corpus/<task>.json` makes a detached worktree at `base`,
   runs a headless `claude -p` on the prompt (plan-approval gate off — no
   human present; every other hook fires normally), then grafts the REF
   commit's test files over the agent's work and runs them.
3. Green = the future tests pass on the agent's independent fix.
   Results append to `~/.claude/pipeline/evals/results.jsonl`;
   `scoreboard.sh` renders the markdown table.

## Caveats

- `env_error` rows (broken setup, missing deps) are excluded from the green
  rate — they measure the harness environment, not the agent.
- Oracle tests are the ref commit's own tests: passing them means "matches
  the shipped behaviour", which is the point, but a *better* alternative fix
  that legitimately changes the API would score red. Keep corpus tasks small
  and behaviour-pinned.
- Frappe tasks score on locally runnable oracles only (JS/vitest); bench
  tests need CI (no local bench on this VPS).

## Running

```bash
evals/run-eval.sh evals/corpus/superset-1m-context.json          # one task
for c in evals/corpus/*.json; do evals/run-eval.sh "$c"; done     # baseline
evals/scoreboard.sh                                               # render
```
