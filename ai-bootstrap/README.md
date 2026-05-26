# 🧠 AI Bootstrap

> One command to set up your entire AI development workflow — on **macOS**, **Windows**, or **Ubuntu**.

Installs and configures a local AI stack: **Ollama + Qwen 3 27B**, **Serena MCP** (code intelligence), **OpenSpec MCP** (spec-driven development), **OpenCode CLI** with **custom agents**, and **Claude Code** integration — all wired together.

---

## Quick Start

### macOS / Ubuntu

```bash
git clone https://github.com/YOUR_USERNAME/ai-bootstrap.git
cd ai-bootstrap
chmod +x bootstrap.sh
./bootstrap.sh
```

### Windows (PowerShell — Run as Administrator)

```powershell
git clone https://github.com/YOUR_USERNAME/ai-bootstrap.git
cd ai-bootstrap
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\bootstrap.ps1
```

---

## What Gets Installed

| Component | Description | Method |
|-----------|-------------|--------|
| **Docker** | Container runtime for Ollama | Homebrew / apt / winget |
| **Ollama** | Local LLM server | Docker Compose |
| **Qwen 3 27B** | Local reasoning model | Auto-pulled by Ollama |
| **Node.js 20+** | Runtime for MCP servers & OpenCode | Homebrew / NodeSource / winget |
| **Python 3.10+** | Required by Serena | Homebrew / apt / winget |
| **uv** | Fast Python package manager | Homebrew / curl / pip |
| **OpenCode CLI** | Terminal AI coding agent | npm |
| **OpenSpec CLI** | Spec-driven development framework | npm |
| **Serena MCP** | LSP-powered code intelligence server | Runs via uvx (auto-installed) |

---

## What Gets Configured

### Claude Code (`~/.claude.json`)

MCP servers are merged into your existing Claude Code config:
- **Serena** — symbol-level code navigation, find references, semantic editing
- **OpenSpec** — structured proposals, designs, and task tracking

### OpenCode (`~/.config/opencode/opencode.json`)

Same MCP servers configured for OpenCode's client.

### OpenCode Agents (`~/.config/opencode/agents/`)

Six custom agents are deployed for a full team workflow:

| Agent | Role | Scope |
|-------|------|-------|
| **orchestrator** | Assigns work, routes handoffs, escalates to human | Coordination only — no code |
| **backend** | Builds server-side code | `app/api/` |
| **frontend** | Builds client-side code | Components, pages, styles |
| **critic** | Reviews diffs for architecture & edge cases | Sends feedback → builder revises |
| **infra** | CI/CD, deploy scripts, infrastructure | `/infra`, `/scripts` — self-reviews |
| **quality** | Writes tests, updates documentation | End of pipeline |

All agents use `openrouter/qwen/qwen-2.5-72b-instruct` at temperature `0.2`.

**Pipeline:** `orchestrator` → `builder` (backend/frontend) → `critic` → `builder` (revision) → `quality`

### Caveman Prompt (`~/.claude/commands/caveman.md`)

A minimalist Claude Code skill — terse, code-first, no-fluff responses.

---

## Updating Agents

After modifying agent files in `agents/`, use the standalone update script to push changes:

### macOS / Ubuntu

```bash
chmod +x update-agents.sh
./update-agents.sh          # deploy changes
./update-agents.sh --dry-run  # preview only
```

### Windows

```powershell
.\update-agents.ps1           # deploy changes
.\update-agents.ps1 -DryRun   # preview only
```

The update script:
- Compares source to target using file hashes
- Skips unchanged files
- Reports what was updated

---

## Project Structure

```
ai-bootstrap/
├── bootstrap.sh              # Mac/Ubuntu install script
├── bootstrap.ps1             # Windows PowerShell install script
├── update-agents.sh          # Mac/Ubuntu agent updater
├── update-agents.ps1         # Windows agent updater
├── docker-compose.yml        # Ollama + Qwen 3 27B
├── agents/
│   ├── orchestrator.md       # Coordinator — assigns & routes work
│   ├── backend.md            # Backend builder (app/api/)
│   ├── frontend.md           # Frontend builder (UI)
│   ├── critic.md             # Code reviewer (architecture + edge cases)
│   ├── infra.md              # Infrastructure (CI/CD, deploy, self-reviews)
│   └── quality.md            # Tests & documentation
├── configs/
│   ├── mcp_settings.json     # Claude Code MCP servers
│   ├── opencode.json         # OpenCode MCP client config
│   └── caveman_prompt.txt    # Claude Code skill prompt
├── .gitignore
└── README.md
```

---

## Architecture

```
                    ┌─────────────────┐
                    │   Orchestrator   │
                    │  (routes work)   │
                    └───┬─────┬───┬───┘
                        │     │   │
              ┌─────────┘     │   └─────────┐
              ▼               ▼             ▼
        ┌──────────┐   ┌──────────┐   ┌──────────┐
        │ Backend  │   │ Frontend │   │  Infra   │
        │ Builder  │   │ Builder  │   │(self-rev)│
        └────┬─────┘   └────┬─────┘   └──────────┘
             │               │
             ▼               ▼
        ┌────────────────────────┐
        │        Critic          │
        │  (reviews → feedback)  │
        └──────────┬─────────────┘
                   │ (revision loop)
                   ▼
        ┌────────────────────────┐
        │       Quality          │
        │  (tests + docs)        │
        └────────────────────────┘

MCP Clients                    MCP Servers               Local LLM
┌──────────────┐               ┌──────────────┐          ┌──────────────┐
│  Claude Code │──connects──▶  │   Serena     │          │   Ollama     │
│  OpenCode    │──connects──▶  │   OpenSpec   │          │  Qwen 3 27B │
└──────────────┘               └──────────────┘          └──────────────┘
```

---

## Usage

### Verify Installation

```bash
# Check Ollama
curl http://localhost:11434/api/tags

# Check Claude Code MCP servers
claude /mcp

# Check OpenCode MCP servers + agents
opencode  # then type MCPS in the TUI
```

### Using Local Qwen 3 27B

```bash
curl http://localhost:11434/api/chat -d '{
  "model": "qwen3:27b",
  "messages": [{"role": "user", "content": "Hello!"}]
}'
```

---

## Troubleshooting

### Docker Issues

```bash
# Mac
open -a Docker

# Ubuntu
sudo systemctl start docker

# Windows
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
```

### GPU Not Detected

- Ensure NVIDIA drivers and `nvidia-container-toolkit` are installed
- Mac: Docker cannot access Apple Silicon GPU — Ollama runs on CPU in Docker
- Consider native Ollama on Mac: `brew install ollama`

### Windows: Serena "spawn ENOENT"

The bootstrap script automatically uses the `cmd /c` wrapper. If manually configuring:
```json
{"command": "cmd", "args": ["/c", "uvx", "--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--context", "claude-code", "--project-from-cwd"]}
```

---

## Uninstall

```bash
# Stop Ollama
docker compose down -v

# Remove CLIs
npm uninstall -g opencode-ai @fission-ai/openspec

# Remove configs
rm ~/.claude/commands/caveman.md
rm -rf ~/.config/opencode/agents/
rm ~/.config/opencode/opencode.json
```

---

## License

MIT
