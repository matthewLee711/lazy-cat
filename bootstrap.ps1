#Requires -Version 5.1
<#
.SYNOPSIS
    AI Bootstrap — Windows installer for the full AI development stack.

.DESCRIPTION
    Installs Git, Docker Desktop, Node.js, Python, uv, OpenCode CLI, OpenSpec CLI,
    deploys MCP/OpenCode/caveman configs, and starts Docker Compose services.
    Idempotent — safe to re-run. Checks for existing installations before acting.

.PARAMETER DryRun
    Preview all actions without making changes.

.PARAMETER Help
    Show usage information and exit.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────
$SCRIPT_VERSION = "1.0.0"
$CONFIGS_DIR    = Join-Path $PSScriptRoot "configs"

# ─────────────────────────────────────────────────────────────────────────────
# Output helpers
# ─────────────────────────────────────────────────────────────────────────────
function Write-Banner {
    $banner = @"

    ╔═══════════════════════════════════════════════════════════════╗
    ║              AI  B O O T S T R A P  (Windows)               ║
    ║                                                               ║
    ║   Git · Docker · Node · Python · uv · OpenCode · OpenSpec   ║
    ║                       v$SCRIPT_VERSION                              ║
    ╚═══════════════════════════════════════════════════════════════╝

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Write-Step    { param([string]$msg) Write-Host "  ► $msg"  -ForegroundColor Yellow }
function Write-Success { param([string]$msg) Write-Host "  ✓ $msg"  -ForegroundColor Green  }
function Write-Err     { param([string]$msg) Write-Host "  ✗ $msg"  -ForegroundColor Red    }
function Write-Info    { param([string]$msg) Write-Host "  ℹ $msg"  -ForegroundColor Cyan   }
function Write-Dry     { param([string]$msg) Write-Host "  ⏸ [DRY-RUN] $msg" -ForegroundColor Magenta }

function Write-Section {
    param([string]$title)
    Write-Host ""
    Write-Host "  ── $title ──" -ForegroundColor White
}

# ─────────────────────────────────────────────────────────────────────────────
# Help
# ─────────────────────────────────────────────────────────────────────────────
function Show-Help {
    Write-Banner
    Write-Host @"
  USAGE
      .\bootstrap.ps1 [-DryRun] [-Help]

  FLAGS
      -DryRun     Preview all actions without making any changes.
      -Help       Show this help message and exit.

  DESCRIPTION
      Installs and configures the full AI dev-stack on Windows:

        1.  Git                     (winget)
        2.  Docker Desktop          (winget)
        3.  Node.js 20+ LTS        (winget)
        4.  Python 3.12             (winget)
        5.  uv                      (astral installer)
        6.  Start Docker engine     (wait for readiness)
        7.  Docker Compose up       (docker compose up -d)
        8.  OpenCode CLI            (npm -g)
        9.  OpenSpec CLI            (npm -g)
       10.  Deploy MCP config       (merge into ~\.claude.json)
       11.  Deploy OpenCode config  (copy to ~\.config\opencode\)
       12.  Deploy caveman prompt   (copy to ~\.claude\commands\)

      The script requires Administrator privileges and will self-elevate
      if run from a non-elevated shell.

  EXAMPLES
      # Full install
      .\bootstrap.ps1

      # Preview only
      .\bootstrap.ps1 -DryRun
"@
}

if ($Help) {
    Show-Help
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Admin check & self-elevation
# ─────────────────────────────────────────────────────────────────────────────
function Assert-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Info "Not running as Administrator — attempting self-elevation..."
        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
        if ($DryRun) { $argList += "-DryRun" }
        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -Wait
        } catch {
            Write-Err "Failed to elevate. Please re-run as Administrator."
            exit 1
        }
        exit 0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# PATH refresh — picks up tools installed by winget in the current session
# ─────────────────────────────────────────────────────────────────────────────
function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath"
    Write-Info "PATH refreshed for current session."
}

# ─────────────────────────────────────────────────────────────────────────────
# Generic helpers
# ─────────────────────────────────────────────────────────────────────────────
function Test-CommandExists {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-ViaWinget {
    param(
        [string]$DisplayName,
        [string]$WingetId,
        [string]$TestCommand
    )

    Write-Section "Step: $DisplayName"

    # Check if already installed via the test command
    if ($TestCommand -and (Test-CommandExists $TestCommand)) {
        $ver = & $TestCommand --version 2>$null
        Write-Success "$DisplayName is already installed ($ver)."
        return
    }

    # Also check winget list as a fallback (tool may be installed but not on PATH yet)
    $wingetCheck = winget list --id $WingetId 2>$null
    if ($LASTEXITCODE -eq 0 -and $wingetCheck -match $WingetId) {
        Write-Success "$DisplayName is already installed (found via winget list)."
        return
    }

    if ($DryRun) {
        Write-Dry "Would install $DisplayName via: winget install --id $WingetId -e"
        return
    }

    Write-Step "Installing $DisplayName..."
    winget install --id $WingetId -e --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to install $DisplayName (exit code $LASTEXITCODE)."
        Write-Info "You may need to install $DisplayName manually."
    } else {
        Refresh-Path
        Write-Success "$DisplayName installed successfully."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 5 — uv
# ─────────────────────────────────────────────────────────────────────────────
function Install-Uv {
    Write-Section "Step 5: uv (Python package manager)"

    if (Test-CommandExists "uv") {
        $ver = uv --version 2>$null
        Write-Success "uv is already installed ($ver)."
        return
    }

    if ($DryRun) {
        Write-Dry "Would install uv via astral installer (irm https://astral.sh/uv/install.ps1 | iex)"
        return
    }

    Write-Step "Installing uv via astral installer..."
    try {
        $installerScript = Invoke-RestMethod "https://astral.sh/uv/install.ps1"
        Invoke-Expression $installerScript
        Refresh-Path

        # Also add common uv install location to PATH for this session
        $uvHome = Join-Path $env:USERPROFILE ".local\bin"
        if (Test-Path $uvHome) {
            $env:Path = "$uvHome;$env:Path"
        }
        $uvCargo = Join-Path $env:USERPROFILE ".cargo\bin"
        if (Test-Path $uvCargo) {
            $env:Path = "$uvCargo;$env:Path"
        }

        if (Test-CommandExists "uv") {
            Write-Success "uv installed successfully."
        } else {
            Write-Err "uv installed but not found on PATH. You may need to restart your shell."
        }
    } catch {
        Write-Err "Failed to install uv: $_"
        Write-Info "Try manually: pip install uv"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 6 — Start Docker Desktop & wait for engine
# ─────────────────────────────────────────────────────────────────────────────
function Start-DockerEngine {
    Write-Section "Step 6: Start Docker Engine"

    # Check if Docker is already running
    try {
        $dockerInfo = docker info 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Docker engine is already running."
            return
        }
    } catch { }

    if ($DryRun) {
        Write-Dry "Would start Docker Desktop and wait for engine readiness."
        return
    }

    # Locate Docker Desktop executable
    $dockerDesktopPaths = @(
        "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
        (Join-Path $env:LOCALAPPDATA "Docker\Docker Desktop.exe")
    )

    $dockerExe = $null
    foreach ($p in $dockerDesktopPaths) {
        if (Test-Path $p) { $dockerExe = $p; break }
    }

    if (-not $dockerExe) {
        Write-Err "Docker Desktop executable not found. Please start it manually."
        return
    }

    Write-Step "Starting Docker Desktop..."
    Start-Process -FilePath $dockerExe

    # Wait for engine readiness (up to 120 seconds)
    $maxWait = 120
    $waited  = 0
    $interval = 5
    Write-Info "Waiting for Docker engine to become ready (up to ${maxWait}s)..."
    while ($waited -lt $maxWait) {
        Start-Sleep -Seconds $interval
        $waited += $interval
        try {
            docker info 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Docker engine is ready (waited ${waited}s)."
                return
            }
        } catch { }
        Write-Host "    … waiting (${waited}s / ${maxWait}s)" -ForegroundColor DarkGray
    }

    Write-Err "Docker engine did not become ready within ${maxWait}s. Check Docker Desktop."
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 7 — Docker Compose up
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-DockerComposeUp {
    Write-Section "Step 7: Docker Compose up"

    $composeFile = Join-Path $PSScriptRoot "docker-compose.yml"
    if (-not (Test-Path $composeFile)) {
        $composeFile = Join-Path $PSScriptRoot "docker-compose.yaml"
    }
    if (-not (Test-Path $composeFile)) {
        Write-Info "No docker-compose.yml found in $PSScriptRoot — skipping."
        return
    }

    if ($DryRun) {
        Write-Dry "Would run: docker compose up -d (in $PSScriptRoot)"
        return
    }

    Write-Step "Running docker compose up -d..."
    Push-Location $PSScriptRoot
    try {
        docker compose up -d
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Docker Compose services started."
        } else {
            Write-Err "docker compose up -d failed (exit code $LASTEXITCODE)."
        }
    } catch {
        Write-Err "docker compose up -d failed: $_"
    } finally {
        Pop-Location
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 8/9 — npm global installs
# ─────────────────────────────────────────────────────────────────────────────
function Install-NpmGlobal {
    param(
        [string]$DisplayName,
        [string]$PackageName,
        [string]$TestCommand
    )

    Write-Section "Step: $DisplayName"

    if ($TestCommand -and (Test-CommandExists $TestCommand)) {
        $ver = & $TestCommand --version 2>$null
        Write-Success "$DisplayName is already installed ($ver)."
        return
    }

    if ($DryRun) {
        Write-Dry "Would install: npm install -g $PackageName"
        return
    }

    if (-not (Test-CommandExists "npm")) {
        Write-Err "npm not found — cannot install $DisplayName. Install Node.js first."
        return
    }

    Write-Step "Installing $DisplayName globally..."
    npm install -g $PackageName
    if ($LASTEXITCODE -eq 0) {
        Refresh-Path
        Write-Success "$DisplayName installed."
    } else {
        Write-Err "Failed to install $DisplayName (exit code $LASTEXITCODE)."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 10 — Deploy MCP config (merge into ~/.claude.json)
# ─────────────────────────────────────────────────────────────────────────────
function Deploy-McpConfig {
    Write-Section "Step 10: Deploy MCP config"

    $sourceFile = Join-Path $CONFIGS_DIR "mcp_settings.json"
    $targetFile = Join-Path $env:USERPROFILE ".claude.json"

    if (-not (Test-Path $sourceFile)) {
        Write-Err "Source MCP config not found: $sourceFile"
        return
    }

    if ($DryRun) {
        Write-Dry "Would merge $sourceFile into $targetFile"
        Write-Dry "Would apply Windows-specific Serena cmd /c wrapper"
        return
    }

    Write-Step "Deploying MCP config..."

    # Read the source MCP settings
    $sourceJson = Get-Content $sourceFile -Raw | ConvertFrom-Json

    # Apply Windows-specific Serena config (cmd /c wrapper to avoid ENOENT errors)
    if ($sourceJson.mcpServers -and $sourceJson.mcpServers.serena) {
        Write-Info "Applying Windows-specific Serena config (cmd /c wrapper)..."
        $sourceJson.mcpServers.serena = [PSCustomObject]@{
            command = "cmd"
            args    = @("/c", "uvx", "--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--context", "claude-code", "--project-from-cwd")
        }
    } else {
        # If serena not in source, add it explicitly
        Write-Info "Adding Windows-specific Serena config..."
        if (-not $sourceJson.mcpServers) {
            $sourceJson | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
        }
        $sourceJson.mcpServers | Add-Member -NotePropertyName "serena" -NotePropertyValue ([PSCustomObject]@{
            command = "cmd"
            args    = @("/c", "uvx", "--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--context", "claude-code", "--project-from-cwd")
        }) -Force
    }

    # Merge into target
    if (Test-Path $targetFile) {
        Write-Info "Existing .claude.json found — merging mcpServers..."
        try {
            $targetJson = Get-Content $targetFile -Raw | ConvertFrom-Json

            if (-not $targetJson.mcpServers) {
                $targetJson | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
            }

            # Merge each server from source into target (don't overwrite existing)
            $sourceServers = $sourceJson.mcpServers
            $sourceServers.PSObject.Properties | ForEach-Object {
                $serverName = $_.Name
                $serverConfig = $_.Value
                if (-not ($targetJson.mcpServers.PSObject.Properties.Name -contains $serverName)) {
                    Write-Info "  Adding MCP server: $serverName"
                    $targetJson.mcpServers | Add-Member -NotePropertyName $serverName -NotePropertyValue $serverConfig
                } else {
                    Write-Info "  MCP server '$serverName' already exists — skipping (won't overwrite)."
                }
            }

            $targetJson | ConvertTo-Json -Depth 20 | Set-Content $targetFile -Encoding UTF8
            Write-Success "MCP config merged into $targetFile"
        } catch {
            Write-Err "Failed to merge MCP config: $_"
            Write-Info "Backing up existing file and writing fresh config..."
            Copy-Item $targetFile "$targetFile.bak" -Force
            $sourceJson | ConvertTo-Json -Depth 20 | Set-Content $targetFile -Encoding UTF8
            Write-Success "Fresh MCP config written (backup at .claude.json.bak)."
        }
    } else {
        Write-Info "No existing .claude.json — creating fresh..."
        $sourceJson | ConvertTo-Json -Depth 20 | Set-Content $targetFile -Encoding UTF8
        Write-Success "MCP config created at $targetFile"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 11 — Deploy OpenCode config
# ─────────────────────────────────────────────────────────────────────────────
function Deploy-OpenCodeConfig {
    Write-Section "Step 11: Deploy OpenCode config"

    $sourceFile = Join-Path $CONFIGS_DIR "opencode.json"
    $targetDir  = Join-Path $env:USERPROFILE ".config\opencode"
    $targetFile = Join-Path $targetDir "opencode.json"

    if (-not (Test-Path $sourceFile)) {
        Write-Err "Source OpenCode config not found: $sourceFile"
        return
    }

    if ($DryRun) {
        Write-Dry "Would copy $sourceFile → $targetFile"
        return
    }

    Write-Step "Deploying OpenCode config..."
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    Copy-Item $sourceFile $targetFile -Force
    Write-Success "OpenCode config deployed to $targetFile"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 12 — Deploy caveman prompt
# ─────────────────────────────────────────────────────────────────────────────
function Deploy-CavemanPrompt {
    Write-Section "Step 12: Deploy caveman prompt"

    $sourceFile = Join-Path $CONFIGS_DIR "caveman_prompt.txt"
    $targetDir  = Join-Path $env:USERPROFILE ".claude\commands"
    $targetFile = Join-Path $targetDir "caveman.md"

    if (-not (Test-Path $sourceFile)) {
        Write-Err "Source caveman prompt not found: $sourceFile"
        return
    }

    if ($DryRun) {
        Write-Dry "Would copy $sourceFile → $targetFile"
        return
    }

    Write-Step "Deploying caveman prompt..."
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    Copy-Item $sourceFile $targetFile -Force
    Write-Success "Caveman prompt deployed to $targetFile"
}

# ─────────────────────────────────────────────────────────────────────────────
# Post-install verification
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-PostInstallVerification {
    Write-Host ""
    Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor White
    Write-Host "   POST-INSTALL VERIFICATION" -ForegroundColor Cyan
    Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor White
    Write-Host ""

    $results = @()

    # -- Docker --
    Write-Info "Checking Docker..."
    try {
        $dockerOut = docker info 2>&1 | Select-Object -First 3
        if ($LASTEXITCODE -eq 0) {
            $results += @{ Name = "Docker"; Status = "OK"; Detail = "Engine running" }
            Write-Success "Docker: Engine running"
        } else {
            $results += @{ Name = "Docker"; Status = "WARN"; Detail = "Not running" }
            Write-Err "Docker: Engine not running"
        }
    } catch {
        $results += @{ Name = "Docker"; Status = "FAIL"; Detail = "Not installed" }
        Write-Err "Docker: Not found"
    }

    # -- Ollama (via Docker) --
    Write-Info "Checking Ollama (localhost:11434)..."
    try {
        $ollamaResp = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -ErrorAction Stop
        $modelCount = if ($ollamaResp.models) { $ollamaResp.models.Count } else { 0 }
        $results += @{ Name = "Ollama"; Status = "OK"; Detail = "$modelCount model(s) available" }
        Write-Success "Ollama: Reachable — $modelCount model(s)"
    } catch {
        $results += @{ Name = "Ollama"; Status = "WARN"; Detail = "Not reachable" }
        Write-Err "Ollama: Not reachable at localhost:11434"
    }

    # -- Node.js --
    Write-Info "Checking Node.js..."
    if (Test-CommandExists "node") {
        $nodeVer = node --version 2>$null
        $results += @{ Name = "Node.js"; Status = "OK"; Detail = $nodeVer }
        Write-Success "Node.js: $nodeVer"
    } else {
        $results += @{ Name = "Node.js"; Status = "FAIL"; Detail = "Not found" }
        Write-Err "Node.js: Not found"
    }

    # -- Python --
    Write-Info "Checking Python..."
    if (Test-CommandExists "python") {
        $pyVer = python --version 2>$null
        $results += @{ Name = "Python"; Status = "OK"; Detail = $pyVer }
        Write-Success "Python: $pyVer"
    } else {
        $results += @{ Name = "Python"; Status = "FAIL"; Detail = "Not found" }
        Write-Err "Python: Not found"
    }

    # -- uv --
    Write-Info "Checking uv..."
    if (Test-CommandExists "uv") {
        $uvVer = uv --version 2>$null
        $results += @{ Name = "uv"; Status = "OK"; Detail = $uvVer }
        Write-Success "uv: $uvVer"
    } else {
        $results += @{ Name = "uv"; Status = "FAIL"; Detail = "Not found" }
        Write-Err "uv: Not found"
    }

    # -- Git --
    Write-Info "Checking Git..."
    if (Test-CommandExists "git") {
        $gitVer = git --version 2>$null
        $results += @{ Name = "Git"; Status = "OK"; Detail = $gitVer }
        Write-Success "Git: $gitVer"
    } else {
        $results += @{ Name = "Git"; Status = "FAIL"; Detail = "Not found" }
        Write-Err "Git: Not found"
    }

    # -- OpenCode CLI --
    Write-Info "Checking OpenCode CLI..."
    if (Test-CommandExists "opencode") {
        $ocVer = opencode --version 2>$null
        $results += @{ Name = "OpenCode"; Status = "OK"; Detail = $ocVer }
        Write-Success "OpenCode: $ocVer"
    } else {
        $results += @{ Name = "OpenCode"; Status = "FAIL"; Detail = "Not found" }
        Write-Err "OpenCode: Not found"
    }

    # -- Config files --
    Write-Info "Checking config files..."
    $configChecks = @(
        @{ Name = "MCP config (.claude.json)";          Path = (Join-Path $env:USERPROFILE ".claude.json") },
        @{ Name = "OpenCode config";                     Path = (Join-Path $env:USERPROFILE ".config\opencode\opencode.json") },
        @{ Name = "Caveman prompt";                      Path = (Join-Path $env:USERPROFILE ".claude\commands\caveman.md") }
    )
    foreach ($cfg in $configChecks) {
        if (Test-Path $cfg.Path) {
            $results += @{ Name = $cfg.Name; Status = "OK"; Detail = "Exists" }
            Write-Success "$($cfg.Name): ✓ exists"
        } else {
            $results += @{ Name = $cfg.Name; Status = "MISS"; Detail = "Not found" }
            Write-Err "$($cfg.Name): not found"
        }
    }

    # Summary table
    Write-Host ""
    Write-Host "  ┌────────────────────────────────┬────────┬──────────────────────────────┐" -ForegroundColor White
    Write-Host "  │ Component                      │ Status │ Detail                       │" -ForegroundColor White
    Write-Host "  ├────────────────────────────────┼────────┼──────────────────────────────┤" -ForegroundColor White
    foreach ($r in $results) {
        $name   = $r.Name.PadRight(30)
        $status = $r.Status.PadRight(6)
        $detail = if ($r.Detail.Length -gt 28) { $r.Detail.Substring(0,28) } else { $r.Detail.PadRight(28) }
        $color = switch ($r.Status) {
            "OK"   { "Green"  }
            "WARN" { "Yellow" }
            "MISS" { "Yellow" }
            default { "Red"   }
        }
        Write-Host "  │ " -ForegroundColor White -NoNewline
        Write-Host "$name" -ForegroundColor White -NoNewline
        Write-Host " │ " -ForegroundColor White -NoNewline
        Write-Host "$status" -ForegroundColor $color -NoNewline
        Write-Host " │ " -ForegroundColor White -NoNewline
        Write-Host "$detail" -ForegroundColor $color -NoNewline
        Write-Host " │" -ForegroundColor White
    }
    Write-Host "  └────────────────────────────────┴────────┴──────────────────────────────┘" -ForegroundColor White
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
function Main {
    Write-Banner

    if ($DryRun) {
        Write-Host "  *** DRY-RUN MODE — no changes will be made ***" -ForegroundColor Magenta
        Write-Host ""
    }

    # Require admin (skip for dry-run to allow unprivileged preview)
    if (-not $DryRun) {
        Assert-Admin
    }

    # ── Step 1: Git ──────────────────────────────────────────────────────────
    Install-ViaWinget -DisplayName "Git" -WingetId "Git.Git" -TestCommand "git"

    # ── Step 2: Docker Desktop ───────────────────────────────────────────────
    Install-ViaWinget -DisplayName "Docker Desktop" -WingetId "Docker.DockerDesktop" -TestCommand "docker"

    # ── Step 3: Node.js 20+ LTS ─────────────────────────────────────────────
    Install-ViaWinget -DisplayName "Node.js LTS" -WingetId "OpenJS.NodeJS.LTS" -TestCommand "node"

    # ── Step 4: Python 3.12 ──────────────────────────────────────────────────
    Install-ViaWinget -DisplayName "Python 3.12" -WingetId "Python.Python.3.12" -TestCommand "python"

    # Refresh PATH after all winget installs
    if (-not $DryRun) {
        Refresh-Path
    }

    # ── Step 5: uv ──────────────────────────────────────────────────────────
    Install-Uv

    # ── Step 6: Start Docker engine ──────────────────────────────────────────
    Start-DockerEngine

    # ── Step 7: Docker Compose up ────────────────────────────────────────────
    Invoke-DockerComposeUp

    # ── Step 8: OpenCode CLI ─────────────────────────────────────────────────
    Install-NpmGlobal -DisplayName "OpenCode CLI" -PackageName "opencode-ai" -TestCommand "opencode"

    # ── Step 9: OpenSpec CLI ─────────────────────────────────────────────────
    Install-NpmGlobal -DisplayName "OpenSpec CLI" -PackageName "@fission-ai/openspec@latest" -TestCommand "openspec"

    # ── Step 10: Deploy MCP config ───────────────────────────────────────────
    Deploy-McpConfig

    # ── Step 11: Deploy OpenCode config ──────────────────────────────────────
    Deploy-OpenCodeConfig

    # ── Step 12: Deploy caveman prompt ───────────────────────────────────────
    Deploy-CavemanPrompt

    # ── Verification ─────────────────────────────────────────────────────────
    if (-not $DryRun) {
        Invoke-PostInstallVerification
    } else {
        Write-Host ""
        Write-Dry "Skipping post-install verification in dry-run mode."
    }

    # ── Done ─────────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    if ($DryRun) {
        Write-Host "  ║          DRY-RUN COMPLETE — no changes were made            ║" -ForegroundColor Green
    } else {
        Write-Host "  ║              BOOTSTRAP COMPLETE — Happy hacking!            ║" -ForegroundColor Green
    }
    Write-Host "  ╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""

    if (-not $DryRun) {
        Write-Info "NOTE: You may need to restart your terminal for all PATH changes to take effect."
        Write-Info "NOTE: Docker Desktop may require a system restart if WSL2 was just installed."
        Write-Host ""
    }
}

# Entry point
Main
