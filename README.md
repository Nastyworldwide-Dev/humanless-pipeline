# Humanless Pipeline

A portable, hook-driven CI/CD pipeline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — with a tool-agnostic git-hook layer so Codex, humans, and scripts hit the same quality gates. Zero daemons, zero cron jobs.

## What This Is

The humanless pipeline turns Claude Code into a fully autonomous development assistant with:

- **Pre-commit quality gates** -- lint auto-fix + typecheck gate, TDD reminders, secret detection, config protection
- **Post-commit automation** -- code review, design review, auto-deploy, cost tracking
- **Deploy gate** -- deploy-phase commands restricted to admins in `deploy-permissions.json`
- **Session management** -- context recovery, handoff persistence, dead letter queue
- **Learning system** -- captures LEARNING: lines from every subagent into a searchable SQLite database
- **Task pipeline** -- backlog, active, done, failed, blocked, archived task states
- **Cost tracking** -- per-session and per-tool token usage and cost estimation
- **Multi-tool enforcement** -- global git hooks make the gates apply to Codex and human commits, not just Claude Code

## Quick Start

```bash
git clone https://github.com/YOUR_ORG/humanless-pipeline.git ~/humanless-pipeline
cd ~/humanless-pipeline

# Install core pipeline
./install.sh

# Install with a technology pack
./install.sh --pack frappe

# Install multiple packs
./install.sh --pack frappe --pack react-ts
```

The installer will:
1. Check dependencies (and offer to install missing ones)
2. Create the directory structure under `~/.claude/`
3. Symlink hooks, agents, and skills (easy to update)
4. Generate `settings.json` and `CLAUDE.md` from templates
5. Initialize SQLite databases for cost tracking and learnings
6. Install global git hooks (`core.hooksPath`) and Codex config
7. Run verification to confirm everything works

## System Requirements

### Required
| Tool | Min Version | Purpose |
|------|-------------|---------|
| node | 18+ | Hook execution, npx-based linters |
| npm | any | Package management |
| python3 | any | Python linting, scripting |
| git | any | Version control |
| jq | any | JSON processing in hooks |
| sqlite3 | any | Cost tracking, learnings database |
| tmux | any | Teammate mode (parallel agents) |
| gh | any | GitHub CLI (PRs, issues, releases) |
| claude | any | Claude Code CLI |

### Optional
| Tool | Purpose |
|------|---------|
| bun | Fast JS runtime (monorepo deploys) |
| ruff | Python linter/formatter |
| google-chrome-stable | Browser automation (agent-browser) |
| dolt | Versioned database (advanced learnings) |

Check your system:
```bash
bash core/deps.sh

# Auto-install missing required tools
bash core/deps.sh --install
```

## Available Packs

Packs add technology-specific hooks, agents, skills, and shared references.

| Pack | What It Adds |
|------|-------------|
| `frappe` | Frappe/ERPNext hooks (branch guard, migrate check, fixture check), ERPNext skills, Frappe test patterns |
| `react-ts` | TypeScript/React hooks (Biome format, ESLint, type check), React component patterns |
| `kotlin-android` | Kotlin/Android hooks (detekt, Gradle build), Material Design skills |

Each pack has its own `install.sh` that extends the core pipeline without conflicting.

## How It Works

```
User Prompt
    |
    v
[UserPromptSubmit hooks]
    |-- task-dispatcher.sh      Route to backlog or execute
    |-- prompt-team-router.sh   Select agent team composition
    |-- requirement-interpreter.sh  Parse intent
    |
    v
[PreToolUse hooks]
    |-- validate-bash.sh        Block dangerous commands
    |-- tdd-gate.sh             Require tests for feat:/fix:
    |-- pre-commit-lint.sh      Run linters before commit
    |-- secret-detection.sh     Block secrets in Edit/Write
    |-- config-protection.sh    Guard config files
    |-- logging-gate.sh         Require logging in new functions
    |
    v
  Tool Executes (Bash, Edit, Write, etc.)
    |
    v
[PostToolUse hooks]
    |-- post-commit-review.sh   Dispatch code reviewer
    |-- post-edit-format.sh     Auto-format changed files
    |-- debug-statement-check.sh  Warn about leftover debugs
    |-- cost-tracker.sh         Log token usage
    |-- task-completion.sh      Update task state
    |
    v
[SubagentStop hooks]
    |-- learnings-capture.sh    Extract patterns from agent results
    |
    v
[SessionStart hooks]
    |-- pipeline-health.sh      Check circuit breakers, DLQ
    |-- dlq-check.sh            Report failed tasks
    |-- mcp-health-check.sh     Verify MCP connections
    |
    v
[Stop hooks]
    |-- session-persist.sh      Save state for recovery
```

Every hook is a standalone bash script. No daemon, no background process. Claude Code's hook system triggers them at the right lifecycle moment.

## Multi-Tool Enforcement (Codex, humans, scripts)

Claude Code hooks only fire inside Claude Code. To make the pipeline apply to
**every** committer, the installer also sets up a global git-hook layer:

```
git config --global core.hooksPath ~/.claude/git-hooks   # (installer does this)

~/.claude/git-hooks/          # symlink -> core/git-hooks/
  pre-commit     Runs the same lint auto-fix + typecheck gate; blocks on
                 unfixable issues. Skipped when CLAUDECODE=1 (Claude Code's
                 PreToolUse hook already ran it — no double lint).
  commit-msg     Warns when the message is not conventional-commits format.
  post-commit    Prints REVIEW REQUIRED after non-trivial commits so agents
                 that read command output (Codex) act on it.
```

All three chain to the repo-local `.git/hooks/<name>` afterwards, so husky /
pre-commit-framework / project hooks keep working. Escape hatch for CI or
emergency commits: `PIPELINE_SKIP_GIT_HOOKS=1 git commit ...`.

**Codex integration**: when the `codex` CLI is detected, the installer links
`~/.codex/AGENTS.md` to `core/codex/AGENTS.md` — the pipeline working
agreement (conventional commits, TDD, review-before-push, admin-only deploys)
that Codex loads globally — and creates a `~/.codex/config.toml` stub if none
exists. Combined with the git-hook layer, Codex sessions get both the
guidance and the enforcement.

## Rolling Out to a Team

Each developer (or each account on a shared VPS) runs:

```bash
git clone https://github.com/YOUR_ORG/humanless-pipeline.git ~/humanless-pipeline
cd ~/humanless-pipeline
./install.sh                 # plus --pack <name> for your stack
```

Everything installs per-user (`~/.claude`, `~/.codex`, global git config) —
nothing system-wide, so team members on the same machine don't interfere.
Notes:

- Hooks/agents/skills are **symlinks into the clone** — `git pull &&
  ./install.sh --update` picks up fixes for the whole toolchain at once.
- `~/.claude/config/deploy-permissions.json` is initialized with the
  installing user as admin. Edit `admin_users` to grant deploy rights.
- Existing user files are never overwritten (the installer skips non-symlink
  files and warns).
- Pack installs copy bench/project-specific hooks; pack agent variants
  intentionally replace the core symlink on that machine only.

## Directory Structure

```
~/.claude/
  settings.json          # Hook config, permissions, tool settings
  CLAUDE.md              # Global instructions for Claude
  hooks/                 # Hook scripts (symlinks to this repo)
    lib/                 # Shared hook utilities
  git-hooks/             # Global git hooks (symlink to this repo)
  agents/                # Agent definitions (.md files)
  skills/                # Skill definitions (symlinks to this repo)
    _shared/             # Shared reference files across skills
  pipeline/
    circuit/             # Circuit breaker state
    learnings/           # Learning artifacts
    logs/                # Pipeline event logs
    tasks/
      active/            # Currently executing tasks
      backlog/           # Queued tasks
      done/              # Completed tasks
      failed/            # Failed tasks (DLQ)
      blocked/           # Waiting on dependencies
      archived/          # Old completed/failed tasks
    debounce/            # Prevents duplicate hook fires
    progress/            # Task progress tracking
    scripts/             # Pipeline utility scripts
    formulas/            # Scoring/priority formulas
    cost-tracking.db     # Token usage and cost data
    learnings.db         # Pattern database
  plans/                 # Active plan documents
  config/
    project-registry.json  # Registered projects and their tooling
  cache/                 # Temporary cache
  debug/                 # Debug artifacts
  backups/               # Auto-backups before destructive ops

~/.codex/
  AGENTS.md              # Codex pipeline guidance (symlink to this repo)
  config.toml            # Codex global config (stub, user-owned after creation)
```

## Updating

```bash
cd ~/humanless-pipeline
git pull
./install.sh --update
```

Update mode:
- Re-symlinks all hooks, agents, and skills (picks up new files)
- Merges new settings into existing `settings.json` (your customizations are preserved)
- Re-runs pack installers
- Re-verifies the installation

## Uninstalling

```bash
cd ~/humanless-pipeline
./uninstall.sh
```

The uninstaller:
- Backs up `settings.json` and SQLite databases
- Removes only symlinks that point into this repo (user files are untouched)
- Removes the `pipeline/` directory
- Does NOT remove `~/.claude/` or any user data

## Verification

Run anytime to check installation health:

```bash
bash verify.sh
```

Checks:
- All hook scripts parse without syntax errors
- `settings.json` is valid JSON with no unresolved placeholders
- All symlinks resolve to real files
- All agent `.md` files exist and are non-empty
- Pipeline directory structure is complete
- SQLite databases are accessible and have correct schema

## Creating a Custom Pack

```
packs/my-pack/
  install.sh        # Installer (receives $SCRIPT_DIR as $1)
  hooks/            # Pack-specific hook scripts
  agents/           # Pack-specific agent definitions
  skills/           # Pack-specific skills
    _shared/        # Pack-specific shared references
```

Your `install.sh` should:
1. Symlink hooks into `~/.claude/hooks/`
2. Symlink agents into `~/.claude/agents/`
3. Symlink skills into `~/.claude/skills/`
4. Merge pack-specific hook entries into `settings.json` using `jq`
5. Use `cp --remove-destination` when copying over names the core pipeline
   symlinks, so you replace the link instead of writing through it

## License

MIT
