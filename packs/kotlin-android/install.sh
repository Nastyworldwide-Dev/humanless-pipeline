#!/bin/bash
set -euo pipefail

# ─── Kotlin/Android Pack Installer ──────────────────────────────────
# Installs hooks, agents, and CLAUDE.md config for a Kotlin/Android project.
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

Kotlin/Android humanless pipeline pack installer.

Options:
  --project-path PATH   Path to Android project (default: current directory)
  --uninstall           Remove all installed components
  --dry-run             Show what would be done without making changes
  -h, --help            Show this help

Examples:
  $SCRIPT_NAME --project-path ~/my-android-app
  $SCRIPT_NAME --uninstall --project-path ~/my-android-app
EOF
  exit 0
}

# ─── Parse arguments ────────────────────────────────────────────────
PROJECT_PATH="$(pwd)"
UNINSTALL=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-path) PROJECT_PATH="$2"; shift 2 ;;
    --uninstall) UNINSTALL=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) err "Unknown option: $1"; usage ;;
  esac
done

PROJECT_PATH="${PROJECT_PATH/#\~/$HOME}"

# ─── Validate project path ─────────────────────────────────────────
if [ "$UNINSTALL" = false ]; then
  if [ ! -f "$PROJECT_PATH/gradlew" ]; then
    err "No gradlew found at: $PROJECT_PATH"
    err "Expected an Android/Kotlin project with Gradle wrapper"
    exit 1
  fi
fi

# Detect build tool variant
BUILD_FILE="build.gradle.kts"
if [ ! -f "$PROJECT_PATH/$BUILD_FILE" ]; then
  BUILD_FILE="build.gradle"
fi

# ─── Uninstall ──────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
  info "Uninstalling Kotlin/Android pack from $PROJECT_PATH..."

  for hook in pre-commit-detekt.sh pre-commit-ktlint.sh post-build-check.sh; do
    rm -f "$PROJECT_PATH/.claude/hooks/$hook" && ok "Removed hook: $hook"
  done

  for agent in tdd-runner-kotlin.md android-reviewer.md; do
    rm -f "$HOME/.claude/agents/$agent" && ok "Removed agent: $agent"
  done

  REGISTRY="$HOME/.claude/project-registry.json"
  if [ -f "$REGISTRY" ] && command -v jq &>/dev/null; then
    jq --arg path "$PROJECT_PATH" 'del(.projects[$path])' "$REGISTRY" > "${REGISTRY}.tmp" \
      && mv "${REGISTRY}.tmp" "$REGISTRY"
    ok "Removed from project registry"
  fi

  ok "Kotlin/Android pack uninstalled. CLAUDE.md.append content must be removed manually."
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
info "Installing Kotlin/Android hooks to $PROJECT_PATH/.claude/hooks/..."
run mkdir -p "$PROJECT_PATH/.claude/hooks"

for hook_file in "$PACK_DIR"/hooks/*.sh; do
  [ -f "$hook_file" ] || continue
  hook_name=$(basename "$hook_file")
  if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would copy $hook_name"
  else
    cp "$hook_file" "$PROJECT_PATH/.claude/hooks/$hook_name"
    chmod +x "$PROJECT_PATH/.claude/hooks/$hook_name"
    ok "Installed hook: $hook_name"
  fi
done

# ─── Install agents ────────────────────────────────────────────────
info "Installing Kotlin/Android agents to ~/.claude/agents/..."
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

# ─── Append to CLAUDE.md ───────────────────────────────────────────
GLOBAL_CLAUDE_MD="$HOME/.claude/CLAUDE.md"
APPEND_FILE="$PACK_DIR/CLAUDE.md.append"
MARKER="## Kotlin/Android Development Conventions"

if [ -f "$APPEND_FILE" ]; then
  if [ -f "$GLOBAL_CLAUDE_MD" ] && grep -qF "$MARKER" "$GLOBAL_CLAUDE_MD"; then
    warn "Kotlin/Android CLAUDE.md sections already present — skipping append"
  else
    if [ "$DRY_RUN" = true ]; then
      info "[DRY RUN] Would append to $GLOBAL_CLAUDE_MD"
    else
      run mkdir -p "$(dirname "$GLOBAL_CLAUDE_MD")"
      cat "$APPEND_FILE" >> "$GLOBAL_CLAUDE_MD"
      ok "Appended Kotlin/Android sections to $GLOBAL_CLAUDE_MD"
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
       --arg build "$BUILD_FILE" \
       '.projects[$path] = {
          "type": "android",
          "build_file": $build,
          "installed_pack": "kotlin-android",
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
# Kotlin/Android Project Configuration

## Environment
- Project path: $PROJECT_PATH
- Build file: $BUILD_FILE
- Build tool: Gradle

## Pipeline Hooks (auto-installed)
- pre-commit-detekt.sh — runs detekt static analysis before commits
- pre-commit-ktlint.sh — Kotlin formatting check
- post-build-check.sh — suggests build verification after changes

## Agents
- tdd-runner-kotlin (haiku) — runs JUnit/Espresso tests via gradle
- android-reviewer (haiku) — Kotlin/Android code review

## Commands
- Build debug: \`./gradlew assembleDebug\`
- Unit tests: \`./gradlew testDebugUnitTest\`
- Instrumented tests: \`./gradlew connectedDebugAndroidTest\`
- Lint: \`./gradlew detekt\`
- Format: \`./gradlew ktlintFormat\`
CLAUDEEOF
    ok "Created $PROJECT_CLAUDE_MD"
  else
    warn "$PROJECT_CLAUDE_MD already exists — skipping"
  fi
fi

# ─── Create pipeline directories ───────────────────────────────────
if [ "$DRY_RUN" = false ]; then
  mkdir -p "$HOME/.claude/pipeline/debounce"
  ok "Created pipeline directories"
fi

# ─── Summary ────────────────────────────────────────────────────────
echo ""
info "═══════════════════════════════════════════════"
info " Kotlin/Android Pack Installation Complete"
info "═══════════════════════════════════════════════"
info " Project:    $PROJECT_PATH"
info " Build:      $BUILD_FILE"
info " Hooks:      $(ls "$PROJECT_PATH/.claude/hooks/"*.sh 2>/dev/null | wc -l) installed"
info " Agents:     tdd-runner-kotlin, android-reviewer"
info "═══════════════════════════════════════════════"
echo ""
