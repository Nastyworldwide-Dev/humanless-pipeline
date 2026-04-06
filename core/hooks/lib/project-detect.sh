#!/usr/bin/env bash
# project-detect.sh — Shared library for project-aware hooks
# Source this file to auto-detect project context.
#
# Auto-set variables (<10ms):
#   PD_PROJECT_ROOT    — git root or CWD
#   PD_PROJECT_TYPE    — frappe-bench | electron | monorepo | android | node | generic
#   PD_BENCH_ROOT      — frappe bench root (if applicable, else empty)
#   PD_IS_FRAPPE_BENCH — 1 or 0
#
# On-demand functions (cached):
#   pd_get_custom_apps    — space-separated custom apps (excludes frappe/erpnext/hrms)
#   pd_get_site_name      — default site name
#   pd_get_app_for_file   — which app a file belongs to
#   pd_get_linter         — linter command for file extension
#   pd_get_formatter      — formatter command for file extension
#   pd_get_reviewers      — reviewer agent names for an app
#
# Usage: source "$PIPELINE_HOOKS_DIR/lib/project-detect.sh"

# Guard against multiple sourcing
[ -n "${_PD_LOADED:-}" ] && return 0
_PD_LOADED=1

# Registry path (user can override via PIPELINE_REGISTRY env var)
PD_REGISTRY="${PIPELINE_REGISTRY:-$HOME/.claude/project-registry.json}"

# ─── Auto-detect project root ───────────────────────────────────────

PD_PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")

# ─── Detect project type ────────────────────────────────────────────

_pd_detect_type() {
    local dir="$1"

    # Check registry first (exact match or parent match)
    if [ -f "$PD_REGISTRY" ] && command -v jq &>/dev/null; then
        local registered_type
        registered_type=$(jq -r --arg d "$dir" '
            .projects[$d].type // empty
        ' "$PD_REGISTRY" 2>/dev/null)
        if [ -n "$registered_type" ]; then
            echo "$registered_type"
            return
        fi
        # Check if CWD is under a registered project
        local key
        for key in $(jq -r '.projects | keys[]' "$PD_REGISTRY" 2>/dev/null); do
            if [[ "$dir" == "$key"* ]]; then
                registered_type=$(jq -r --arg k "$key" '.projects[$k].type // empty' "$PD_REGISTRY" 2>/dev/null)
                if [ -n "$registered_type" ]; then
                    echo "$registered_type"
                    return
                fi
            fi
        done
    fi

    # Auto-detect from marker files (walk up from dir)
    local check="$dir"
    while [ "$check" != "/" ]; do
        # Frappe bench: has sites/common_site_config.json + apps/ dir
        if [ -f "$check/sites/common_site_config.json" ] && [ -d "$check/apps" ]; then
            echo "frappe-bench"
            return
        fi
        # Electron: electron-builder.yml
        if [ -f "$check/electron-builder.yml" ] || [ -f "$check/electron-builder.json5" ]; then
            echo "electron"
            return
        fi
        # Bun+Turbo monorepo
        if { [ -f "$check/turbo.json" ] || [ -f "$check/turbo.jsonc" ]; } && [ -f "$check/bun.lock" ]; then
            echo "monorepo"
            return
        fi
        # Android
        if [ -f "$check/build.gradle.kts" ] && [ -d "$check/app/src" ]; then
            echo "android"
            return
        fi
        # Node (generic — must be last among JS checks)
        if [ -f "$check/package.json" ] && [ "$check" = "$dir" ]; then
            # Only match at project root, not parent dirs
            echo "node"
            return
        fi
        check=$(dirname "$check")
    done

    echo "generic"
}

PD_PROJECT_TYPE=$(_pd_detect_type "$PD_PROJECT_ROOT")

# ─── Frappe bench specifics ─────────────────────────────────────────

_pd_find_bench_root() {
    local dir="$1"
    local check="$dir"
    while [ "$check" != "/" ]; do
        if [ -f "$check/sites/common_site_config.json" ] && [ -d "$check/apps" ]; then
            echo "$check"
            return
        fi
        check=$(dirname "$check")
    done
    echo ""
}

if [ "$PD_PROJECT_TYPE" = "frappe-bench" ]; then
    PD_BENCH_ROOT=$(_pd_find_bench_root "$PD_PROJECT_ROOT")
    PD_IS_FRAPPE_BENCH=1
else
    PD_BENCH_ROOT=""
    PD_IS_FRAPPE_BENCH=0
fi

# ─── Registry lookup helper ─────────────────────────────────────────

# Find the registry key for current project
_pd_registry_key() {
    if [ ! -f "$PD_REGISTRY" ] || ! command -v jq &>/dev/null; then
        echo ""
        return
    fi
    # Try exact match on project root
    if jq -e --arg d "$PD_PROJECT_ROOT" '.projects[$d]' "$PD_REGISTRY" &>/dev/null; then
        echo "$PD_PROJECT_ROOT"
        return
    fi
    # Try bench root
    if [ -n "$PD_BENCH_ROOT" ]; then
        if jq -e --arg d "$PD_BENCH_ROOT" '.projects[$d]' "$PD_REGISTRY" &>/dev/null; then
            echo "$PD_BENCH_ROOT"
            return
        fi
    fi
    # Walk up
    local check="$PD_PROJECT_ROOT"
    while [ "$check" != "/" ]; do
        if jq -e --arg d "$check" '.projects[$d]' "$PD_REGISTRY" &>/dev/null; then
            echo "$check"
            return
        fi
        check=$(dirname "$check")
    done
    echo ""
}

_PD_REG_KEY=""  # lazy-loaded

_pd_ensure_reg_key() {
    if [ -z "$_PD_REG_KEY" ]; then
        _PD_REG_KEY=$(_pd_registry_key)
    fi
}

# ─── On-demand functions ────────────────────────────────────────────

# Cache for expensive operations
_PD_CUSTOM_APPS_CACHE=""
_PD_SITE_NAME_CACHE=""

pd_get_custom_apps() {
    # Returns space-separated list of custom apps (excludes framework apps)
    if [ -n "$_PD_CUSTOM_APPS_CACHE" ]; then
        echo "$_PD_CUSTOM_APPS_CACHE"
        return
    fi

    local apps=""

    # Try registry first
    _pd_ensure_reg_key
    if [ -n "$_PD_REG_KEY" ]; then
        apps=$(jq -r --arg k "$_PD_REG_KEY" '
            .projects[$k].custom_apps // [] | join(" ")
        ' "$PD_REGISTRY" 2>/dev/null)
    fi

    # Fall back to reading installed_apps.json from bench
    if [ -z "$apps" ] && [ -n "$PD_BENCH_ROOT" ]; then
        local site
        site=$(pd_get_site_name)
        if [ -n "$site" ] && [ -f "$PD_BENCH_ROOT/sites/$site/installed_apps.json" ]; then
            apps=$(jq -r '.[].app_name // empty' "$PD_BENCH_ROOT/sites/$site/installed_apps.json" 2>/dev/null \
                | grep -vE '^(frappe|erpnext|hrms|payments|india_compliance|lms)$' \
                | tr '\n' ' ')
        fi
    fi

    # Fall back to scanning apps/ directory
    if [ -z "$apps" ] && [ -n "$PD_BENCH_ROOT" ] && [ -d "$PD_BENCH_ROOT/apps" ]; then
        apps=$(ls -d "$PD_BENCH_ROOT/apps"/*/ 2>/dev/null \
            | xargs -I{} basename {} \
            | grep -vE '^(frappe|erpnext|hrms|payments|india_compliance|lms)$' \
            | tr '\n' ' ')
    fi

    _PD_CUSTOM_APPS_CACHE=$(echo "$apps" | xargs)  # trim whitespace
    echo "$_PD_CUSTOM_APPS_CACHE"
}

pd_get_site_name() {
    # Returns the default site name
    if [ -n "$_PD_SITE_NAME_CACHE" ]; then
        echo "$_PD_SITE_NAME_CACHE"
        return
    fi

    local site=""

    # Try registry
    _pd_ensure_reg_key
    if [ -n "$_PD_REG_KEY" ]; then
        site=$(jq -r --arg k "$_PD_REG_KEY" '.projects[$k].site // empty' "$PD_REGISTRY" 2>/dev/null)
    fi

    # Fall back to currentsite.txt
    if [ -z "$site" ] && [ -n "$PD_BENCH_ROOT" ]; then
        if [ -f "$PD_BENCH_ROOT/sites/currentsite.txt" ]; then
            site=$(cat "$PD_BENCH_ROOT/sites/currentsite.txt" 2>/dev/null | tr -d '[:space:]')
        fi
    fi

    _PD_SITE_NAME_CACHE="$site"
    echo "$_PD_SITE_NAME_CACHE"
}

pd_get_app_for_file() {
    # Given a file path, returns which Frappe app it belongs to
    local file_path="$1"

    if [ "$PD_IS_FRAPPE_BENCH" != "1" ] || [ -z "$PD_BENCH_ROOT" ]; then
        echo ""
        return
    fi

    # Extract app name from path: .../apps/<app_name>/...
    if [[ "$file_path" == *"/apps/"* ]]; then
        echo "$file_path" | sed 's|.*/apps/\([^/]*\)/.*|\1|'
    else
        echo ""
    fi
}

pd_get_linter() {
    # Given a file extension (py, js, ts, kt), returns the linter command
    local ext="$1"

    # Try registry
    _pd_ensure_reg_key
    if [ -n "$_PD_REG_KEY" ]; then
        local linter
        linter=$(jq -r --arg k "$_PD_REG_KEY" --arg e "$ext" '
            .projects[$k].linters[$e] // empty
        ' "$PD_REGISTRY" 2>/dev/null)
        if [ -n "$linter" ]; then
            echo "$linter"
            return
        fi
    fi

    # Defaults by extension
    case "$ext" in
        py) echo "ruff check" ;;
        js) echo "npx oxlint" ;;
        ts|tsx) echo "npx oxlint" ;;
        kt|kts) echo "./gradlew detekt" ;;
        *) echo "" ;;
    esac
}

pd_get_formatter() {
    # Given a file extension, returns the formatter command
    local ext="$1"

    # Try registry
    _pd_ensure_reg_key
    if [ -n "$_PD_REG_KEY" ]; then
        local formatter
        formatter=$(jq -r --arg k "$_PD_REG_KEY" --arg e "$ext" '
            .projects[$k].formatters[$e] // empty
        ' "$PD_REGISTRY" 2>/dev/null)
        if [ -n "$formatter" ]; then
            echo "$formatter"
            return
        fi
    fi

    # Defaults
    case "$ext" in
        py) echo "ruff format" ;;
        js|jsx|ts|tsx) echo "" ;;  # needs biome.json discovery
        *) echo "" ;;
    esac
}

pd_get_reviewers() {
    # Given an app name, returns reviewer config from registry
    # Output: JSON object with agent patterns, or empty
    local app="$1"

    _pd_ensure_reg_key
    if [ -z "$_PD_REG_KEY" ]; then
        echo ""
        return
    fi

    jq -r --arg k "$_PD_REG_KEY" --arg a "$app" '
        .projects[$k].reviewers[$a] // empty
    ' "$PD_REGISTRY" 2>/dev/null
}

pd_get_reviewer_max_concurrent() {
    # Given an app name, returns max concurrent reviewers
    local app="$1"
    _pd_ensure_reg_key
    [ -n "$_PD_REG_KEY" ] || { echo "3"; return; }
    local max
    max=$(jq -r --arg k "$_PD_REG_KEY" --arg a "$app" '
        .projects[$k].reviewers[$a].max_concurrent // 3
    ' "$PD_REGISTRY" 2>/dev/null)
    echo "${max:-3}"
}

pd_get_reviewer_agents() {
    # Given an app name, returns space-separated list of reviewer types
    local app="$1"
    _pd_ensure_reg_key
    [ -n "$_PD_REG_KEY" ] || { echo ""; return; }
    jq -r --arg k "$_PD_REG_KEY" --arg a "$app" '
        .projects[$k].reviewers[$a].agents // {} | keys | join(" ")
    ' "$PD_REGISTRY" 2>/dev/null
}

pd_get_reviewer_pattern() {
    # Given app + reviewer type, returns the file match pattern
    local app="$1"
    local reviewer_type="$2"
    _pd_ensure_reg_key
    [ -n "$_PD_REG_KEY" ] || { echo ""; return; }
    jq -r --arg k "$_PD_REG_KEY" --arg a "$app" --arg r "$reviewer_type" '
        .projects[$k].reviewers[$a].agents[$r] // empty
    ' "$PD_REGISTRY" 2>/dev/null
}

# ─── Utility: match file against pipe-separated glob patterns ────────

pd_file_matches_pattern() {
    # Check if a file path matches any pattern in a pipe-separated pattern string
    # Patterns use glob-like syntax: app/hooks.py|app/*/api*
    local file="$1"
    local patterns="$2"

    IFS='|' read -ra PATS <<< "$patterns"
    for pat in "${PATS[@]}"; do
        # Convert glob to regex: * → [^/]*, ** → .*
        local regex
        regex=$(echo "$pat" | sed 's|\*\*|__DOUBLESTAR__|g' | sed 's|\*|[^/]*|g' | sed 's|__DOUBLESTAR__|.*|g')
        if echo "$file" | grep -qP "$regex" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}
