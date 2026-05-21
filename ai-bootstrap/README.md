# 🧠 AI Bootstrap

> One command to set up your entire AI development workflow — on **macOS**, **Windows**, or **Ubuntu**.

Installs and configures a local AI stack: **Ollama + Qwen 3 27B**, **Serena MCP** (code intelligence), **OpenSpec MCP** (spec-driven development), **OpenCode CLI**, and **Claude Code** integration — all wired together.

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

Same MCP servers configured for OpenCode's client:
- Serena and OpenSpec available in the OpenCode TUI

### Caveman Prompt (`~/.claude/commands/caveman.md`)

A minimalist Claude Code skill that makes Claude:
- Lead with code, not commentary
- Be terse and direct
- Act autonomously on clear intent
- Never apologize or hedge

---

## Project Structure

```
ai-bootstrap/
├── bootstrap.sh            # Mac/Ubuntu install script
├── bootstrap.ps1           # Windows PowerShell install script
├── docker-compose.yml      # Ollama + Qwen 3 27B
├── configs/
│   ├── mcp_settings.json   # Claude Code MCP servers
│   ├── opencode.json       # OpenCode MCP client config
│   └── caveman_prompt.txt  # Claude Code skill prompt
└── README.md               # This file
```

---

## Architecture

```
┌─────────────────────────────────────────────┐
│              MCP Clients                     │
│  ┌──────────────┐  ┌──────────────────────┐ │
│  │  Claude Code  │  │    OpenCode CLI      │ │
│  └──────┬───────┘  └──────────┬───────────┘ │
│         │                     │              │
│         ▼                     ▼              │
│  ┌─────────────────────────────────────────┐ │
│  │           MCP Servers                   │ │
│  │  ┌─────────────┐  ┌──────────────────┐ │ │
│  │  │   Serena    │  │    OpenSpec      │ │ │
│  │  │ (Code Intel)│  │ (Spec-Driven)   │ │ │
│  │  └─────────────┘  └──────────────────┘ │ │
│  └─────────────────────────────────────────┘ │
│                                              │
│  ┌─────────────────────────────────────────┐ │
│  │         Local LLM (Docker)              │ │
│  │  ┌─────────────────────────────────┐    │ │
│  │  │  Ollama → Qwen 3 27B           │    │ │
│  │  │  http://localhost:11434         │    │ │
│  │  └─────────────────────────────────┘    │ │
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

---

## Usage

### Verify Installation

After running the bootstrap script, verify everything is working:

```bash
# Check Ollama is running
curl http://localhost:11434/api/tags

# Check model is available
curl http://localhost:11434/api/generate -d '{"model":"qwen3:27b","prompt":"Say hello","stream":false}'

# Check Claude Code MCP servers
claude /mcp

# Check OpenCode MCP servers
opencode  # then type MCPS in the TUI
```

### Using with Claude Code

```bash
cd your-project
claude
# Serena and OpenSpec MCP servers auto-connect
# Use /mcp to verify
```

### Using with OpenCode

```bash
cd your-project
opencode
# Type MCPS to see connected MCP servers
```

### Using Local Qwen 3 27B

The Ollama server is available at `http://localhost:11434`. You can use it with any tool that supports the Ollama API:

```bash
# Direct API
curl http://localhost:11434/api/chat -d '{
  "model": "qwen3:27b",
  "messages": [{"role": "user", "content": "Hello!"}]
}'

# Or configure OpenCode to use it
# Add to opencode.json:
# "provider": { "ollama": { "options": { "baseURL": "http://localhost:11434" } } }
```

---

## Configuration

### Customize MCP Servers

Edit `configs/mcp_settings.json` and re-run the bootstrap script to update Claude Code's config.

### Customize Ollama

Edit `docker-compose.yml` to:
- Change the model (replace `qwen3:27b` with any [Ollama model](https://ollama.com/library))
- Adjust GPU allocation
- Change the port

Then restart:
```bash
docker compose down && docker compose up -d
```

### Customize Caveman Prompt

Edit `configs/caveman_prompt.txt` and re-run bootstrap, or edit `~/.claude/commands/caveman.md` directly.

---

## Troubleshooting

### Docker Issues

**Docker daemon not running:**
```bash
# Mac
open -a Docker

# Ubuntu
sudo systemctl start docker

# Windows
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
```

**GPU not detected in Docker:**
- Ensure NVIDIA drivers and `nvidia-container-toolkit` are installed
- On Mac: Docker cannot access Apple Silicon GPU — Ollama runs on CPU in Docker
- Consider native Ollama install on Mac for GPU: `brew install ollama`

### Model Download Stuck

The Qwen 3 27B model is ~16GB. On slow connections:
```bash
# Check download progress
docker logs -f ollama-pull

# Or pull manually
docker exec -it ollama ollama pull qwen3:27b
```

### MCP Server Not Connecting

```bash
# Verify Serena
uvx --from git+https://github.com/oraios/serena serena --help

# Verify OpenSpec
npx -y @fission-ai/openspec-mcp --help

# Check Claude Code config
cat ~/.claude.json | python3 -m json.tool
```

### Windows: Serena "spawn ENOENT" Error

Ensure the Serena config uses the `cmd /c` wrapper. The bootstrap script handles this automatically, but if manually configuring:
```json
{
  "command": "cmd",
  "args": ["/c", "uvx", "--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--context", "claude-code", "--project-from-cwd"]
}
```

---

## Uninstall

```bash
# Stop and remove Ollama container + data
docker compose down -v

# Remove installed CLIs
npm uninstall -g opencode-ai @fission-ai/openspec

# Remove configs (optional)
rm ~/.claude/commands/caveman.md
rm ~/.config/opencode/opencode.json
# To remove MCP servers from Claude Code, edit ~/.claude.json manually
```

---

## Prerequisites

| Requirement | Mac | Ubuntu | Windows |
|------------|-----|--------|---------|
| Git | Xcode CLI Tools | `apt install git` | `winget install Git.Git` |
| Internet | For npm/Docker pulls | Same | Same |
| ~20GB disk | For Qwen 3 27B model | Same | Same |
| GPU (optional) | Apple Silicon (native only) | NVIDIA w/ drivers | NVIDIA w/ drivers |

---

## License

MIT
