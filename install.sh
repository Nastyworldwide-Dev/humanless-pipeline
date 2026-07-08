#!/usr/bin/env bash
# install.sh — Humanless Pipeline Installer
# Usage:
#   ./install.sh                      # Install core pipeline
#   ./install.sh --pack frappe        # Install core + frappe pack
#   ./install.sh --pack frappe --pack react-ts  # Multiple packs
#   ./install.sh --update             # Update existing installation
#   ./install.sh --uninstall          # Remove pipeline
set -euo pipefail

# ─── Constants ───────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$SCRIPT_DIR/core"
PACKS_DIR="$SCRIPT_DIR/packs"
CLAUDE_DIR="$HOME/.claude"
PIPELINE_DIR="$CLAUDE_DIR/pipeline"

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ─── Helpers ─────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; }
step()    { echo -e "\n${BOLD}${CYAN}>>> $*${RESET}"; }

# ─── Parse Arguments ────────────────────────────────────────────────────────
PACKS=()
MODE="install"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pack)
            PACKS+=("$2")
            shift 2
            ;;
        --update)
            MODE="update"
            shift
            ;;
        --uninstall)
            MODE="uninstall"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--pack <name>]... [--update] [--uninstall]"
            echo ""
            echo "Options:"
            echo "  --pack <name>   Install a technology pack (repeatable)"
            echo "                  Available: frappe, react-ts, kotlin-android"
            echo "  --update        Update existing installation (re-symlink, re-run packs)"
            echo "  --uninstall     Remove the pipeline (keeps user data)"
            echo ""
            echo "Examples:"
            echo "  $0                          # Core pipeline only"
            echo "  $0 --pack frappe            # Core + Frappe/ERPNext pack"
            echo "  $0 --pack react-ts --pack kotlin-android"
            exit 0
            ;;
        *)
            error "Unknown argument: $1"
            echo "Run $0 --help for usage."
            exit 1
            ;;
    esac
done

# ─── Uninstall Mode ─────────────────────────────────────────────────────────
if [[ "$MODE" == "uninstall" ]]; then
    exec bash "$SCRIPT_DIR/uninstall.sh"
fi

# ─── Banner ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}=============================================${RESET}"
echo -e "${BOLD}${CYAN}  Humanless Pipeline Installer${RESET}"
echo -e "${BOLD}${CYAN}=============================================${RESET}"
echo -e "${DIM}  Hook-driven CI/CD for Claude Code${RESET}"
echo -e "${DIM}  Mode: ${MODE}${RESET}"
if [[ ${#PACKS[@]} -gt 0 ]]; then
    echo -e "${DIM}  Packs: ${PACKS[*]}${RESET}"
fi
echo ""

# ─── Step 1: Check Dependencies ─────────────────────────────────────────────
step "Step 1/8: Checking dependencies"
source "$CORE_DIR/deps.sh"
if ! check_all_required; then
    warn "Some required dependencies are missing."
    print_status_table
    echo ""
    read -rp "Continue anyway? Missing tools will cause hook failures. [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo ""
        info "Run 'bash $CORE_DIR/deps.sh --install' to install missing deps first."
        exit 1
    fi
else
    success "All required dependencies found."
fi

# ─── Step 2: Create Directory Structure ──────────────────────────────────────
step "Step 2/8: Creating directory structure"

DIRS=(
    "$CLAUDE_DIR"
    "$CLAUDE_DIR/agents"
    "$CLAUDE_DIR/hooks"
    "$CLAUDE_DIR/hooks/lib"
    "$CLAUDE_DIR/pipeline"
    "$CLAUDE_DIR/pipeline/circuit"
    "$CLAUDE_DIR/pipeline/learnings"
    "$CLAUDE_DIR/pipeline/logs"
    "$CLAUDE_DIR/pipeline/tasks"
    "$CLAUDE_DIR/pipeline/tasks/active"
    "$CLAUDE_DIR/pipeline/tasks/backlog"
    "$CLAUDE_DIR/pipeline/tasks/done"
    "$CLAUDE_DIR/pipeline/tasks/failed"
    "$CLAUDE_DIR/pipeline/tasks/blocked"
    "$CLAUDE_DIR/pipeline/tasks/archived"
    "$CLAUDE_DIR/pipeline/deploy-pending"
    "$CLAUDE_DIR/pipeline/debounce"
    "$CLAUDE_DIR/pipeline/progress"
    "$CLAUDE_DIR/pipeline/scripts"
    "$CLAUDE_DIR/pipeline/formulas"
    "$CLAUDE_DIR/plans"
    "$CLAUDE_DIR/plugins"
    "$CLAUDE_DIR/cache"
    "$CLAUDE_DIR/config"
    "$CLAUDE_DIR/debug"
    "$CLAUDE_DIR/backups"
    "$CLAUDE_DIR/skills"
    "$CLAUDE_DIR/skills/_shared"
)

for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
done
success "Directory structure created (${#DIRS[@]} directories)."

# ─── Step 3: Symlink Core Hooks ─────────────────────────────────────────────
step "Step 3/8: Installing core hooks"

hook_count=0
if [[ -d "$CORE_DIR/hooks" ]]; then
    # Symlink individual hook scripts (not directories)
    while IFS= read -r -d '' hook_file; do
        hook_name="$(basename "$hook_file")"
        target="$CLAUDE_DIR/hooks/$hook_name"

        # Skip if a non-symlink file exists (user customization)
        if [[ -f "$target" && ! -L "$target" ]]; then
            warn "Skipping $hook_name — user file exists (not a symlink)"
            continue
        fi

        ln -sf "$hook_file" "$target"
        hook_count=$((hook_count + 1))
    done < <(find "$CORE_DIR/hooks" -maxdepth 1 -name '*.sh' -print0 2>/dev/null)

    # Symlink hook lib files
    if [[ -d "$CORE_DIR/hooks/lib" ]]; then
        while IFS= read -r -d '' lib_file; do
            lib_name="$(basename "$lib_file")"
            ln -sf "$lib_file" "$CLAUDE_DIR/hooks/lib/$lib_name"
            hook_count=$((hook_count + 1))
        done < <(find "$CORE_DIR/hooks/lib" -maxdepth 1 -type f -print0 2>/dev/null)
    fi
fi
success "Installed $hook_count hook files."

# ─── Step 4: Symlink Core Agents ────────────────────────────────────────────
step "Step 4/8: Installing core agents"

agent_count=0
if [[ -d "$CORE_DIR/agents" ]]; then
    while IFS= read -r -d '' agent_file; do
        agent_name="$(basename "$agent_file")"
        target="$CLAUDE_DIR/agents/$agent_name"

        if [[ -f "$target" && ! -L "$target" ]]; then
            warn "Skipping $agent_name — user file exists"
            continue
        fi

        ln -sf "$agent_file" "$target"
        agent_count=$((agent_count + 1))
    done < <(find "$CORE_DIR/agents" -maxdepth 1 -type f -print0 2>/dev/null)
fi
success "Installed $agent_count agent files."

# ─── Step 5: Symlink Core Skills ────────────────────────────────────────────
step "Step 5/8: Installing core skills"

skill_count=0
if [[ -d "$CORE_DIR/skills" ]]; then
    # Symlink skill directories
    while IFS= read -r -d '' skill_dir; do
        skill_name="$(basename "$skill_dir")"
        target="$CLAUDE_DIR/skills/$skill_name"

        if [[ -d "$target" && ! -L "$target" ]]; then
            warn "Skipping skill $skill_name — user directory exists"
            continue
        fi

        ln -sf "$skill_dir" "$target"
        skill_count=$((skill_count + 1))
    done < <(find "$CORE_DIR/skills" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    # Symlink shared reference files
    if [[ -d "$CORE_DIR/skills/_shared" ]]; then
        while IFS= read -r -d '' shared_file; do
            shared_name="$(basename "$shared_file")"
            target="$CLAUDE_DIR/skills/_shared/$shared_name"
            if [[ -f "$target" && ! -L "$target" ]]; then
                warn "Skipping shared file $shared_name — user file exists"
                continue
            fi
            ln -sf "$shared_file" "$target"
            skill_count=$((skill_count + 1))
        done < <(find "$CORE_DIR/skills/_shared" -maxdepth 1 -type f -print0 2>/dev/null)
    fi
fi
success "Installed $skill_count skill items."

# ─── Step 6: Copy Pipeline Infrastructure ───────────────────────────────────
step "Step 6/8: Installing pipeline infrastructure"

infra_count=0

# Copy workflow.json if it exists
if [[ -f "$CORE_DIR/pipeline/workflow.json" ]]; then
    cp "$CORE_DIR/pipeline/workflow.json" "$PIPELINE_DIR/workflow.json"
    infra_count=$((infra_count + 1))
fi

# Symlink pipeline scripts
if [[ -d "$CORE_DIR/pipeline/scripts" ]]; then
    while IFS= read -r -d '' script_file; do
        script_name="$(basename "$script_file")"
        ln -sf "$script_file" "$PIPELINE_DIR/scripts/$script_name"
        infra_count=$((infra_count + 1))
    done < <(find "$CORE_DIR/pipeline/scripts" -maxdepth 1 -type f -print0 2>/dev/null)
fi

# Symlink pipeline formulas
if [[ -d "$CORE_DIR/pipeline/formulas" ]]; then
    while IFS= read -r -d '' formula_file; do
        formula_name="$(basename "$formula_file")"
        ln -sf "$formula_file" "$PIPELINE_DIR/formulas/$formula_name"
        infra_count=$((infra_count + 1))
    done < <(find "$CORE_DIR/pipeline/formulas" -maxdepth 1 -type f -print0 2>/dev/null)
fi

success "Installed $infra_count pipeline infrastructure files."

# Initialize deploy permissions config
DEPLOY_PERMS_FILE="$CLAUDE_DIR/config/deploy-permissions.json"
if [[ ! -f "$DEPLOY_PERMS_FILE" ]]; then
    if [[ -f "$CORE_DIR/config/deploy-permissions.json" ]]; then
        cp "$CORE_DIR/config/deploy-permissions.json" "$DEPLOY_PERMS_FILE"
        # Auto-populate current user as admin
        CURRENT_USER=$(whoami)
        if command -v jq &>/dev/null; then
            jq --arg u "$CURRENT_USER" '.admin_users = [$u]' "$DEPLOY_PERMS_FILE" > "$DEPLOY_PERMS_FILE.tmp"
            mv "$DEPLOY_PERMS_FILE.tmp" "$DEPLOY_PERMS_FILE"
        fi
        success "deploy-permissions.json initialized (admin: $CURRENT_USER)."
    else
        warn "deploy-permissions.json template not found — skipping."
    fi
else
    info "deploy-permissions.json already exists — skipping."
fi

# ─── Step 7: Generate settings.json ─────────────────────────────────────────
step "Step 7/8: Generating configuration files"

# Detect NODE_MODULES path
NODE_MODULES=""
if command -v node &>/dev/null; then
    NODE_PREFIX="$(npm config get prefix 2>/dev/null || echo "")"
    if [[ -n "$NODE_PREFIX" && -d "$NODE_PREFIX/lib/node_modules" ]]; then
        NODE_MODULES="$NODE_PREFIX/lib/node_modules"
    fi
fi

if [[ -z "$NODE_MODULES" ]]; then
    # Fallback: check common locations
    for candidate in \
        "$HOME/.nvm/versions/node/"*/lib/node_modules \
        /usr/local/lib/node_modules \
        /usr/lib/node_modules; do
        if [[ -d "$candidate" ]]; then
            NODE_MODULES="$candidate"
            break
        fi
    done
fi

if [[ -z "$NODE_MODULES" ]]; then
    warn "Could not detect node_modules path. Context-mode hooks will be disabled."
    NODE_MODULES="/usr/local/lib/node_modules"
fi

info "HOME=$HOME"
info "NODE_MODULES=$NODE_MODULES"

SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SETTINGS_TMPL="$CORE_DIR/templates/settings.json.tmpl"

if [[ -f "$SETTINGS_FILE" ]] && jq -e '.hooks' "$SETTINGS_FILE" &>/dev/null; then
    if [[ "$MODE" == "update" ]]; then
        info "settings.json exists — merging (preserving user customizations)..."
        # Backup first
        cp "$SETTINGS_FILE" "$CLAUDE_DIR/backups/settings.json.bak.$(date +%Y%m%d%H%M%S)"

        # For merge: we read the template, resolve placeholders, then use jq to merge
        # Strategy: keep existing settings, add any missing hook entries from template
        RESOLVED_TMPL=$(sed \
            -e "s|{{HOME}}|$HOME|g" \
            -e "s|{{NODE_MODULES}}|$NODE_MODULES|g" \
            "$SETTINGS_TMPL")

        # Remove _comment fields for valid JSON, then merge
        CLEAN_TMPL=$(echo "$RESOLVED_TMPL" | jq 'walk(if type == "object" then with_entries(select(.key | startswith("_comment") | not)) else . end)')

        if command -v jq &>/dev/null; then
            # Deep merge: existing * template (existing wins on conflicts)
            jq -s '.[1] * .[0]' "$SETTINGS_FILE" <(echo "$CLEAN_TMPL") > "$SETTINGS_FILE.tmp"
            mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
            success "settings.json merged successfully."
        else
            warn "jq not available — cannot merge. Backup saved."
        fi
    else
        info "settings.json already exists — skipping (use --update to merge)."
    fi
else
    # Fresh install: resolve template and write
    sed \
        -e "s|{{HOME}}|$HOME|g" \
        -e "s|{{NODE_MODULES}}|$NODE_MODULES|g" \
        "$SETTINGS_TMPL" | \
    jq 'walk(if type == "object" then with_entries(select(.key | startswith("_comment") | not)) else . end)' \
        > "$SETTINGS_FILE"
    success "settings.json generated."
fi

# Generate CLAUDE.md if it doesn't exist
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
CLAUDE_MD_TMPL="$CORE_DIR/templates/CLAUDE.md.tmpl"

if [[ ! -f "$CLAUDE_MD" ]] || [[ ! -s "$CLAUDE_MD" ]]; then
    echo ""
    info "Setting up your CLAUDE.md profile..."
    echo ""

    # Interactive prompts (or use defaults for non-interactive)
    if [[ -t 0 ]]; then
        read -rp "  Your name: " USER_NAME
        read -rp "  Your email: " USER_EMAIL
        read -rp "  Environment (e.g., 'WSL2 Ubuntu on Windows', 'macOS Sonoma'): " ENVIRONMENT
        read -rp "  Default PR target branch (e.g., 'main', 'develop'): " DEFAULT_PR_TARGET
    else
        USER_NAME="${USER_NAME:-Developer}"
        USER_EMAIL="${USER_EMAIL:-dev@example.com}"
        ENVIRONMENT="${ENVIRONMENT:-$(uname -s) $(uname -r)}"
        DEFAULT_PR_TARGET="${DEFAULT_PR_TARGET:-main}"
    fi

    USER_NAME="${USER_NAME:-Developer}"
    USER_EMAIL="${USER_EMAIL:-dev@example.com}"
    ENVIRONMENT="${ENVIRONMENT:-$(uname -s)}"
    DEFAULT_PR_TARGET="${DEFAULT_PR_TARGET:-main}"

    sed \
        -e "s|{{USER_NAME}}|$USER_NAME|g" \
        -e "s|{{USER_EMAIL}}|$USER_EMAIL|g" \
        -e "s|{{ENVIRONMENT}}|$ENVIRONMENT|g" \
        -e "s|{{DEFAULT_PR_TARGET}}|$DEFAULT_PR_TARGET|g" \
        "$CLAUDE_MD_TMPL" > "$CLAUDE_MD"

    success "CLAUDE.md generated."
else
    info "CLAUDE.md already exists — skipping."
fi

# Generate project-registry.json if it doesn't exist
REGISTRY_FILE="$CLAUDE_DIR/config/project-registry.json"
if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo '{"projects": {}}' | jq '.' > "$REGISTRY_FILE"
    success "project-registry.json initialized."
else
    info "project-registry.json already exists — skipping."
fi

# ─── Step 8: Initialize SQLite Databases ─────────────────────────────────────
step "Step 8/8: Initializing databases"

# Cost tracking database
COST_DB="$PIPELINE_DIR/cost-tracking.db"
if [[ ! -f "$COST_DB" ]]; then
    sqlite3 "$COST_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS tool_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    session_id TEXT,
    tool_name TEXT NOT NULL,
    model TEXT,
    input_tokens INTEGER DEFAULT 0,
    output_tokens INTEGER DEFAULT 0,
    estimated_cost_usd REAL DEFAULT 0.0,
    project_path TEXT,
    duration_ms INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS session_summary (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT UNIQUE NOT NULL,
    started_at TEXT NOT NULL,
    ended_at TEXT,
    total_input_tokens INTEGER DEFAULT 0,
    total_output_tokens INTEGER DEFAULT 0,
    total_cost_usd REAL DEFAULT 0.0,
    tool_calls INTEGER DEFAULT 0,
    project_path TEXT
);

CREATE INDEX IF NOT EXISTS idx_tool_usage_session ON tool_usage(session_id);
CREATE INDEX IF NOT EXISTS idx_tool_usage_timestamp ON tool_usage(timestamp);
CREATE INDEX IF NOT EXISTS idx_session_summary_started ON session_summary(started_at);
SQL
    success "cost-tracking.db initialized."
else
    info "cost-tracking.db already exists — skipping."
fi

# Learnings database
LEARN_DB="$PIPELINE_DIR/learnings.db"
if [[ ! -f "$LEARN_DB" ]]; then
    sqlite3 "$LEARN_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS learnings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    session_id TEXT,
    category TEXT NOT NULL,
    subcategory TEXT,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    source TEXT,
    project_path TEXT,
    file_path TEXT,
    confidence REAL DEFAULT 0.8,
    times_applied INTEGER DEFAULT 0,
    last_applied TEXT
);

CREATE TABLE IF NOT EXISTS learning_tags (
    learning_id INTEGER NOT NULL,
    tag TEXT NOT NULL,
    FOREIGN KEY (learning_id) REFERENCES learnings(id),
    PRIMARY KEY (learning_id, tag)
);

CREATE INDEX IF NOT EXISTS idx_learnings_category ON learnings(category);
CREATE INDEX IF NOT EXISTS idx_learnings_timestamp ON learnings(timestamp);
CREATE INDEX IF NOT EXISTS idx_learning_tags_tag ON learning_tags(tag);
SQL
    success "learnings.db initialized."
else
    info "learnings.db already exists — skipping."
fi

# ─── Install Packs ──────────────────────────────────────────────────────────
if [[ ${#PACKS[@]} -gt 0 ]]; then
    echo ""
    step "Installing technology packs"
    for pack in "${PACKS[@]}"; do
        pack_dir="$PACKS_DIR/$pack"
        pack_installer="$pack_dir/install.sh"

        if [[ ! -d "$pack_dir" ]]; then
            error "Pack '$pack' not found at $pack_dir"
            continue
        fi

        if [[ -f "$pack_installer" ]]; then
            info "Installing pack: $pack"
            bash "$pack_installer" "$SCRIPT_DIR"
            success "Pack '$pack' installed."
        else
            warn "Pack '$pack' has no install.sh — skipping."
        fi
    done
fi

# ─── Set Permissions ─────────────────────────────────────────────────────────
step "Setting permissions"
find "$CLAUDE_DIR/hooks" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
find "$PIPELINE_DIR/scripts" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
success "Executable permissions set on all hook and script files."

# ─── Run Verification ────────────────────────────────────────────────────────
echo ""
step "Running verification"
if bash "$SCRIPT_DIR/verify.sh"; then
    echo ""
    echo -e "${BOLD}${GREEN}=============================================${RESET}"
    echo -e "${BOLD}${GREEN}  Installation Complete!${RESET}"
    echo -e "${BOLD}${GREEN}=============================================${RESET}"
    echo ""
    echo -e "  Start Claude Code and the pipeline hooks will activate automatically."
    echo -e "  Run ${CYAN}claude${RESET} in any project directory to begin."
    echo ""
    if [[ ${#PACKS[@]} -gt 0 ]]; then
        echo -e "  Installed packs: ${CYAN}${PACKS[*]}${RESET}"
    fi
    echo -e "  Config: ${DIM}$CLAUDE_DIR/settings.json${RESET}"
    echo -e "  Hooks:  ${DIM}$CLAUDE_DIR/hooks/${RESET}"
    echo -e "  Data:   ${DIM}$PIPELINE_DIR/${RESET}"
    echo ""
else
    echo ""
    warn "Verification reported issues. The pipeline may still work but check the output above."
fi
