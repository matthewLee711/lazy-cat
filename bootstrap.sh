#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# bootstrap.sh — Master AI Development Environment Installer
# Supports: macOS (Homebrew) and Ubuntu/Debian (apt)
# Usage:    ./bootstrap.sh [--dry-run] [--help]
# ============================================================================

# ---------------------------------------------------------------------------
# Resolve SCRIPT_DIR reliably (works with symlinks, sourcing, any cwd)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Color & symbol constants
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

SYM_OK="${GREEN}✓${RESET}"
SYM_FAIL="${RED}✗${RESET}"
SYM_WORK="${YELLOW}⟳${RESET}"
SYM_SKIP="${CYAN}─${RESET}"

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------
DRY_RUN=false
OS_TYPE=""          # "macos" or "ubuntu"
ERRORS=()           # collect non-fatal error messages

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
${BOLD}Usage:${RESET} ./bootstrap.sh [OPTIONS]

${BOLD}Options:${RESET}
  --dry-run   Preview every action without making changes
  --help      Show this help message and exit

${BOLD}Description:${RESET}
  Installs and configures a complete AI development environment:
    • Docker + Ollama (via Docker Compose)
    • Node.js 20+, Python 3.10+, uv
    • OpenCode CLI, OpenSpec CLI
    • MCP / OpenCode / Caveman prompt configs

  Safe to re-run — each step checks for existing installations first.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --help|-h) usage; exit 0 ;;
        *)
            echo -e "${SYM_FAIL} Unknown option: ${arg}"
            usage
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
banner() {
    echo ""
    echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}${BOLD}║          AI Development Environment — Bootstrap             ║${RESET}"
    echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    if $DRY_RUN; then
        echo -e "  ${YELLOW}${BOLD}▶ DRY-RUN MODE — no changes will be made${RESET}"
        echo ""
    fi
}

log_step() {
    local num="$1"; shift
    echo -e "\n${BOLD}[${num}]${RESET} $*"
}

log_ok()   { echo -e "  ${SYM_OK}  $*"; }
log_fail() { echo -e "  ${SYM_FAIL}  $*"; }
log_work() { echo -e "  ${SYM_WORK}  $*"; }
log_skip() { echo -e "  ${SYM_SKIP}  $*"; }

# Run a command (or just print it in dry-run mode)
run() {
    if $DRY_RUN; then
        echo -e "  ${DIM}[dry-run] $*${RESET}"
        return 0
    fi
    "$@"
}

# Check if a command exists on PATH
has_cmd() { command -v "$1" &>/dev/null; }

# Record a non-fatal error so the script can continue
record_error() { ERRORS+=("$1"); }

# ---------------------------------------------------------------------------
# Detect OS
# ---------------------------------------------------------------------------
detect_os() {
    log_step "0" "Detecting operating system …"
    case "$(uname -s)" in
        Darwin*)
            OS_TYPE="macos"
            log_ok "macOS detected ($(sw_vers -productVersion 2>/dev/null || echo 'unknown version'))"
            ;;
        Linux*)
            if [[ -f /etc/os-release ]]; then
                # shellcheck disable=SC1091
                source /etc/os-release
                if [[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *"debian"* || "${ID:-}" == "debian" ]]; then
                    OS_TYPE="ubuntu"
                    log_ok "Ubuntu/Debian detected (${PRETTY_NAME:-unknown})"
                else
                    OS_TYPE="ubuntu"  # best-effort: treat other Linux as Debian-ish
                    log_work "Linux detected (${PRETTY_NAME:-unknown}) — treating as Debian-based"
                fi
            else
                OS_TYPE="ubuntu"
                log_work "Linux detected (no /etc/os-release) — treating as Debian-based"
            fi
            ;;
        *)
            log_fail "Unsupported OS: $(uname -s)"
            exit 1
            ;;
    esac
}

# ===========================  INSTALL STEPS  ================================

# ---------------------------------------------------------------------------
# 1. Prerequisites
# ---------------------------------------------------------------------------
install_prerequisites() {
    log_step "1" "Prerequisites"

    if [[ "$OS_TYPE" == "macos" ]]; then
        # Xcode command-line tools
        if xcode-select -p &>/dev/null; then
            log_ok "Xcode CLI tools already installed"
        else
            log_work "Installing Xcode CLI tools …"
            run xcode-select --install || true
            log_ok "Xcode CLI tools install triggered (may need manual approval)"
        fi

        # Homebrew
        if has_cmd brew; then
            log_ok "Homebrew already installed ($(brew --version 2>/dev/null | head -1))"
        else
            log_work "Installing Homebrew …"
            run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Ensure brew is on PATH for the rest of this session
            if [[ -f /opt/homebrew/bin/brew ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -f /usr/local/bin/brew ]]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            log_ok "Homebrew installed"
        fi
    else
        log_work "Updating apt and installing base packages …"
        run sudo apt update -y
        run sudo apt install -y curl git build-essential
        log_ok "Base packages installed"
    fi
}

# ---------------------------------------------------------------------------
# 2. Docker
# ---------------------------------------------------------------------------
install_docker() {
    log_step "2" "Docker"

    if has_cmd docker; then
        log_ok "Docker already installed ($(docker --version 2>/dev/null || echo 'unknown'))"
    else
        log_work "Installing Docker …"
        if [[ "$OS_TYPE" == "macos" ]]; then
            run brew install --cask docker
        else
            run sudo apt install -y docker.io docker-compose-plugin
            run sudo systemctl enable --now docker
            run sudo usermod -aG docker "$USER"
            log_work "Added ${USER} to docker group (log out/in to take effect)"
        fi
        log_ok "Docker installed"
    fi

    # On Ubuntu, ensure the service is enabled even if docker was already present
    if [[ "$OS_TYPE" == "ubuntu" ]]; then
        if systemctl is-active --quiet docker 2>/dev/null; then
            log_ok "Docker daemon running"
        else
            log_work "Enabling Docker daemon …"
            run sudo systemctl enable --now docker
            log_ok "Docker daemon started"
        fi
    fi
}

# ---------------------------------------------------------------------------
# 3. Node.js 20+
# ---------------------------------------------------------------------------
install_node() {
    log_step "3" "Node.js 20+"

    if has_cmd node; then
        local node_major
        node_major="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
        if [[ "$node_major" -ge 20 ]] 2>/dev/null; then
            log_ok "Node.js already installed ($(node --version))"
            return
        else
            log_work "Node.js found but version $(node --version) < 20 — upgrading …"
        fi
    else
        log_work "Installing Node.js …"
    fi

    if [[ "$OS_TYPE" == "macos" ]]; then
        run brew install node
    else
        run bash -c 'curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -'
        run sudo apt install -y nodejs
    fi
    log_ok "Node.js installed"
}

# ---------------------------------------------------------------------------
# 4. Python 3.10+
# ---------------------------------------------------------------------------
install_python() {
    log_step "4" "Python 3.10+"

    if has_cmd python3; then
        local py_minor
        py_minor="$(python3 -c 'import sys; print(sys.version_info.minor)' 2>/dev/null || echo 0)"
        local py_major
        py_major="$(python3 -c 'import sys; print(sys.version_info.major)' 2>/dev/null || echo 0)"
        if [[ "$py_major" -ge 3 && "$py_minor" -ge 10 ]] 2>/dev/null; then
            log_ok "Python already installed ($(python3 --version))"
            return
        else
            log_work "Python $(python3 --version 2>/dev/null) is below 3.10 — upgrading …"
        fi
    else
        log_work "Installing Python …"
    fi

    if [[ "$OS_TYPE" == "macos" ]]; then
        run brew install python
    else
        run sudo apt install -y python3 python3-pip python3-venv
    fi
    log_ok "Python installed"
}

# ---------------------------------------------------------------------------
# 5. uv (Python package manager)
# ---------------------------------------------------------------------------
install_uv() {
    log_step "5" "uv (Python package manager)"

    if has_cmd uv; then
        log_ok "uv already installed ($(uv --version 2>/dev/null || echo 'unknown'))"
        return
    fi

    log_work "Installing uv …"
    if [[ "$OS_TYPE" == "macos" ]]; then
        run brew install uv
    else
        run bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
        # Source cargo env to get uv on PATH for the rest of this session
        if [[ -f "$HOME/.local/bin/env" ]]; then
            # shellcheck disable=SC1091
            source "$HOME/.local/bin/env" 2>/dev/null || true
        fi
        if [[ -f "$HOME/.cargo/env" ]]; then
            # shellcheck disable=SC1091
            source "$HOME/.cargo/env" 2>/dev/null || true
        fi
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    fi
    log_ok "uv installed"
}

# ---------------------------------------------------------------------------
# 6. Start Docker
# ---------------------------------------------------------------------------
start_docker() {
    log_step "6" "Start Docker daemon"

    if [[ "$OS_TYPE" == "macos" ]]; then
        if docker info &>/dev/null; then
            log_ok "Docker daemon already running"
        else
            log_work "Starting Docker Desktop …"
            run open -a Docker

            if ! $DRY_RUN; then
                echo -ne "  ${DIM}Waiting for Docker daemon "
                local retries=0
                local max_retries=60
                while ! docker info &>/dev/null; do
                    retries=$((retries + 1))
                    if [[ $retries -ge $max_retries ]]; then
                        echo -e "${RESET}"
                        log_fail "Docker daemon did not start within ${max_retries}s"
                        record_error "Docker daemon timeout"
                        return
                    fi
                    echo -n "."
                    sleep 2
                done
                echo -e "${RESET}"
                log_ok "Docker daemon started"
            fi
        fi
    else
        if docker info &>/dev/null; then
            log_ok "Docker daemon already running"
        else
            log_work "Docker daemon not responding — ensure it is started"
            run sudo systemctl start docker || true
            log_ok "Docker start attempted"
        fi
    fi
}

# ---------------------------------------------------------------------------
# 7. Docker Compose up (Ollama)
# ---------------------------------------------------------------------------
docker_compose_up() {
    log_step "7" "Docker Compose up (Ollama)"

    local compose_file="${SCRIPT_DIR}/docker-compose.yml"
    if [[ ! -f "$compose_file" ]] && ! $DRY_RUN; then
        log_skip "No docker-compose.yml found in ${SCRIPT_DIR} — skipping"
        return
    fi

    log_work "Running docker compose up -d …"
    run docker compose -f "$compose_file" up -d
    log_ok "Containers started"
}

# ---------------------------------------------------------------------------
# 8. OpenCode CLI
# ---------------------------------------------------------------------------
install_opencode() {
    log_step "8" "OpenCode CLI"

    if has_cmd opencode; then
        log_ok "OpenCode already installed ($(opencode --version 2>/dev/null || echo 'unknown'))"
        return
    fi

    log_work "Installing opencode-ai globally via npm …"
    run npm install -g opencode-ai
    log_ok "OpenCode CLI installed"
}

# ---------------------------------------------------------------------------
# 9. OpenSpec CLI
# ---------------------------------------------------------------------------
install_openspec() {
    log_step "9" "OpenSpec CLI"

    if has_cmd openspec; then
        log_ok "OpenSpec already installed"
        return
    fi

    log_work "Installing @fission-ai/openspec@latest globally via npm …"
    run npm install -g @fission-ai/openspec@latest
    log_ok "OpenSpec CLI installed"
}

# ---------------------------------------------------------------------------
# 10. Deploy MCP config → ~/.claude.json
# ---------------------------------------------------------------------------
deploy_mcp_config() {
    log_step "10" "Deploy MCP config → ~/.claude.json"

    local src="${SCRIPT_DIR}/configs/mcp_settings.json"
    local dest="$HOME/.claude.json"

    if [[ ! -f "$src" ]] && ! $DRY_RUN; then
        log_skip "Source not found: ${src} — skipping"
        return
    fi

    if $DRY_RUN; then
        log_skip "Would merge ${src} into ${dest}"
        return
    fi

    # ---------- choose a JSON merge tool ----------
    local merge_tool=""
    if has_cmd python3; then
        merge_tool="python3"
    elif has_cmd jq; then
        merge_tool="jq"
    else
        log_fail "Neither python3 nor jq available — cannot merge JSON"
        record_error "MCP config merge: no JSON tool"
        return
    fi

    if [[ "$merge_tool" == "python3" ]]; then
        python3 - "$src" "$dest" <<'PYEOF'
import json, sys, os

src_path = sys.argv[1]
dest_path = sys.argv[2]

with open(src_path) as f:
    src_data = json.load(f)

new_servers = src_data.get("mcpServers", {})

if os.path.isfile(dest_path):
    with open(dest_path) as f:
        dest_data = json.load(f)
else:
    dest_data = {}

existing_servers = dest_data.get("mcpServers", {})

# Merge: new servers are added; existing servers with the same name are NOT overwritten
for key, value in new_servers.items():
    if key not in existing_servers:
        existing_servers[key] = value

dest_data["mcpServers"] = existing_servers

with open(dest_path, "w") as f:
    json.dump(dest_data, f, indent=2)
    f.write("\n")
PYEOF
    else
        # jq merge fallback
        if [[ -f "$dest" ]]; then
            local tmp
            tmp="$(mktemp)"
            jq -s '.[0] as $existing | .[1] as $new |
                $existing * { mcpServers: (($existing.mcpServers // {}) + ($new.mcpServers // {}) ) } |
                .mcpServers = (($new.mcpServers // {}) + (.mcpServers // {}))
            ' "$dest" "$src" > "$tmp"
            mv "$tmp" "$dest"
        else
            # No existing file — just remap from src
            jq '{ mcpServers: .mcpServers }' "$src" > "$dest"
        fi
    fi

    log_ok "MCP config deployed to ${dest}"
}

# ---------------------------------------------------------------------------
# 11. Deploy OpenCode config → ~/.config/opencode/opencode.json
# ---------------------------------------------------------------------------
deploy_opencode_config() {
    log_step "11" "Deploy OpenCode config → ~/.config/opencode/opencode.json"

    local src="${SCRIPT_DIR}/configs/opencode.json"
    local dest_dir="$HOME/.config/opencode"
    local dest="${dest_dir}/opencode.json"

    if [[ ! -f "$src" ]] && ! $DRY_RUN; then
        log_skip "Source not found: ${src} — skipping"
        return
    fi

    run mkdir -p "$dest_dir"
    run cp "$src" "$dest"
    log_ok "OpenCode config deployed to ${dest}"
}

# ---------------------------------------------------------------------------
# 12. Deploy caveman prompt → ~/.claude/commands/caveman.md
# ---------------------------------------------------------------------------
deploy_caveman_prompt() {
    log_step "12" "Deploy caveman prompt → ~/.claude/commands/caveman.md"

    local src="${SCRIPT_DIR}/configs/caveman_prompt.txt"
    local dest_dir="$HOME/.claude/commands"
    local dest="${dest_dir}/caveman.md"

    if [[ ! -f "$src" ]] && ! $DRY_RUN; then
        log_skip "Source not found: ${src} — skipping"
        return
    fi

    run mkdir -p "$dest_dir"
    run cp "$src" "$dest"
    log_ok "Caveman prompt deployed to ${dest}"
}

# ===========================  VERIFICATION  =================================

verify() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║                   Post-Install Verification                 ║${RESET}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    if $DRY_RUN; then
        echo -e "  ${DIM}Skipped in dry-run mode${RESET}"
        return
    fi

    local pass=0
    local fail=0
    local results=()

    # Helper: run a check and collect the result
    check() {
        local label="$1"; shift
        if "$@" &>/dev/null; then
            results+=("${SYM_OK}|${label}|$("$@" 2>/dev/null | head -1 || echo 'OK')")
            pass=$((pass + 1))
        else
            results+=("${SYM_FAIL}|${label}|NOT AVAILABLE")
            fail=$((fail + 1))
        fi
    }

    check_file() {
        local label="$1"
        local path="$2"
        if [[ -f "$path" ]]; then
            results+=("${SYM_OK}|${label}|${path}")
            pass=$((pass + 1))
        else
            results+=("${SYM_FAIL}|${label}|missing")
            fail=$((fail + 1))
        fi
    }

    check_url() {
        local label="$1"
        local url="$2"
        if curl -s --max-time 5 "$url" &>/dev/null; then
            results+=("${SYM_OK}|${label}|responding")
            pass=$((pass + 1))
        else
            results+=("${SYM_FAIL}|${label}|not responding")
            fail=$((fail + 1))
        fi
    }

    # --- checks ---
    check       "Docker daemon"           docker info
    check_url   "Ollama API"              "http://localhost:11434/api/tags"
    check       "Node.js"                 node --version
    check       "Python 3"                python3 --version
    check       "uv"                      uv --version
    check       "OpenCode CLI"            opencode --version
    check_file  "~/.claude.json"          "$HOME/.claude.json"
    check_file  "OpenCode config"         "$HOME/.config/opencode/opencode.json"
    check_file  "Caveman prompt"          "$HOME/.claude/commands/caveman.md"

    # --- print table ---
    printf "\n  ${BOLD}%-4s %-22s %s${RESET}\n" "" "CHECK" "DETAIL"
    printf "  ${DIM}%-4s %-22s %s${RESET}\n" "" "─────────────────────" "──────────────────────────────"
    for row in "${results[@]}"; do
        IFS='|' read -r sym label detail <<< "$row"
        printf "  %-4b %-22s %s\n" "$sym" "$label" "$detail"
    done

    echo ""
    echo -e "  ${BOLD}Results:${RESET} ${GREEN}${pass} passed${RESET}, ${RED}${fail} failed${RESET}"

    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo ""
        echo -e "  ${YELLOW}${BOLD}Warnings during install:${RESET}"
        for err in "${ERRORS[@]}"; do
            echo -e "    ${SYM_FAIL} ${err}"
        done
    fi

    if [[ $fail -eq 0 && ${#ERRORS[@]} -eq 0 ]]; then
        echo ""
        echo -e "  ${GREEN}${BOLD}🎉 All checks passed — environment is ready!${RESET}"
    else
        echo ""
        echo -e "  ${YELLOW}${BOLD}⚠  Some checks failed. Review the output above.${RESET}"
    fi
}

# ===========================  MAIN  =========================================

main() {
    banner
    detect_os

    install_prerequisites
    install_docker
    install_node
    install_python
    install_uv
    start_docker
    docker_compose_up
    install_opencode
    install_openspec
    deploy_mcp_config
    deploy_opencode_config
    deploy_caveman_prompt

    verify

    echo ""
    echo -e "${DIM}Bootstrap complete. Log out and back in if you were added to the docker group.${RESET}"
    echo ""
}

main "$@"
