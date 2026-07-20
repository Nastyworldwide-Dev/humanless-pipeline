# Constitution — {repo-name}

Non-negotiable invariants for this repo. Every spec is validated against
this list before plan approval (`CONSTITUTION: PASS` in the spec asserts it).
Keep this file SHORT — hard rules only, not guidance. Guidance lives in the
wiki; tooling commands live in CLAUDE.md. Extract entries from the repo's
CLAUDE.md stack rather than inventing new rules.

## Rules

- C-1: {e.g. Never touch the production database; migrations via drizzle-kit generate only}
- C-2: {e.g. Every host-service router scopes reads/writes by caller memberId}
- C-3: {e.g. TDD required on feat/fix; conventional commits}
- C-4: {e.g. tRPC subscriptions use observable(), never async generators}
