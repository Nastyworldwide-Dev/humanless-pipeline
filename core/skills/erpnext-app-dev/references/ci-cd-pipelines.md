# Frappe/ERPNext CI/CD Pipeline Canon (v15 era)

Verified against frappe-org repos (July 2026). Use when building or fixing
pipelines for custom Frappe apps. Companion: `gotchas.md` (code-level),
this file (pipeline-level).

## Server-test CI (the canonical shape)

`bench new-app` scaffolds `.github/workflows/ci.yml` from
`frappe/utils/boilerplate.py` — there is NO official reusable setup action;
everyone uses plain workflows + repo-local install scripts.

Recipe (what our next-nsty_custom ci.yml already matches):
- Services: `mariadb:10.6` (root/root, health-cmd `mariadb-admin ping`) +
  TWO `redis:alpine` services on ports **13000** (cache) and **11000** (queue)
  — these match bench's default ports, paired with `--skip-redis-config-generation`.
- Python 3.10/3.11, Node 18 (v15 standard); pip + yarn caches.
- `pip install frappe-bench` → `bench init --skip-redis-config-generation
  --skip-assets` → set `utf8mb4` globals via mariadb CLI →
  `bench get-app <app> $GITHUB_WORKSPACE` (installs the checked-out working
  copy) → `bench setup requirements --dev` → `bench new-site
  --db-root-password root --admin-password admin test_site` → `install-app`
  → `bench build` (`CI: 'Yes'`).
- `bench --site test_site set-config allow_tests true` then
  `bench --site test_site run-tests --app <app>`.

Mature-app upgrades (frappe/hrms pattern):
- **Sanity first**: `python -m compileall -q -f "$GITHUB_WORKSPACE"` + grep for
  `^<<<<<<< ` conflict markers before any bench setup.
- **Sharding**: matrix `container: [1..N]` +
  `bench --site test_site run-parallel-tests --app <app> --total-builds
  ${{ strategy.job-total }} --build-number ${{ matrix.container }}`
  (hrms adds `--lightmode`).
- **Coverage**: `CAPTURE_COVERAGE` env (non-PR runs only) →
  `sites/coverage.xml` → upload-artifact per shard → codecov merge job.
- **Dependent apps**: `bench get-app erpnext --resolve-deps` (+ payments etc.)
  BEFORE `get-app <yourapp> $GITHUB_WORKSPACE`.
- `paths-ignore: ['**.js','**.css','**.md','**.html']` on PR triggers.
- Debug: `mxschmitt/action-tmate@v3` gated on `debug-gha` PR label;
  always-run `cat bench_start.log` step.
- **Trigger branches must match the repo's real branches** (frappe org uses
  `develop` + `version-N`; a repo working on `version-15` needs that in the
  workflow triggers or CI never fires).

Version-compat testing (frappe/insights `compat-matrix.yml`): daily cron,
matrix of app branches × frappe branches, python/node picked per frappe
branch (`3.10`/18 for v15, `3.14`/24 for v16).

## Linter workflow (the second workflow every app should have)

Boilerplate `linter.yml` contents:
1. **ruff** (lint + format check).
2. **frappe/semgrep-rules**:
   ```yaml
   - run: git clone --depth 1 https://github.com/frappe/semgrep-rules.git frappe-semgrep-rules
   - run: |
       pip install semgrep
       semgrep ci --config ./frappe-semgrep-rules/rules --config r/python.lang.correctness
   ```
   Rule families: translate.yml (empty/variable-only/split `_()` strings,
   f-strings inside `_()`), ux.yml (untranslated msgprint/throw),
   frappe_correctness.yml (~24 rules: `frappe-manual-commit`,
   `frappe-modifying-but-not-comitting`, `frappe-breaks-multitenancy`,
   `frappe-no-functional-code`, `frappe-query-debug-statement`,
   `frappe-modifying-child-tables-while-iterating`, `frappe-cur-frm-usage`,
   `frappe-monkey-patching-not-allowed`, `frappe-realtime-pick-room`, ...),
   code_quality.yml (`unchecked-frappe-permission-call`, ...).
3. **commitlint**: `npx commitlint --from <base.sha> --to <head.sha>` with
   `@commitlint/config-conventional` (needs `fetch-depth: 200`).
4. **pip-audit**: `pip-audit --desc on .` with explicit documented
   `--ignore-vuln` pins.

## pre-commit config (boilerplate standard)

- `pre-commit-hooks` v5: trailing-whitespace (exclude json/txt/csv/md/svg),
  check-merge-conflict, check-ast, check-json/toml/yaml, debug-statements.
- `ruff-pre-commit`: three hooks in order — `ruff --select=I --fix` (imports),
  `ruff` (lint), `ruff-format`.
- `mirrors-prettier` v2.7.1 (js/vue/scss; exclude public/dist, node_modules,
  templates/includes, public/js/lib) + `mirrors-eslint` v8.44 `--quiet`.
- `no-commit-to-branch` guarding the stable branch.
- Canonical ruff config: line-length 110, target py310,
  select `["F","E","W","I","UP","B","RUF"]`, tab indent
  (`W191`/`E101` deliberately ignored), `UP030/31/32` ignored because
  `_()` translations must use positional/%-formatting, not f-strings.

## Testing conventions (v15)

- Base class: `frappe.tests.utils.FrappeTestCase` — CLASS-level DB rollback
  (tests share a transaction). The `UnitTestCase`/`IntegrationTestCase`
  split is **v16-only** (shimmed via `frappe.deprecation_dumpster`).
- Test records auto-built from `test_records.json` next to the doctype +
  `test_dependencies` module globals; `before_tests` hook for one-time setup;
  `--skip-test-records` to disable.
- CI needs `set-config allow_tests true`.
- UI tests: `bench --site test_site run-ui-tests <app> --headless`
  auto-installs Cypress ^13 stack; newer apps use Playwright instead.
- The boilerplate CI includes a "Find tests" step that FAILS the build if
  the app has zero `def test` occurrences.

## Release / versioning

- Branch discipline: `develop` (next major) → `version-N-hotfix`
  (integration) → `version-N` (stable). Direct PRs to stable are auto-closed
  by Mergify; backports via `backport version-N-hotfix` labels.
- semantic-release on push to `version-N`: version lives in
  `<app>/__init__.py` `__version__` (pyproject `dynamic = ["version"]`,
  flit); `.releaserc` sed-bumps `__init__.py`; **breaking commits
  deliberately do NOT major-bump** (`{"breaking": true, "release": false}`)
  — majors are branch-driven. Changelog = GitHub Release notes (no
  CHANGELOG.md in the org).
- A manual bump-tag-push flow (chore(release) commits) is an acceptable
  equivalent; the branch discipline is the part that matters.
- Benches consume via `bench get-app <url> --branch version-N`
  (`--resolve-deps` honors `required_apps` in hooks.py).

## Deploying to self-hosted benches

- Blessed all-in-one: **`bench update --apps <app>`** = backup → pull →
  requirements → build → migrate → restart (backup ON by default;
  `--no-backup` is "not recommended in production").
- Manual equivalent: `git pull` in apps/<app> → `bench setup requirements` →
  `bench build --app <app>` → `bench --site <site> migrate` → `bench restart`.
- `bench migrate` internals: `filelock("bench_migrate")` (concurrent migrate
  fails fast), `before_migrate` hooks → pre_model_sync patches → schema sync
  → post_model_sync patches → `after_migrate` hooks; writes
  `sites/<site>/touched_tables.json` (audit which tables changed).
- Maintenance mode: `bench --site <site> set-maintenance-mode on`; there is
  NO built-in zero-downtime migrate on classic bench — the ecosystem answer
  is staging rehearsal + short window.
- **Staging practice**: restore last night's production backup onto a staging
  bench/site, run the exact migrate there first, then production with a fresh
  verified backup.
- Docker path (frappe_docker): custom image from `apps.json` — v15-era used
  `--build-arg=APPS_JSON_BASE64=...`; **current main uses BuildKit
  `--secret=id=apps_json` + a `CACHE_BUST` build-arg** (don't use
  `--no-cache`). `overrides/compose.migrator.yaml` adds a `migrator` service
  running `bench --site all migrate` on stack start — the CI/CD-friendly
  deploy is: push image tag → `docker compose pull && up -d` → migrator.
- Health: `bench doctor` (workers/scheduler) is an ops tool, not a CI step.

## v14 → v15 deltas worth remembering

1. black/isort/flake8/pyupgrade → **ruff** ecosystem-wide.
2. CSV translations → **PO/POT gettext** (+ `generate-pot-file.yml` workflows).
3. `setup.py` → pyproject + flit, `dynamic = ["version"]`.
4. `FrappeTestCase` unchanged in v15; Unit/Integration split is v16.
5. frappe_docker apps.json: build-arg → BuildKit secret.
6. v15 floor: Python 3.10, Node 18, MariaDB 10.6 in CI.
