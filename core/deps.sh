#!/usr/bin/env bash
# deps.sh — Dependency checker and optional installer for the humanless pipeline
# Usage: source core/deps.sh    (to load functions)
#        bash core/deps.sh       (to run status table)
#        bash core/deps.sh --install  (to install missing required deps)

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ─── OS Detection ────────────────────────────────────────────────────────────
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|pop|linuxmint) echo "debian" ;;
            arch|manjaro|endeavouros) echo "arch" ;;
            fedora|rhel|centos) echo "fedora" ;;
            *) echo "unknown" ;;
        esac
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

OS_FAMILY="$(detect_os)"

# ─── Version Comparisons ────────────────────────────────────────────────────
# Returns 0 if $1 >= $2 (semver-ish: compares major only for simplicity)
version_gte() {
    local have="$1" need="$2"
    local have_major="${have%%.*}"
    local need_major="${need%%.*}"
    [[ "$have_major" -ge "$need_major" ]]
}

# ─── Install Hints ──────────────────────────────────────────────────────────
install_hint() {
    local tool="$1"
    case "$OS_FAMILY" in
        debian)
            case "$tool" in
                node)      echo "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs" ;;
                npm)       echo "Installed with node (see above)" ;;
                python3)   echo "sudo apt-get install -y python3 python3-pip" ;;
                git)       echo "sudo apt-get install -y git" ;;
                jq)        echo "sudo apt-get install -y jq" ;;
                sqlite3)   echo "sudo apt-get install -y sqlite3" ;;
                tmux)      echo "sudo apt-get install -y tmux" ;;
                gh)        echo "curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && echo 'deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main' | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null && sudo apt update && sudo apt install gh -y" ;;
                claude)    echo "npm install -g @anthropic-ai/claude-code" ;;
                bun)       echo "curl -fsSL https://bun.sh/install | bash" ;;
                ruff)      echo "pip3 install ruff" ;;
                google-chrome-stable) echo "wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && sudo dpkg -i google-chrome-stable_current_amd64.deb && rm google-chrome-stable_current_amd64.deb" ;;
                dolt)      echo "sudo bash -c 'curl -L https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash'" ;;
                *)         echo "See https://github.com/$tool for install instructions" ;;
            esac
            ;;
        arch)
            case "$tool" in
                node)      echo "sudo pacman -S nodejs npm" ;;
                npm)       echo "Installed with node (see above)" ;;
                python3)   echo "sudo pacman -S python python-pip" ;;
                git)       echo "sudo pacman -S git" ;;
                jq)        echo "sudo pacman -S jq" ;;
                sqlite3)   echo "sudo pacman -S sqlite" ;;
                tmux)      echo "sudo pacman -S tmux" ;;
                gh)        echo "sudo pacman -S github-cli" ;;
                claude)    echo "npm install -g @anthropic-ai/claude-code" ;;
                bun)       echo "curl -fsSL https://bun.sh/install | bash" ;;
                ruff)      echo "pip3 install ruff" ;;
                google-chrome-stable) echo "yay -S google-chrome" ;;
                dolt)      echo "sudo bash -c 'curl -L https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash'" ;;
                *)         echo "See https://github.com/$tool for install instructions" ;;
            esac
            ;;
        macos)
            case "$tool" in
                node)      echo "brew install node@22" ;;
                npm)       echo "Installed with node (see above)" ;;
                python3)   echo "brew install python3" ;;
                git)       echo "brew install git" ;;
                jq)        echo "brew install jq" ;;
                sqlite3)   echo "brew install sqlite" ;;
                tmux)      echo "brew install tmux" ;;
                gh)        echo "brew install gh" ;;
                claude)    echo "npm install -g @anthropic-ai/claude-code" ;;
                bun)       echo "brew install bun" ;;
                ruff)      echo "brew install ruff" ;;
                google-chrome-stable) echo "brew install --cask google-chrome" ;;
                dolt)      echo "brew install dolt" ;;
                *)         echo "See https://github.com/$tool for install instructions" ;;
            esac
            ;;
        *)
            echo "Install $tool manually — see project docs"
            ;;
    esac
}

# ─── Auto-install command ───────────────────────────────────────────────────
install_tool() {
    local tool="$1"
    case "$OS_FAMILY" in
        debian)
            case "$tool" in
                node)
                    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
                    sudo apt-get install -y nodejs
                    ;;
                python3)   sudo apt-get install -y python3 python3-pip ;;
                git)       sudo apt-get install -y git ;;
                jq)        sudo apt-get install -y jq ;;
                sqlite3)   sudo apt-get install -y sqlite3 ;;
                tmux)      sudo apt-get install -y tmux ;;
                gh)
                    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                    sudo apt update && sudo apt install gh -y
                    ;;
                claude)    npm install -g @anthropic-ai/claude-code ;;
                *)         echo "No auto-install for $tool"; return 1 ;;
            esac
            ;;
        arch)
            case "$tool" in
                node)      sudo pacman -S --noconfirm nodejs npm ;;
                python3)   sudo pacman -S --noconfirm python python-pip ;;
                git)       sudo pacman -S --noconfirm git ;;
                jq)        sudo pacman -S --noconfirm jq ;;
                sqlite3)   sudo pacman -S --noconfirm sqlite ;;
                tmux)      sudo pacman -S --noconfirm tmux ;;
                gh)        sudo pacman -S --noconfirm github-cli ;;
                claude)    npm install -g @anthropic-ai/claude-code ;;
                *)         echo "No auto-install for $tool"; return 1 ;;
            esac
            ;;
        macos)
            case "$tool" in
                node)      brew install node@22 ;;
                python3)   brew install python3 ;;
                git)       brew install git ;;
                jq)        brew install jq ;;
                sqlite3)   brew install sqlite ;;
                tmux)      brew install tmux ;;
                gh)        brew install gh ;;
                claude)    npm install -g @anthropic-ai/claude-code ;;
                *)         echo "No auto-install for $tool"; return 1 ;;
            esac
            ;;
        *)
            echo "Auto-install not supported for OS family: $OS_FAMILY"
            return 1
            ;;
    esac
}

# ─── Check a single tool ────────────────────────────────────────────────────
# Returns: "version_string" or "" (empty = missing)
check_tool() {
    local tool="$1"
    case "$tool" in
        node)
            if command -v node &>/dev/null; then
                node --version 2>/dev/null | sed 's/^v//'
            fi
            ;;
        npm)
            if command -v npm &>/dev/null; then
                npm --version 2>/dev/null
            fi
            ;;
        python3)
            if command -v python3 &>/dev/null; then
                python3 --version 2>/dev/null | awk '{print $2}'
            fi
            ;;
        git)
            if command -v git &>/dev/null; then
                git --version 2>/dev/null | awk '{print $3}'
            fi
            ;;
        jq)
            if command -v jq &>/dev/null; then
                jq --version 2>/dev/null | sed 's/^jq-//'
            fi
            ;;
        sqlite3)
            if command -v sqlite3 &>/dev/null; then
                sqlite3 --version 2>/dev/null | awk '{print $1}'
            fi
            ;;
        tmux)
            if command -v tmux &>/dev/null; then
                tmux -V 2>/dev/null | awk '{print $2}'
            fi
            ;;
        gh)
            if command -v gh &>/dev/null; then
                gh --version 2>/dev/null | head -1 | awk '{print $3}'
            fi
            ;;
        claude)
            if command -v claude &>/dev/null; then
                claude --version 2>/dev/null | head -1 | awk '{print $1}' || echo "installed"
            fi
            ;;
        bun)
            if command -v bun &>/dev/null; then
                bun --version 2>/dev/null
            fi
            ;;
        ruff)
            if command -v ruff &>/dev/null; then
                ruff --version 2>/dev/null | awk '{print $2}'
            fi
            ;;
        google-chrome-stable)
            if command -v google-chrome-stable &>/dev/null; then
                google-chrome-stable --version 2>/dev/null | awk '{print $NF}'
            elif command -v google-chrome &>/dev/null; then
                google-chrome --version 2>/dev/null | awk '{print $NF}'
            fi
            ;;
        dolt)
            if command -v dolt &>/dev/null; then
                dolt version 2>/dev/null | head -1 | awk '{print $3}'
            fi
            ;;
    esac
}

# ─── Required and Optional tools ────────────────────────────────────────────
REQUIRED_TOOLS=(node npm python3 git jq sqlite3 tmux gh claude)
REQUIRED_MIN_VERSIONS=("18" "" "" "" "" "" "" "" "")
OPTIONAL_TOOLS=(bun ruff google-chrome-stable dolt)

# ─── Status Table ────────────────────────────────────────────────────────────
print_status_table() {
    local missing_required=0
    local missing_optional=0

    echo ""
    echo -e "${BOLD}${CYAN}Humanless Pipeline — Dependency Check${RESET}"
    echo -e "${DIM}OS detected: ${OS_FAMILY}${RESET}"
    echo ""
    printf "${BOLD}%-25s %-12s %-10s %s${RESET}\n" "Tool" "Status" "Version" "Note"
    printf "%-25s %-12s %-10s %s\n" "-------------------------" "------------" "----------" "-----------------------------"

    # Required tools
    echo -e "\n${BOLD}Required:${RESET}"
    for i in "${!REQUIRED_TOOLS[@]}"; do
        local tool="${REQUIRED_TOOLS[$i]}"
        local min_ver="${REQUIRED_MIN_VERSIONS[$i]}"
        local version
        version="$(check_tool "$tool")"

        if [[ -n "$version" ]]; then
            # Check minimum version if specified
            if [[ -n "$min_ver" ]] && ! version_gte "$version" "$min_ver"; then
                printf "  ${YELLOW}%-23s %-12s %-10s %s${RESET}\n" "$tool" "OUTDATED" "$version" "Need >= $min_ver"
                missing_required=$((missing_required + 1))
            else
                printf "  ${GREEN}%-23s %-12s %-10s${RESET}\n" "$tool" "OK" "$version"
            fi
        else
            printf "  ${RED}%-23s %-12s %-10s %s${RESET}\n" "$tool" "MISSING" "-" "$(install_hint "$tool" | head -c 80)"
            missing_required=$((missing_required + 1))
        fi
    done

    # Optional tools
    echo -e "\n${BOLD}Optional:${RESET}"
    for tool in "${OPTIONAL_TOOLS[@]}"; do
        local version
        version="$(check_tool "$tool")"

        if [[ -n "$version" ]]; then
            printf "  ${GREEN}%-23s %-12s %-10s${RESET}\n" "$tool" "OK" "$version"
        else
            printf "  ${DIM}%-23s %-12s %-10s %s${RESET}\n" "$tool" "MISSING" "-" "$(install_hint "$tool" | head -c 80)"
            missing_optional=$((missing_optional + 1))
        fi
    done

    echo ""
    printf "%-25s %-12s\n" "-------------------------" "------------"

    if [[ "$missing_required" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}All required dependencies satisfied.${RESET}"
    else
        echo -e "${RED}${BOLD}$missing_required required tool(s) missing.${RESET}"
        echo -e "${DIM}Run with --install to auto-install missing required tools.${RESET}"
    fi

    if [[ "$missing_optional" -gt 0 ]]; then
        echo -e "${YELLOW}$missing_optional optional tool(s) missing (not required for core functionality).${RESET}"
    fi

    echo ""
    return "$missing_required"
}

# ─── Install missing required tools ─────────────────────────────────────────
install_missing() {
    local to_install=()

    for i in "${!REQUIRED_TOOLS[@]}"; do
        local tool="${REQUIRED_TOOLS[$i]}"
        local min_ver="${REQUIRED_MIN_VERSIONS[$i]}"
        local version
        version="$(check_tool "$tool")"

        if [[ -z "$version" ]]; then
            to_install+=("$tool")
        elif [[ -n "$min_ver" ]] && ! version_gte "$version" "$min_ver"; then
            to_install+=("$tool")
        fi
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        echo -e "${GREEN}All required tools already installed.${RESET}"
        return 0
    fi

    echo -e "${BOLD}The following tools will be installed:${RESET}"
    for tool in "${to_install[@]}"; do
        echo -e "  ${CYAN}$tool${RESET} — $(install_hint "$tool")"
    done
    echo ""

    read -rp "Proceed with installation? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo "Aborted."
        return 1
    fi

    echo ""
    for tool in "${to_install[@]}"; do
        echo -e "${BLUE}Installing $tool...${RESET}"
        if install_tool "$tool"; then
            echo -e "${GREEN}  $tool installed successfully.${RESET}"
        else
            echo -e "${RED}  Failed to install $tool. Install manually:${RESET}"
            echo -e "    $(install_hint "$tool")"
        fi
        echo ""
    done

    echo -e "${BOLD}Re-checking dependencies...${RESET}"
    print_status_table
}

# ─── Programmatic check (for sourcing) ──────────────────────────────────────
# Returns 0 if all required deps present, 1 otherwise
check_all_required() {
    local missing=0
    for i in "${!REQUIRED_TOOLS[@]}"; do
        local tool="${REQUIRED_TOOLS[$i]}"
        local min_ver="${REQUIRED_MIN_VERSIONS[$i]}"
        local version
        version="$(check_tool "$tool")"

        if [[ -z "$version" ]]; then
            missing=$((missing + 1))
        elif [[ -n "$min_ver" ]] && ! version_gte "$version" "$min_ver"; then
            missing=$((missing + 1))
        fi
    done
    return "$missing"
}

# ─── Main ────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --install)
            install_missing
            ;;
        --check)
            # Silent check — exit code only
            check_all_required
            ;;
        *)
            print_status_table
            ;;
    esac
fi
