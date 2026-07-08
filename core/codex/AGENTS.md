<!-- Humanless Pipeline — global Codex guidance. Managed by humanless-pipeline
     install.sh (symlinked into ~/.codex/AGENTS.md). Edit in the repo, not here. -->

# Humanless Pipeline — Working Agreement

This machine runs the Humanless Pipeline. Quality gates are enforced at the
**git layer** for every tool, including you:

- **pre-commit**: auto-fixes lint/format issues (ruff/biome/eslint/oxlint/
  prettier), stages the fixes, then **blocks the commit** if unfixable lint or
  type errors remain. Fix what it reports and commit again.
- **commit-msg**: warns when the message is not conventional-commits format.
- **post-commit**: prints `REVIEW REQUIRED` after non-trivial commits — act on
  it before pushing.

## Commit conventions

- Conventional commits: `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`,
  `test:`, `perf:`, `ci:` — first line under 72 chars, body explains why.
- Descriptive branches: `feat/feature-name`, `fix/bug-description`.
- Never force-push `main`/`master`. Prefer new commits over amending.

## TDD

For `feat:` and `fix:` changes, write the failing test first, then implement
(red → green → refactor). Skip tests only for config-only changes, typo
fixes, pure restyling, or when the user explicitly says "skip tests" — and
use a `chore:`/`docs:` prefix in those cases.

## Review before push

After completing a feature or fix, run a code review of the diff
(`codex review`) before pushing. Severity handling: **Critical** — fix
immediately; **Important** — fix before pushing; **Minor** — note and move on.

## Deploys are admin-only

Deploy-phase commands (version bumps, production builds, `bench migrate`,
release pushes) are restricted to admins listed in
`~/.claude/config/deploy-permissions.json`. If the current user is not an
admin, stop and tell the user instead of deploying.

## Logging convention

Every new function/method longer than ~5 lines should include at least one
contextual log statement (logger.info/warn/error with context — no secrets,
no PII). The pipeline relies on log trails for self-diagnosis.
