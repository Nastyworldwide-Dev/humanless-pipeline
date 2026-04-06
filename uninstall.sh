#!/usr/bin/env bash
# uninstall.sh — Remove the humanless pipeline
# Only removes symlinks and pipeline-managed files. Never touches user data.
set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
AGENTS_DIR="$HOME/.agents"
PIPELINE_DIR="$CLAUDE_DIR/pipeline"

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
removed() { echo -e "${RED}[DEL]${RESET}   $*"; }
kept()    { echo -e "${GREEN}[KEPT]${RESET}  $*"; }

echo ""
echo -e "${BOLD}${RED}=============================================${RESET}"
echo -e "${BOLD}${RED}  Humanless Pipeline — Uninstall${RESET}"
echo -e "${BOLD}${RED}=============================================${RESET}"
echo ""
echo -e "This will remove:"
echo -e "  - Pipeline hooks (symlinks only, not user-created hooks)"
echo -e "  - Pipeline agents (symlinks only)"
echo -e "  - Pipeline skills (symlinks only)"
echo -e "  - Pipeline directory (~/.claude/pipeline/)"
echo ""
echo -e "${BOLD}This will NOT remove:${RESET}"
echo -e "  - ~/.claude/ directory itself"
echo -e "  - settings.json (a backup is saved)"
echo -e "  - CLAUDE.md"
echo -e "  - User-created hooks, agents, or skills"
echo -e "  - Plans, cache, config, or debug data"
echo ""

read -rp "Proceed with uninstall? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy] ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
removed_count=0
kept_count=0

# ─── 1. Backup settings.json ────────────────────────────────────────────────
info "Backing up settings.json..."
if [[ -f "$CLAUDE_DIR/settings.json" ]]; then
    backup_path="$CLAUDE_DIR/backups/settings.json.pre-uninstall.$(date +%Y%m%d%H%M%S)"
    mkdir -p "$CLAUDE_DIR/backups"
    cp "$CLAUDE_DIR/settings.json" "$backup_path"
    kept "settings.json backed up to $backup_path"
fi

# ─── 2. Remove pipeline hooks (symlinks pointing into this repo only) ────────
info "Removing pipeline hooks..."
if [[ -d "$CLAUDE_DIR/hooks" ]]; then
    while IFS= read -r -d '' hook; do
        if [[ -L "$hook" ]]; then
            target="$(readlink "$hook")"
            # Only remove if symlink points into this repo
            if [[ "$target" == "$SCRIPT_DIR"* ]]; then
                rm "$hook"
                removed "hooks/$(basename "$hook")"
                removed_count=$((removed_count + 1))
            else
                kept "hooks/$(basename "$hook") (points outside this repo)"
                kept_count=$((kept_count + 1))
            fi
        else
            kept "hooks/$(basename "$hook") (not a symlink — user file)"
            kept_count=$((kept_count + 1))
        fi
    done < <(find "$CLAUDE_DIR/hooks" -maxdepth 1 -name '*.sh' -print0 2>/dev/null)

    # Clean lib/ symlinks
    if [[ -d "$CLAUDE_DIR/hooks/lib" ]]; then
        while IFS= read -r -d '' lib_file; do
            if [[ -L "$lib_file" ]]; then
                target="$(readlink "$lib_file")"
                if [[ "$target" == "$SCRIPT_DIR"* ]]; then
                    rm "$lib_file"
                    removed "hooks/lib/$(basename "$lib_file")"
                    removed_count=$((removed_count + 1))
                fi
            fi
        done < <(find "$CLAUDE_DIR/hooks/lib" -maxdepth 1 -print0 2>/dev/null)
    fi
fi

# ─── 3. Remove pipeline agents (symlinks only) ──────────────────────────────
info "Removing pipeline agents..."
if [[ -d "$CLAUDE_DIR/agents" ]]; then
    while IFS= read -r -d '' agent; do
        if [[ -L "$agent" ]]; then
            target="$(readlink "$agent")"
            if [[ "$target" == "$SCRIPT_DIR"* ]]; then
                rm "$agent"
                removed "agents/$(basename "$agent")"
                removed_count=$((removed_count + 1))
            else
                kept "agents/$(basename "$agent") (points outside this repo)"
                kept_count=$((kept_count + 1))
            fi
        else
            kept "agents/$(basename "$agent") (not a symlink)"
            kept_count=$((kept_count + 1))
        fi
    done < <(find "$CLAUDE_DIR/agents" -maxdepth 1 -type f -o -type l -print0 2>/dev/null)
fi

# ─── 4. Remove pipeline skills (symlinks only) ──────────────────────────────
info "Removing pipeline skills..."
if [[ -d "$AGENTS_DIR/skills" ]]; then
    while IFS= read -r -d '' skill; do
        if [[ -L "$skill" ]]; then
            target="$(readlink "$skill")"
            if [[ "$target" == "$SCRIPT_DIR"* ]]; then
                rm "$skill"
                removed "skills/$(basename "$skill")"
                removed_count=$((removed_count + 1))
            else
                kept "skills/$(basename "$skill") (points outside this repo)"
                kept_count=$((kept_count + 1))
            fi
        fi
    done < <(find "$AGENTS_DIR/skills" -maxdepth 1 -print0 2>/dev/null)

    # Clean _shared/ symlinks
    if [[ -d "$AGENTS_DIR/skills/_shared" ]]; then
        while IFS= read -r -d '' shared; do
            if [[ -L "$shared" ]]; then
                target="$(readlink "$shared")"
                if [[ "$target" == "$SCRIPT_DIR"* ]]; then
                    rm "$shared"
                    removed "skills/_shared/$(basename "$shared")"
                    removed_count=$((removed_count + 1))
                fi
            fi
        done < <(find "$AGENTS_DIR/skills/_shared" -maxdepth 1 -print0 2>/dev/null)
    fi
fi

# ─── 5. Remove pipeline/ directory ──────────────────────────────────────────
info "Removing pipeline directory..."
if [[ -d "$PIPELINE_DIR" ]]; then
    # Backup databases before removal
    for db in "$PIPELINE_DIR"/*.db; do
        if [[ -f "$db" ]]; then
            db_backup="$CLAUDE_DIR/backups/$(basename "$db").pre-uninstall.$(date +%Y%m%d%H%M%S)"
            cp "$db" "$db_backup"
            kept "$(basename "$db") backed up to backups/"
        fi
    done

    rm -rf "$PIPELINE_DIR"
    removed "pipeline/ directory"
    removed_count=$((removed_count + 1))
else
    info "pipeline/ directory not found — already removed."
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}────────────────────────────────────────${RESET}"
echo -e "  ${RED}Removed: $removed_count${RESET}  ${GREEN}Kept: $kept_count${RESET}"
echo -e "${BOLD}────────────────────────────────────────${RESET}"
echo ""
echo -e "${GREEN}Uninstall complete.${RESET}"
echo -e "${DIM}Backups saved in $CLAUDE_DIR/backups/${RESET}"
echo -e "${DIM}To fully remove all Claude Code config: rm -rf $CLAUDE_DIR${RESET}"
echo ""
