#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# bootstrap.sh — Master AI development environment installer
# Supports: macOS (Homebrew) and Ubuntu/Debian (apt)
#
# Usage:
#   ./bootstrap.sh [--dry-run] [--help]
#
# Flags:
#   --dry-run   Preview what would be installed without making changes
#   --help      Show usage information and exit
#
# This script is idempotent — safe to re-run at any time.
###############################################################################

# ---------------------------------------------------------------------------
# Resolve SCRIPT_DIR (works regardless of symlinks or invocation path)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Color & symbol helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

SYM_OK="${GREEN}✓${RESET}"
SYM_FAIL="${RED}✗${RESET}"
SYM_WORK="${YELLOW}⟳${RESET}"
SYM_SKIP="${CYAN}»${RESET}"

info()    { echo -e "  ${SYM_WORK}  ${BOLD}$1${RESET}"; }
success() { echo -e "  ${SYM_OK}  $1"; }
skip()    { echo -e "  ${SYM_SKIP}  $1 ${CYAN}(already installed)${RESET}"; }
fail()    { echo -e "  ${SYM_FAIL}  ${RED}$1${RESET}"; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${RESET}"; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: bootstrap.sh [OPTIONS]

Master installer for the AI development environment.
Detects macOS vs Ubuntu/Debian and installs all required tooling.

Options:
  --dry-run   Preview every step without making changes
  --help, -h  Show this help message and exit

Install sequence:
   1. Prerequisites (Homebrew / apt essentials)
   2. Docker
   3. Node.js 20+
   4. Python 3.10+
   5. uv (Python package manager)
   6. Start Docker daemon
   7. Docker Compose up (Ollama)
   8. OpenCode CLI
   9. OpenSpec CLI
  10. Deploy MCP config (~/.claude.json)
  11. Deploy OpenCode config (~/.config/opencode/opencode.json)
  12. Deploy caveman prompt (~/.claude/commands/caveman.md)
  13. Deploy OpenCode agents (~/.config/opencode/agents/)

The script is idempotent — safe to re-run at any time.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Run with --help for usage information."
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Dry-run wrapper — executes or just prints the command
# ---------------------------------------------------------------------------
run() {
  if $DRY_RUN; then
    echo -e "      ${YELLOW}[dry-run]${RESET} $*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux)
      if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "$ID" in
          ubuntu|debian|pop|linuxmint|elementary|zorin) OS="ubuntu" ;;
          *)
            echo "Unsupported Linux distribution: $ID"
            echo "This script supports Ubuntu, Debian, and their derivatives."
            exit 1
            ;;
        esac
      else
        echo "Cannot detect Linux distribution (missing /etc/os-release)."
        exit 1
      fi
      ;;
    *)
      echo "Unsupported OS: $(uname -s)"
      exit 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
banner() {
  echo -e "${BOLD}${CYAN}"
  cat <<'ART'
    ╔══════════════════════════════════════════════════╗
    ║       AI Development Environment Bootstrap      ║
    ╚══════════════════════════════════════════════════╝
ART
  echo -e "${RESET}"
  echo -e "  OS detected : ${BOLD}${OS}${RESET}"
  if $DRY_RUN; then
    echo -e "  Mode        : ${YELLOW}${BOLD}DRY RUN (no changes will be made)${RESET}"
  fi
  echo ""
}

# ===========================================================================
# Step 1 — Prerequisites
# ===========================================================================
install_prerequisites() {
  section "Step 1 · Prerequisites"

  if [ "$OS" = "macos" ]; then
    # Xcode Command Line Tools
    if xcode-select -p &>/dev/null; then
      skip "Xcode Command Line Tools"
    else
      info "Installing Xcode Command Line Tools …"
      run xcode-select --install || true
      success "Xcode Command Line Tools install triggered"
    fi

    # Homebrew
    if command -v brew &>/dev/null; then
      skip "Homebrew"
    else
      info "Installing Homebrew …"
      run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      # Ensure brew is on PATH for the rest of this session
      if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [ -f /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
      success "Homebrew installed"
    fi

  else
    # Ubuntu / Debian
    info "Updating apt package index …"
    run sudo apt update -y
    info "Installing curl, git, build-essential …"
    run sudo apt install -y curl git build-essential
    success "apt prerequisites installed"
  fi
}

# ===========================================================================
# Step 2 — Docker
# ===========================================================================
install_docker() {
  section "Step 2 · Docker"

  if command -v docker &>/dev/null; then
    skip "Docker"
  else
    info "Installing Docker …"
    if [ "$OS" = "macos" ]; then
      run brew install --cask docker
    else
      run sudo apt install -y docker.io docker-compose-plugin
      run sudo systemctl enable --now docker
      run sudo usermod -aG docker "$USER"
      echo -e "      ${YELLOW}NOTE: You may need to log out and back in for Docker group membership to take effect.${RESET}"
    fi
    success "Docker installed"
  fi
}

# ===========================================================================
# Step 3 — Node.js 20+
# ===========================================================================
install_node() {
  section "Step 3 · Node.js 20+"

  if command -v node &>/dev/null; then
    NODE_VER="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
    if [ "${NODE_VER:-0}" -ge 20 ]; then
      skip "Node.js $(node --version)"
    else
      info "Node.js $(node --version) found but is below v20 — upgrading …"
      if [ "$OS" = "macos" ]; then
        run brew install node
      else
        run bash -c 'curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -'
        run sudo apt install -y nodejs
      fi
      success "Node.js upgraded to $(node --version 2>/dev/null || echo 'latest')"
    fi
  else
    info "Installing Node.js …"
    if [ "$OS" = "macos" ]; then
      run brew install node
    else
      run bash -c 'curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -'
      run sudo apt install -y nodejs
    fi
    success "Node.js installed"
  fi
}

# ===========================================================================
# Step 4 — Python 3.10+
# ===========================================================================
install_python() {
  section "Step 4 · Python 3.10+"

  if command -v python3 &>/dev/null; then
    PY_VER="$(python3 --version 2>/dev/null | awk '{print $2}')"
    PY_MINOR="$(echo "$PY_VER" | cut -d. -f2)"
    if [ "${PY_MINOR:-0}" -ge 10 ]; then
      skip "Python ${PY_VER}"
    else
      info "Python ${PY_VER} found but is below 3.10 — upgrading …"
      if [ "$OS" = "macos" ]; then
        run brew install python
      else
        run sudo apt install -y python3 python3-pip python3-venv
      fi
      success "Python upgraded"
    fi
  else
    info "Installing Python …"
    if [ "$OS" = "macos" ]; then
      run brew install python
    else
      run sudo apt install -y python3 python3-pip python3-venv
    fi
    success "Python installed"
  fi
}

# ===========================================================================
# Step 5 — uv (Python package manager)
# ===========================================================================
install_uv() {
  section "Step 5 · uv"

  if command -v uv &>/dev/null; then
    skip "uv $(uv --version 2>/dev/null || true)"
  else
    info "Installing uv …"
    if [ "$OS" = "macos" ]; then
      run brew install uv
    else
      run bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
      # Source cargo env if uv was installed to ~/.cargo/bin
      if [ -f "$HOME/.cargo/env" ]; then
        # shellcheck disable=SC1091
        source "$HOME/.cargo/env"
      fi
    fi
    success "uv installed"
  fi
}

# ===========================================================================
# Step 6 — Start Docker daemon
# ===========================================================================
start_docker() {
  section "Step 6 · Start Docker daemon"

  if docker info &>/dev/null 2>&1; then
    skip "Docker daemon running"
    return
  fi

  if [ "$OS" = "macos" ]; then
    info "Starting Docker Desktop …"
    run open -a Docker

    if ! $DRY_RUN; then
      echo -n "      Waiting for Docker daemon "
      local retries=0
      local max_retries=60
      while ! docker info &>/dev/null 2>&1; do
        echo -n "."
        sleep 3
        retries=$((retries + 1))
        if [ "$retries" -ge "$max_retries" ]; then
          echo ""
          fail "Docker daemon did not start within 3 minutes"
          echo -e "      ${YELLOW}Please start Docker Desktop manually and re-run this script.${RESET}"
          return 1
        fi
      done
      echo ""
      success "Docker daemon is running"
    fi
  else
    # systemctl should have started it in step 2
    info "Starting Docker via systemctl …"
    run sudo systemctl start docker
    success "Docker daemon started"
  fi
}

# ===========================================================================
# Step 7 — Docker Compose up (Ollama)
# ===========================================================================
docker_compose_up() {
  section "Step 7 · Docker Compose up (Ollama)"

  local compose_file="${SCRIPT_DIR}/docker-compose.yml"
  if [ ! -f "$compose_file" ] && [ ! -f "${SCRIPT_DIR}/docker-compose.yaml" ] && [ ! -f "${SCRIPT_DIR}/compose.yml" ] && [ ! -f "${SCRIPT_DIR}/compose.yaml" ]; then
    fail "No docker-compose file found in ${SCRIPT_DIR}"
    echo -e "      ${YELLOW}Skipping Docker Compose — create a compose file and re-run.${RESET}"
    return 0
  fi

  info "Running docker compose up -d …"
  run docker compose -f "$compose_file" up -d 2>/dev/null || run docker compose up -d
  success "Docker Compose services started"
}

# ===========================================================================
# Step 8 — OpenCode CLI
# ===========================================================================
install_opencode() {
  section "Step 8 · OpenCode CLI"

  if command -v opencode &>/dev/null; then
    skip "opencode $(opencode --version 2>/dev/null || true)"
  else
    info "Installing opencode-ai globally via npm …"
    run npm install -g opencode-ai
    success "OpenCode CLI installed"
  fi
}

# ===========================================================================
# Step 9 — OpenSpec CLI
# ===========================================================================
install_openspec() {
  section "Step 9 · OpenSpec CLI"

  if command -v openspec &>/dev/null; then
    skip "openspec"
  else
    info "Installing @fission-ai/openspec globally via npm …"
    run npm install -g @fission-ai/openspec@latest
    success "OpenSpec CLI installed"
  fi
}

# ===========================================================================
# Step 10 — Deploy MCP config (~/.claude.json)
# ===========================================================================
deploy_mcp_config() {
  section "Step 10 · Deploy MCP config"

  local src="${SCRIPT_DIR}/configs/mcp_settings.json"
  local dest="$HOME/.claude.json"

  if [ ! -f "$src" ]; then
    fail "Source config not found: ${src}"
    return 0
  fi

  info "Merging MCP settings into ${dest} …"

  if $DRY_RUN; then
    echo -e "      ${YELLOW}[dry-run]${RESET} Would merge ${src} into ${dest}"
    return
  fi

  # Choose a JSON merge strategy — prefer python3, fall back to jq
  if command -v python3 &>/dev/null; then
    python3 - "$src" "$dest" <<'PYMERGE'
import json, sys, os

src_path, dest_path = sys.argv[1], sys.argv[2]

with open(src_path) as f:
    src_data = json.load(f)

new_servers = src_data.get("mcpServers", {})

if os.path.isfile(dest_path):
    with open(dest_path) as f:
        dest_data = json.load(f)
else:
    dest_data = {}

if "mcpServers" not in dest_data:
    dest_data["mcpServers"] = {}

# Merge: only add servers that don't already exist (don't overwrite)
for name, cfg in new_servers.items():
    if name not in dest_data["mcpServers"]:
        dest_data["mcpServers"][name] = cfg

with open(dest_path, "w") as f:
    json.dump(dest_data, f, indent=2)
    f.write("\n")
PYMERGE
    success "MCP config merged into ${dest}"

  elif command -v jq &>/dev/null; then
    if [ ! -f "$dest" ]; then
      # No existing file — just wrap mcpServers from source
      jq '{mcpServers: .mcpServers}' "$src" > "$dest"
    else
      # Merge: existing servers take precedence (we use * with existing on the right)
      local tmp
      tmp="$(mktemp)"
      jq -s '.[0] as $new | .[1] as $old |
        $old + { mcpServers: (($new.mcpServers // {}) + ($old.mcpServers // {})) }
      ' "$src" "$dest" > "$tmp" && mv "$tmp" "$dest"
    fi
    success "MCP config merged into ${dest}"

  else
    fail "Neither python3 nor jq found — cannot merge JSON"
    return 1
  fi
}

# ===========================================================================
# Step 11 — Deploy OpenCode config
# ===========================================================================
deploy_opencode_config() {
  section "Step 11 · Deploy OpenCode config"

  local src="${SCRIPT_DIR}/configs/opencode.json"
  local dest_dir="$HOME/.config/opencode"
  local dest="${dest_dir}/opencode.json"

  if [ ! -f "$src" ]; then
    fail "Source config not found: ${src}"
    return 0
  fi

  info "Deploying OpenCode config to ${dest} …"
  run mkdir -p "$dest_dir"
  run cp "$src" "$dest"
  success "OpenCode config deployed"
}

# ===========================================================================
# Step 12 — Deploy caveman prompt
# ===========================================================================
deploy_caveman_prompt() {
  section "Step 12 · Deploy caveman prompt"

  local src="${SCRIPT_DIR}/configs/caveman_prompt.txt"
  local dest_dir="$HOME/.claude/commands"
  local dest="${dest_dir}/caveman.md"

  if [ ! -f "$src" ]; then
    fail "Source prompt not found: ${src}"
    return 0
  fi

  info "Deploying caveman prompt to ${dest} …"
  run mkdir -p "$dest_dir"
  run cp "$src" "$dest"
  success "Caveman prompt deployed"
}

# ===========================================================================
# Step 13 — Deploy OpenCode agents
# ===========================================================================
deploy_agents() {
  section "Step 13 · Deploy OpenCode agents"

  local src_dir="${SCRIPT_DIR}/agents"
  local dest_dir="$HOME/.config/opencode/agents"

  if [ ! -d "$src_dir" ]; then
    fail "Agents directory not found: ${src_dir}"
    return 0
  fi

  # Check for .md files
  local md_files
  md_files=("$src_dir"/*.md)
  if [ ! -e "${md_files[0]}" ]; then
    fail "No .md files found in ${src_dir}"
    return 0
  fi

  info "Deploying agent files to ${dest_dir} …"
  run mkdir -p "$dest_dir"

  for f in "${md_files[@]}"; do
    local basename
    basename="$(basename "$f")"
    run cp "$f" "${dest_dir}/${basename}"
    if $DRY_RUN; then
      : # dry-run message already printed by run()
    else
      echo -e "      copied ${BOLD}${basename}${RESET}"
    fi
  done

  success "All agent files deployed (${#md_files[@]} files)"
}

# ===========================================================================
# Post-install verification
# ===========================================================================
verify() {
  section "Post-Install Verification"

  local checks=()
  local results=()

  # Helper: run a check, record pass/fail
  check() {
    local label="$1"
    shift
    checks+=("$label")
    if "$@" &>/dev/null 2>&1; then
      results+=("pass")
    else
      results+=("fail")
    fi
  }

  check_file() {
    local label="$1"
    local path="$2"
    checks+=("$label")
    if [ -f "$path" ]; then
      results+=("pass")
    else
      results+=("fail")
    fi
  }

  check_dir_has_md() {
    local label="$1"
    local dir="$2"
    checks+=("$label")
    if [ -d "$dir" ] && ls "$dir"/*.md &>/dev/null 2>&1; then
      results+=("pass")
    else
      results+=("fail")
    fi
  }

  check "Docker running"               docker info
  check "Ollama responding"             curl -sf http://localhost:11434/api/tags
  check "Node.js"                       node --version
  check "Python 3"                      python3 --version
  check "uv"                            uv --version
  check "OpenCode CLI"                  opencode --version
  check_file "~/.claude.json"           "$HOME/.claude.json"
  check_file "OpenCode config"          "$HOME/.config/opencode/opencode.json"
  check_file "Caveman prompt"           "$HOME/.claude/commands/caveman.md"
  check_dir_has_md "Agent files"        "$HOME/.config/opencode/agents"

  # Print summary table
  echo ""
  echo -e "  ${BOLD}┌──────────────────────────────┬────────┐${RESET}"
  echo -e "  ${BOLD}│ Check                        │ Status │${RESET}"
  echo -e "  ${BOLD}├──────────────────────────────┼────────┤${RESET}"

  local pass_count=0
  local total=${#checks[@]}

  for i in "${!checks[@]}"; do
    local name="${checks[$i]}"
    local result="${results[$i]}"
    # Pad name to 28 chars
    local padded
    padded="$(printf '%-28s' "$name")"
    if [ "$result" = "pass" ]; then
      echo -e "  │ ${padded} │ ${GREEN}  ✓   ${RESET}│"
      pass_count=$((pass_count + 1))
    else
      echo -e "  │ ${padded} │ ${RED}  ✗   ${RESET}│"
    fi
  done

  echo -e "  ${BOLD}└──────────────────────────────┴────────┘${RESET}"
  echo ""
  echo -e "  ${BOLD}${pass_count}/${total} checks passed${RESET}"

  if [ "$pass_count" -lt "$total" ]; then
    echo -e "  ${YELLOW}Some checks failed — review the output above for details.${RESET}"
  else
    echo -e "  ${GREEN}${BOLD}All checks passed — environment is ready! 🚀${RESET}"
  fi
  echo ""
}

# ===========================================================================
# Main
# ===========================================================================
main() {
  detect_os
  banner

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
  deploy_agents

  if ! $DRY_RUN; then
    verify
  else
    echo ""
    echo -e "  ${YELLOW}${BOLD}Dry run complete — no changes were made.${RESET}"
    echo -e "  ${YELLOW}Run without --dry-run to install everything.${RESET}"
    echo ""
  fi
}

main
