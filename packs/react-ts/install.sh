#!/bin/bash
set -euo pipefail

# ─── React/TypeScript Pack Installer ────────────────────────────────
# Installs hooks, agents, and CLAUDE.md config for a React/TS project.
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

React/TypeScript humanless pipeline pack installer.

Options:
  --project-path PATH   Path to React/TS project (default: current directory)
  --pkg-manager NAME    Package manager: npm, yarn, bun, pnpm (auto-detected)
  --uninstall           Remove all installed components
  --dry-run             Show what would be done without making changes
  -h, --help            Show this help

Examples:
  $SCRIPT_NAME --project-path ~/my-react-app
  $SCRIPT_NAME --pkg-manager bun
  $SCRIPT_NAME --uninstall --project-path ~/my-react-app
EOF
  exit 0
}

# ─── Parse arguments ────────────────────────────────────────────────
PROJECT_PATH="$(pwd)"
PKG_MANAGER=""
UNINSTALL=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-path) PROJECT_PATH="$2"; shift 2 ;;
    --pkg-manager) PKG_MANAGER="$2"; shift 2 ;;
    --uninstall) UNINSTALL=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) err "Unknown option: $1"; usage ;;
  esac
done

PROJECT_PATH="${PROJECT_PATH/#\~/$HOME}"

# ─── Validate project path ─────────────────────────────────────────
if [ "$UNINSTALL" = false ]; then
  if [ ! -f "$PROJECT_PATH/package.json" ]; then
    err "No package.json found at: $PROJECT_PATH"
    exit 1
  fi
fi

# ─── Auto-detect package manager ───────────────────────────────────
if [ -z "$PKG_MANAGER" ] && [ -d "$PROJECT_PATH" ]; then
  if [ -f "$PROJECT_PATH/bun.lock" ] || [ -f "$PROJECT_PATH/bun.lockb" ]; then
    PKG_MANAGER="bun"
  elif [ -f "$PROJECT_PATH/pnpm-lock.yaml" ]; then
    PKG_MANAGER="pnpm"
  elif [ -f "$PROJECT_PATH/yarn.lock" ]; then
    PKG_MANAGER="yarn"
  else
    PKG_MANAGER="npm"
  fi
fi

# Detect project type
PROJECT_TYPE="react-ts"
if [ -f "$PROJECT_PATH/turbo.json" ] || [ -f "$PROJECT_PATH/turbo.jsonc" ]; then
  PROJECT_TYPE="monorepo"
fi
if [ -f "$PROJECT_PATH/electron-builder.yml" ] || [ -f "$PROJECT_PATH/electron-builder.json5" ]; then
  PROJECT_TYPE="electron"
fi

# ─── Uninstall ──────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
  info "Uninstalling React/TS pack from $PROJECT_PATH..."

  for hook in pre-commit-typecheck.sh pre-commit-biome.sh post-edit-prettier.sh; do
    rm -f "$PROJECT_PATH/.claude/hooks/$hook" && ok "Removed hook: $hook"
  done

  for agent in tdd-runner-js.md react-reviewer.md; do
    rm -f "$HOME/.claude/agents/$agent" && ok "Removed agent: $agent"
  done

  REGISTRY="$HOME/.claude/project-registry.json"
  if [ -f "$REGISTRY" ] && command -v jq &>/dev/null; then
    jq --arg path "$PROJECT_PATH" 'del(.projects[$path])' "$REGISTRY" > "${REGISTRY}.tmp" \
      && mv "${REGISTRY}.tmp" "$REGISTRY"
    ok "Removed from project registry"
  fi

  ok "React/TS pack uninstalled. CLAUDE.md.append content must be removed manually."
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
info "Installing React/TS hooks to $PROJECT_PATH/.claude/hooks/..."
run mkdir -p "$PROJECT_PATH/.claude/hooks"

for hook_file in "$PACK_DIR"/hooks/*.sh; do
  [ -f "$hook_file" ] || continue
  hook_name=$(basename "$hook_file")
  if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would copy $hook_name"
  else
    cp --remove-destination "$hook_file" "$PROJECT_PATH/.claude/hooks/$hook_name"
    chmod +x "$PROJECT_PATH/.claude/hooks/$hook_name"
    ok "Installed hook: $hook_name"
  fi
done

# ─── Install agents ────────────────────────────────────────────────
info "Installing React/TS agents to ~/.claude/agents/..."
run mkdir -p "$HOME/.claude/agents"

for agent_file in "$PACK_DIR"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  agent_name=$(basename "$agent_file")
  if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would copy $agent_name"
  else
    cp --remove-destination "$agent_file" "$HOME/.claude/agents/$agent_name"
    ok "Installed agent: $agent_name"
  fi
done

# ─── Append to CLAUDE.md ───────────────────────────────────────────
GLOBAL_CLAUDE_MD="$HOME/.claude/CLAUDE.md"
APPEND_FILE="$PACK_DIR/CLAUDE.md.append"
MARKER="## React/TypeScript Development Conventions"

if [ -f "$APPEND_FILE" ]; then
  if [ -f "$GLOBAL_CLAUDE_MD" ] && grep -qF "$MARKER" "$GLOBAL_CLAUDE_MD"; then
    warn "React/TS CLAUDE.md sections already present — skipping append"
  else
    if [ "$DRY_RUN" = true ]; then
      info "[DRY RUN] Would append to $GLOBAL_CLAUDE_MD"
    else
      run mkdir -p "$(dirname "$GLOBAL_CLAUDE_MD")"
      cat "$APPEND_FILE" >> "$GLOBAL_CLAUDE_MD"
      ok "Appended React/TS sections to $GLOBAL_CLAUDE_MD"
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
    jq --arg path "$PROJECT_PATH" \
       --arg type "$PROJECT_TYPE" \
       --arg pkg "$PKG_MANAGER" \
       '.projects[$path] = {
          "type": $type,
          "package_manager": $pkg,
          "installed_pack": "react-ts",
          "installed_at": (now | todate)
        }' "$REGISTRY" > "${REGISTRY}.tmp" && mv "${REGISTRY}.tmp" "$REGISTRY"
    ok "Registered $PROJECT_PATH in project registry"
  else
    warn "jq not found — skipping project registry update"
  fi
fi

# ─── Create project CLAUDE.md ──────────────────────────────────────
PROJECT_CLAUDE_MD="$PROJECT_PATH/.claude/CLAUDE.md"

if [ "$DRY_RUN" = true ]; then
  info "[DRY RUN] Would create $PROJECT_CLAUDE_MD"
else
  run mkdir -p "$PROJECT_PATH/.claude"
  if [ ! -f "$PROJECT_CLAUDE_MD" ]; then
    cat > "$PROJECT_CLAUDE_MD" << CLAUDEEOF
# React/TypeScript Project Configuration

## Environment
- Project path: $PROJECT_PATH
- Package manager: $PKG_MANAGER
- Project type: $PROJECT_TYPE

## Pipeline Hooks (auto-installed)
- pre-commit-typecheck.sh — runs tsc --noEmit before commits
- pre-commit-biome.sh — runs biome format/lint check
- post-edit-prettier.sh — auto-formats after edits

## Agents
- tdd-runner-js (haiku) — runs jest/vitest tests
- react-reviewer (haiku) — React/TS code review

## Commands
- Type check: \`npx tsc --noEmit\`
- Lint: \`npx @biomejs/biome check .\`
- Format: \`npx @biomejs/biome format --write .\`
- Test: \`npx vitest run\` or \`npx jest\`
CLAUDEEOF
    ok "Created $PROJECT_CLAUDE_MD"
  else
    warn "$PROJECT_CLAUDE_MD already exists — skipping"
  fi
fi

# ─── Summary ────────────────────────────────────────────────────────
echo ""
info "═══════════════════════════════════════════════"
info " React/TypeScript Pack Installation Complete"
info "═══════════════════════════════════════════════"
info " Project:    $PROJECT_PATH"
info " Type:       $PROJECT_TYPE"
info " Pkg mgr:    $PKG_MANAGER"
info " Hooks:      $(ls "$PROJECT_PATH/.claude/hooks/"*.sh 2>/dev/null | wc -l) installed"
info " Agents:     tdd-runner-js, react-reviewer"
info "═══════════════════════════════════════════════"
echo ""
