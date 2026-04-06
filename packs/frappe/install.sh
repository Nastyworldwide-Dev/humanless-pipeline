#!/bin/bash
set -euo pipefail

# ─── Frappe/ERPNext Pack Installer ──────────────────────────────────
# Installs hooks, agents, skills, and CLAUDE.md config for a Frappe bench.
# Idempotent — safe to run multiple times.

PACK_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Frappe/ERPNext humanless pipeline pack installer.

Options:
  --bench-path PATH     Path to frappe-bench (default: ~/frappe-bench)
  --site NAME           Site name (default: erplocal.dev)
  --apps NAMES          Comma-separated custom app names (auto-detected if omitted)
  --pr-target BRANCH    Default PR target branch (default: development)
  --uninstall           Remove all installed components
  --dry-run             Show what would be done without making changes
  -h, --help            Show this help

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME --bench-path ~/my-bench --site mysite.local --apps myapp,otherapp
  $SCRIPT_NAME --uninstall
EOF
  exit 0
}

# ─── Parse arguments ────────────────────────────────────────────────
BENCH_PATH="$HOME/frappe-bench"
SITE_NAME="erplocal.dev"
CUSTOM_APPS=""
PR_TARGET="development"
UNINSTALL=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bench-path) BENCH_PATH="$2"; shift 2 ;;
    --site) SITE_NAME="$2"; shift 2 ;;
    --apps) CUSTOM_APPS="$2"; shift 2 ;;
    --pr-target) PR_TARGET="$2"; shift 2 ;;
    --uninstall) UNINSTALL=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) err "Unknown option: $1"; usage ;;
  esac
done

# Expand ~ in bench path
BENCH_PATH="${BENCH_PATH/#\~/$HOME}"

# ─── Validate bench path ───────────────────────────────────────────
if [ "$UNINSTALL" = false ]; then
  if [ ! -d "$BENCH_PATH/apps" ] || [ ! -f "$BENCH_PATH/sites/common_site_config.json" ]; then
    err "Not a valid frappe-bench at: $BENCH_PATH"
    err "Expected apps/ directory and sites/common_site_config.json"
    exit 1
  fi
fi

# ─── Auto-detect custom apps ───────────────────────────────────────
FRAMEWORK_APPS="frappe erpnext hrms insights payments india_compliance lms"

if [ -z "$CUSTOM_APPS" ] && [ -d "$BENCH_PATH/apps" ]; then
  for app_dir in "$BENCH_PATH/apps"/*/; do
    [ -d "$app_dir" ] || continue
    app_name=$(basename "$app_dir")
    is_framework=false
    for fw in $FRAMEWORK_APPS; do
      [ "$app_name" = "$fw" ] && is_framework=true && break
    done
    if [ "$is_framework" = false ] && [ -f "$app_dir/$app_name/hooks.py" ]; then
      CUSTOM_APPS="${CUSTOM_APPS:+$CUSTOM_APPS,}$app_name"
    fi
  done
fi

CUSTOM_APPS_SPACE=$(echo "$CUSTOM_APPS" | tr ',' ' ')

# ─── Uninstall ──────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
  info "Uninstalling Frappe pack from $BENCH_PATH..."

  # Remove hooks
  for hook in branch-guard.sh pre-push-check.sh pre-migrate-check.sh \
              post-migrate-fixture-check.sh app-team-router.sh post-agent-result.sh \
              nsty-team-result.sh auto-stub-tests.sh post-edit-tdd-runner.sh stop-reminder.sh; do
    rm -f "$BENCH_PATH/.claude/hooks/$hook" && ok "Removed hook: $hook"
  done

  # Remove agents
  for agent in frappe-reviewer.md tdd-runner.md migration-checker.md; do
    rm -f "$HOME/.claude/agents/$agent" && ok "Removed agent: $agent"
  done

  # Remove shared skills
  rm -rf "$HOME/.agents/skills/_shared/frappe-doc-lifecycle.md" \
         "$HOME/.agents/skills/_shared/frappe-db-patterns.md" \
         "$HOME/.agents/skills/_shared/frappe-api-rules.md" \
         "$HOME/.agents/skills/_shared/frappe-error-patterns.md"
  ok "Removed shared skill references"

  # Remove from project registry
  REGISTRY="$HOME/.claude/project-registry.json"
  if [ -f "$REGISTRY" ] && command -v jq &>/dev/null; then
    jq --arg path "$BENCH_PATH" 'del(.projects[$path])' "$REGISTRY" > "${REGISTRY}.tmp" \
      && mv "${REGISTRY}.tmp" "$REGISTRY"
    ok "Removed from project registry"
  fi

  ok "Frappe pack uninstalled. CLAUDE.md.append content must be removed manually."
  exit 0
fi

# ─── Dry run prefix ────────────────────────────────────────────────
run() {
  if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] $*"
  else
    "$@"
  fi
}

# ─── Install hooks ─────────────────────────────────────────────────
info "Installing Frappe hooks to $BENCH_PATH/.claude/hooks/..."
run mkdir -p "$BENCH_PATH/.claude/hooks"

for hook_file in "$PACK_DIR"/hooks/*.sh; do
  [ -f "$hook_file" ] || continue
  hook_name=$(basename "$hook_file")
  if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would copy $hook_name"
  else
    cp "$hook_file" "$BENCH_PATH/.claude/hooks/$hook_name"
    chmod +x "$BENCH_PATH/.claude/hooks/$hook_name"
    ok "Installed hook: $hook_name"
  fi
done

# ─── Install agents ────────────────────────────────────────────────
info "Installing Frappe agents to ~/.claude/agents/..."
run mkdir -p "$HOME/.claude/agents"

for agent_file in "$PACK_DIR"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  agent_name=$(basename "$agent_file")
  if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would copy $agent_name"
  else
    cp "$agent_file" "$HOME/.claude/agents/$agent_name"
    ok "Installed agent: $agent_name"
  fi
done

# ─── Install shared skill references ───────────────────────────────
info "Installing shared skill references to ~/.agents/skills/_shared/..."
run mkdir -p "$HOME/.agents/skills/_shared"

for ref_file in "$PACK_DIR"/skills/_shared/*.md; do
  [ -f "$ref_file" ] || continue
  ref_name=$(basename "$ref_file")
  if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would copy $ref_name"
  else
    cp "$ref_file" "$HOME/.agents/skills/_shared/$ref_name"
    ok "Installed reference: $ref_name"
  fi
done

# ─── Symlink erpnext-* skills (if pack has them) ───────────────────
if [ -d "$PACK_DIR/skills/erpnext" ]; then
  info "Symlinking ERPNext skills..."
  run mkdir -p "$HOME/.agents/skills"
  for skill_dir in "$PACK_DIR"/skills/erpnext/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    target="$HOME/.agents/skills/$skill_name"
    if [ "$DRY_RUN" = true ]; then
      info "[DRY RUN] Would symlink $skill_name"
    else
      ln -sfn "$skill_dir" "$target"
      ok "Symlinked skill: $skill_name"
    fi
  done
fi

# ─── Append to CLAUDE.md ───────────────────────────────────────────
GLOBAL_CLAUDE_MD="$HOME/.claude/CLAUDE.md"
APPEND_FILE="$PACK_DIR/CLAUDE.md.append"
MARKER="## Frappe/ERPNext Development Conventions"

if [ -f "$APPEND_FILE" ]; then
  if [ -f "$GLOBAL_CLAUDE_MD" ] && grep -qF "$MARKER" "$GLOBAL_CLAUDE_MD"; then
    warn "Frappe CLAUDE.md sections already present — skipping append"
  else
    if [ "$DRY_RUN" = true ]; then
      info "[DRY RUN] Would append to $GLOBAL_CLAUDE_MD"
    else
      run mkdir -p "$(dirname "$GLOBAL_CLAUDE_MD")"
      cat "$APPEND_FILE" >> "$GLOBAL_CLAUDE_MD"
      ok "Appended Frappe sections to $GLOBAL_CLAUDE_MD"
    fi
  fi
fi

# ─── Register in project-registry.json ──────────────────────────────
REGISTRY="$HOME/.claude/project-registry.json"

if [ "$DRY_RUN" = true ]; then
  info "[DRY RUN] Would register in $REGISTRY"
else
  run mkdir -p "$(dirname "$REGISTRY")"

  if [ ! -f "$REGISTRY" ]; then
    echo '{"projects":{}}' > "$REGISTRY"
  fi

  if command -v jq &>/dev/null; then
    APPS_JSON=$(echo "$CUSTOM_APPS_SPACE" | tr ' ' '\n' | jq -R . | jq -s .)
    jq --arg path "$BENCH_PATH" \
       --arg type "frappe-bench" \
       --arg site "$SITE_NAME" \
       --argjson apps "$APPS_JSON" \
       --arg pr_target "$PR_TARGET" \
       '.projects[$path] = {
          "type": $type,
          "site": $site,
          "custom_apps": $apps,
          "pr_target": $pr_target,
          "installed_pack": "frappe",
          "installed_at": (now | todate)
        }' "$REGISTRY" > "${REGISTRY}.tmp" && mv "${REGISTRY}.tmp" "$REGISTRY"
    ok "Registered $BENCH_PATH in project registry"
  else
    warn "jq not found — skipping project registry update"
  fi
fi

# ─── Create project CLAUDE.md ──────────────────────────────────────
PROJECT_CLAUDE_MD="$BENCH_PATH/.claude/CLAUDE.md"

if [ "$DRY_RUN" = true ]; then
  info "[DRY RUN] Would create $PROJECT_CLAUDE_MD"
else
  run mkdir -p "$BENCH_PATH/.claude"
  cat > "$PROJECT_CLAUDE_MD" << CLAUDEEOF
# Frappe Bench — Project Configuration

## Environment
- Bench path: $BENCH_PATH
- Site: $SITE_NAME
- Custom apps: $CUSTOM_APPS_SPACE
- Framework: Frappe/ERPNext

## Pipeline Hooks (auto-installed)
- branch-guard.sh — blocks feat:/fix: on main/master
- pre-push-check.sh — detects debug artifacts
- pre-migrate-check.sh — suggests migration-checker
- post-migrate-fixture-check.sh — detects fixture drift
- app-team-router.sh — routes review to team-specific reviewers
- post-agent-result.sh — pipeline chain enforcement + circuit breaker
- auto-stub-tests.sh — creates failing test stubs for new files
- post-edit-tdd-runner.sh — triggers tdd-runner after implementation edits
- stop-reminder.sh — uncommitted changes + lint reminder

## Agents
- frappe-reviewer (haiku) — code review for Frappe patterns
- tdd-runner (haiku) — multi-layer test runner
- migration-checker (sonnet) — migration safety analysis

## Commands
- Run tests: \`bench --site $SITE_NAME run-tests --app {app}\`
- Run single: \`bench --site $SITE_NAME run-tests --doctype {DocType}\`
- Migrate: \`bench --site $SITE_NAME migrate\`
- Backup: \`bench --site $SITE_NAME backup\`

## PR Convention
- Default target branch: $PR_TARGET
- Never target main/master without explicit instruction

## MANDATORY: Plan Template
Every implementation plan must include:
1. Requirements analysis
2. TDD plan (red-green-refactor)
3. Implementation steps
4. Pipeline Summary: auto-commit -> auto-review -> auto-deploy
CLAUDEEOF
  ok "Created $PROJECT_CLAUDE_MD"
fi

# ─── Create .mcp.json ──────────────────────────────────────────────
MCP_JSON="$BENCH_PATH/.mcp.json"

if [ "$DRY_RUN" = true ]; then
  info "[DRY RUN] Would create $MCP_JSON"
else
  cat > "$MCP_JSON" << 'MCPEOF'
{
  "mcpServers": {
    "github": {
      "command": "gh",
      "args": ["copilot", "mcp"],
      "description": "GitHub MCP server via gh CLI"
    }
  }
}
MCPEOF
  ok "Created $MCP_JSON"
fi

# ─── Create pipeline directories ───────────────────────────────────
if [ "$DRY_RUN" = false ]; then
  mkdir -p "$HOME/.claude/pipeline/circuit"
  mkdir -p "$HOME/.claude/pipeline/debounce"
  mkdir -p "$HOME/.claude/pipeline/tasks/failed"
  mkdir -p "$HOME/.claude/pipeline/logs"
  ok "Created pipeline directories"
fi

# ─── Summary ────────────────────────────────────────────────────────
echo ""
info "═══════════════════════════════════════════════"
info " Frappe/ERPNext Pack Installation Complete"
info "═══════════════════════════════════════════════"
info " Bench:      $BENCH_PATH"
info " Site:       $SITE_NAME"
info " Apps:       ${CUSTOM_APPS_SPACE:-none detected}"
info " PR target:  $PR_TARGET"
info " Hooks:      $(ls "$BENCH_PATH/.claude/hooks/"*.sh 2>/dev/null | wc -l) installed"
info " Agents:     $(ls "$HOME/.claude/agents/"*.md 2>/dev/null | wc -l) available"
info "═══════════════════════════════════════════════"
echo ""
