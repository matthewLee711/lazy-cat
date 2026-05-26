#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# update-agents.sh — Update OpenCode agent definitions
# Copies agent .md files from this repo to ~/.config/opencode/agents/
# Supports: macOS and Ubuntu/Debian
# Usage:    ./update-agents.sh [--dry-run] [--help]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="${SCRIPT_DIR}/agents"
AGENTS_DEST="$HOME/.config/opencode/agents"

# ── Colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

DRY_RUN=false

# ── Parse args ───────────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            echo -e "${BOLD}Usage:${RESET} ./update-agents.sh [--dry-run] [--help]"
            echo ""
            echo "  Copies agent .md files from ./agents/ to ~/.config/opencode/agents/"
            echo "  Overwrites existing files. Safe to re-run."
            echo ""
            echo "  --dry-run   Preview changes without writing files"
            echo "  --help      Show this message"
            exit 0
            ;;
        *) echo -e "${RED}Unknown option: $arg${RESET}"; exit 1 ;;
    esac
done

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║       OpenCode Agent Updater                     ║${RESET}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════╝${RESET}"
echo ""

if $DRY_RUN; then
    echo -e "  ${YELLOW}${BOLD}▶ DRY-RUN MODE${RESET}"
    echo ""
fi

# ── Validate source ─────────────────────────────────────────────────────────
if [[ ! -d "$AGENTS_SRC" ]]; then
    echo -e "  ${RED}✗ Source directory not found: ${AGENTS_SRC}${RESET}"
    exit 1
fi

agent_files=("$AGENTS_SRC"/*.md)
if [[ ${#agent_files[@]} -eq 0 ]]; then
    echo -e "  ${RED}✗ No .md files found in ${AGENTS_SRC}${RESET}"
    exit 1
fi

echo -e "  ${DIM}Source:${RESET}  ${AGENTS_SRC}"
echo -e "  ${DIM}Target:${RESET}  ${AGENTS_DEST}"
echo ""

# ── Create target directory ─────────────────────────────────────────────────
if [[ ! -d "$AGENTS_DEST" ]]; then
    if $DRY_RUN; then
        echo -e "  ${DIM}[dry-run] Would create ${AGENTS_DEST}${RESET}"
    else
        mkdir -p "$AGENTS_DEST"
        echo -e "  ${GREEN}✓${RESET} Created ${AGENTS_DEST}"
    fi
fi

# ── Copy each agent file ────────────────────────────────────────────────────
updated=0
skipped=0

for src_file in "${agent_files[@]}"; do
    filename="$(basename "$src_file")"
    dest_file="${AGENTS_DEST}/${filename}"

    # Check if target is identical (skip if unchanged)
    if [[ -f "$dest_file" ]]; then
        if diff -q "$src_file" "$dest_file" &>/dev/null; then
            echo -e "  ${CYAN}─${RESET}  ${filename} (unchanged)"
            skipped=$((skipped + 1))
            continue
        fi
    fi

    if $DRY_RUN; then
        if [[ -f "$dest_file" ]]; then
            echo -e "  ${DIM}[dry-run] Would update ${filename}${RESET}"
        else
            echo -e "  ${DIM}[dry-run] Would create ${filename}${RESET}"
        fi
    else
        cp "$src_file" "$dest_file"
        if [[ -f "$dest_file" ]]; then
            echo -e "  ${GREEN}✓${RESET}  ${filename} (updated)"
        else
            echo -e "  ${GREEN}✓${RESET}  ${filename} (created)"
        fi
    fi
    updated=$((updated + 1))
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Summary:${RESET} ${GREEN}${updated} updated${RESET}, ${CYAN}${skipped} unchanged${RESET}"
echo ""
