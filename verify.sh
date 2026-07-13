#!/usr/bin/env bash
# verify.sh — Verify the humanless pipeline installation
# Checks hooks, config, symlinks, agents, pipeline dirs, and databases.
set -uo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

CLAUDE_DIR="$HOME/.claude"
AGENTS_DIR="$HOME/.agents"
PIPELINE_DIR="$CLAUDE_DIR/pipeline"

pass_count=0
fail_count=0
warn_count=0

pass()  { echo -e "  ${GREEN}PASS${RESET}  $*"; pass_count=$((pass_count + 1)); }
fail()  { echo -e "  ${RED}FAIL${RESET}  $*"; fail_count=$((fail_count + 1)); }
skip()  { echo -e "  ${YELLOW}SKIP${RESET}  $*"; warn_count=$((warn_count + 1)); }

echo ""
echo -e "${BOLD}${CYAN}Humanless Pipeline — Verification${RESET}"
echo ""

# ─── 1. Hook Script Syntax ──────────────────────────────────────────────────
echo -e "${BOLD}Hook scripts (bash -n parse check):${RESET}"
hook_dir="$CLAUDE_DIR/hooks"
if [[ -d "$hook_dir" ]]; then
    hook_files=0
    while IFS= read -r -d '' hook; do
        hook_files=$((hook_files + 1))
        name="$(basename "$hook")"
        # Resolve symlink for parse check
        real_path="$(readlink -f "$hook" 2>/dev/null || echo "$hook")"
        if [[ -f "$real_path" ]]; then
            if bash -n "$real_path" 2>/dev/null; then
                pass "$name"
            else
                fail "$name — syntax error"
            fi
        else
            fail "$name — broken symlink -> $real_path"
        fi
    done < <(find "$hook_dir" -maxdepth 1 -name '*.sh' -print0 2>/dev/null)

    # Check lib/ hooks too
    if [[ -d "$hook_dir/lib" ]]; then
        while IFS= read -r -d '' hook; do
            hook_files=$((hook_files + 1))
            name="lib/$(basename "$hook")"
            real_path="$(readlink -f "$hook" 2>/dev/null || echo "$hook")"
            if [[ -f "$real_path" ]]; then
                if bash -n "$real_path" 2>/dev/null; then
                    pass "$name"
                else
                    fail "$name — syntax error"
                fi
            else
                fail "$name — broken symlink"
            fi
        done < <(find "$hook_dir/lib" -maxdepth 1 -type f -o -type l -print0 2>/dev/null)
    fi

    if [[ $hook_files -eq 0 ]]; then
        skip "No hook scripts found in $hook_dir"
    fi
else
    fail "Hook directory missing: $hook_dir"
fi

# ─── 2. settings.json Validity ──────────────────────────────────────────────
echo ""
echo -e "${BOLD}Configuration files:${RESET}"
settings_file="$CLAUDE_DIR/settings.json"
if [[ -f "$settings_file" ]]; then
    if jq empty "$settings_file" 2>/dev/null; then
        pass "settings.json is valid JSON"

        # Check key sections exist
        if jq -e '.permissions' "$settings_file" &>/dev/null; then
            pass "settings.json has permissions section"
        else
            fail "settings.json missing permissions section"
        fi

        if jq -e '.hooks' "$settings_file" &>/dev/null; then
            pass "settings.json has hooks section"
        else
            fail "settings.json missing hooks section"
        fi

        # Check no unresolved template placeholders
        if grep -q '{{' "$settings_file"; then
            fail "settings.json has unresolved {{placeholders}}"
        else
            pass "settings.json has no unresolved placeholders"
        fi
    else
        fail "settings.json is invalid JSON"
    fi
else
    fail "settings.json not found"
fi

# Check CLAUDE.md
claude_md="$CLAUDE_DIR/CLAUDE.md"
if [[ -f "$claude_md" ]]; then
    if grep -q '{{' "$claude_md"; then
        fail "CLAUDE.md has unresolved {{placeholders}}"
    else
        pass "CLAUDE.md exists and has no unresolved placeholders"
    fi
else
    skip "CLAUDE.md not found (run install.sh to generate)"
fi

# Check project registry
registry="$CLAUDE_DIR/config/project-registry.json"
if [[ -f "$registry" ]]; then
    if jq empty "$registry" 2>/dev/null; then
        pass "project-registry.json is valid JSON"
    else
        fail "project-registry.json is invalid JSON"
    fi
else
    skip "project-registry.json not found"
fi

# ─── 3. Symlink Resolution ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Symlink integrity:${RESET}"

check_symlinks_in() {
    local dir="$1"
    local label="$2"
    local found=0

    if [[ ! -d "$dir" ]]; then
        skip "$label directory missing: $dir"
        return
    fi

    while IFS= read -r -d '' item; do
        found=$((found + 1))
        name="$(basename "$item")"
        if [[ -L "$item" ]]; then
            target="$(readlink -f "$item" 2>/dev/null || echo "BROKEN")"
            if [[ -e "$target" ]]; then
                pass "$label/$name -> $(readlink "$item")"
            else
                fail "$label/$name — broken symlink -> $(readlink "$item")"
            fi
        fi
    done < <(find "$dir" -maxdepth 1 -type l -print0 2>/dev/null)

    if [[ $found -eq 0 ]]; then
        skip "No symlinks in $label (files may be copies)"
    fi
}

check_symlinks_in "$CLAUDE_DIR/hooks" "hooks"
check_symlinks_in "$CLAUDE_DIR/agents" "agents"
# Skills live in ~/.claude/skills; older installs used ~/.agents/skills
if [[ -d "$CLAUDE_DIR/skills" ]]; then
    check_symlinks_in "$CLAUDE_DIR/skills" "skills"
else
    check_symlinks_in "$AGENTS_DIR/skills" "skills (legacy path)"
fi

# ─── 4. Agent Files ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Agent definitions:${RESET}"
agent_dir="$CLAUDE_DIR/agents"
if [[ -d "$agent_dir" ]]; then
    agent_count=0
    while IFS= read -r -d '' agent; do
        agent_count=$((agent_count + 1))
        name="$(basename "$agent")"
        real="$(readlink -f "$agent" 2>/dev/null || echo "$agent")"
        if [[ -f "$real" && -s "$real" ]]; then
            pass "$name ($(wc -l < "$real") lines)"
        elif [[ -f "$real" ]]; then
            skip "$name exists but is empty"
        else
            fail "$name — file missing or broken link"
        fi
    done < <(find "$agent_dir" -maxdepth 1 -name '*.md' -print0 2>/dev/null)

    if [[ $agent_count -eq 0 ]]; then
        skip "No agent .md files found"
    fi
else
    fail "Agents directory missing: $agent_dir"
fi

# ─── 5. Pipeline Directory Structure ────────────────────────────────────────
echo ""
echo -e "${BOLD}Pipeline directory structure:${RESET}"

EXPECTED_DIRS=(
    "$PIPELINE_DIR"
    "$PIPELINE_DIR/circuit"
    "$PIPELINE_DIR/learnings"
    "$PIPELINE_DIR/logs"
    "$PIPELINE_DIR/tasks"
    "$PIPELINE_DIR/tasks/active"
    "$PIPELINE_DIR/tasks/backlog"
    "$PIPELINE_DIR/tasks/done"
    "$PIPELINE_DIR/tasks/failed"
    "$PIPELINE_DIR/tasks/blocked"
    "$PIPELINE_DIR/tasks/archived"
    "$PIPELINE_DIR/debounce"
    "$PIPELINE_DIR/progress"
    "$PIPELINE_DIR/scripts"
    "$PIPELINE_DIR/formulas"
    "$CLAUDE_DIR/plans"
    "$CLAUDE_DIR/plugins"
    "$CLAUDE_DIR/cache"
    "$CLAUDE_DIR/config"
    "$CLAUDE_DIR/debug"
    "$CLAUDE_DIR/backups"
)

for dir in "${EXPECTED_DIRS[@]}"; do
    short="${dir/#$HOME/~}"
    if [[ -d "$dir" ]]; then
        pass "$short"
    else
        fail "$short — missing"
    fi
done

# ─── 6. SQLite Databases ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}SQLite databases:${RESET}"

check_db() {
    local db_path="$1"
    local db_name="$2"
    local expected_table="$3"

    if [[ ! -f "$db_path" ]]; then
        fail "$db_name not found: $db_path"
        return
    fi

    if ! sqlite3 "$db_path" "SELECT 1;" &>/dev/null; then
        fail "$db_name — cannot query (corrupted?)"
        return
    fi

    if sqlite3 "$db_path" ".tables" 2>/dev/null | grep -q "$expected_table"; then
        pass "$db_name — OK (has $expected_table table)"
    else
        fail "$db_name — missing $expected_table table"
    fi
}

check_db "$PIPELINE_DIR/cost-tracking.db" "cost-tracking.db" "tool_usage"
check_db "$PIPELINE_DIR/learnings.db" "learnings.db" "learnings"

# ─── 6b. Functional tests (hooks exercised end-to-end, isolated HOME) ───────
echo ""
echo -e "${BOLD}Functional tests:${RESET}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$REPO_DIR/tests" ]]; then
    while IFS= read -r -d '' t; do
        t_name="$(basename "$t")"
        if out=$(bash "$t" 2>&1); then
            pass "$t_name — $out"
        else
            fail "$t_name — $out"
        fi
    done < <(find "$REPO_DIR/tests" -maxdepth 1 -name "test-*.sh" -print0 | sort -z)
else
    skip "no tests/ directory in repo"
fi

# ─── 7. Git Hooks Layer (tool-agnostic gate) ────────────────────────────────
echo ""
echo -e "${BOLD}Git hooks layer:${RESET}"

git_hooks_link="$CLAUDE_DIR/git-hooks"
hookspath="$(git config --global core.hooksPath 2>/dev/null || echo "")"
if [[ -z "$hookspath" ]]; then
    fail "git core.hooksPath not set — Codex/human commits bypass the quality gate"
elif [[ "$hookspath" == "$git_hooks_link" ]]; then
    pass "git core.hooksPath -> $hookspath"
else
    skip "git core.hooksPath -> $hookspath (custom — ensure it chains the pipeline hooks)"
fi

for gh in pre-commit commit-msg post-commit; do
    gh_path="$git_hooks_link/$gh"
    real="$(readlink -f "$gh_path" 2>/dev/null || echo "$gh_path")"
    if [[ -f "$real" ]]; then
        if bash -n "$real" 2>/dev/null; then
            if [[ -x "$real" ]]; then
                pass "git-hooks/$gh"
            else
                fail "git-hooks/$gh — not executable"
            fi
        else
            fail "git-hooks/$gh — syntax error"
        fi
    else
        fail "git-hooks/$gh — missing"
    fi
done

# ─── 8. Codex Integration ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Codex integration:${RESET}"

if command -v codex &>/dev/null || [[ -d "$HOME/.codex" ]]; then
    if [[ -f "$HOME/.codex/AGENTS.md" ]]; then
        pass "~/.codex/AGENTS.md present"
    else
        fail "~/.codex/AGENTS.md missing — Codex sessions have no pipeline guidance"
    fi
    if [[ -f "$HOME/.codex/config.toml" ]]; then
        pass "~/.codex/config.toml present"
    else
        skip "~/.codex/config.toml missing (optional)"
    fi
else
    skip "Codex CLI not installed — skipping Codex checks"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}────────────────────────────────────────${RESET}"
total=$((pass_count + fail_count + warn_count))
echo -e "  ${GREEN}Passed: $pass_count${RESET}  ${RED}Failed: $fail_count${RESET}  ${YELLOW}Skipped: $warn_count${RESET}  Total: $total"
echo -e "${BOLD}────────────────────────────────────────${RESET}"
echo ""

if [[ $fail_count -gt 0 ]]; then
    echo -e "${RED}${BOLD}Verification failed with $fail_count issue(s).${RESET}"
    exit 1
else
    echo -e "${GREEN}${BOLD}All checks passed.${RESET}"
    exit 0
fi
