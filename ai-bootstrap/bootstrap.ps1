<#
.SYNOPSIS
    AI Development Environment Bootstrap — Windows PowerShell Installer
.DESCRIPTION
    Installs and configures Git, Docker Desktop, Node.js, Python, uv,
    OpenCode CLI, OpenSpec CLI, MCP config, OpenCode config, caveman prompt,
    and OpenCode agents. Idempotent — safe to re-run.
.PARAMETER DryRun
    Preview actions without making changes.
.PARAMETER Help
    Display usage information and exit.
#>
param(
    [switch]$DryRun,
    [switch]$Help
)

# ── Strict mode ──────────────────────────────────────────────────────────────
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Colors & Logging ────────────────────────────────────────────────────────
function Write-Success  { param([string]$Msg) Write-Host "  ✅ $Msg" -ForegroundColor Green   }
function Write-Err      { param([string]$Msg) Write-Host "  ❌ $Msg" -ForegroundColor Red     }
function Write-Installing { param([string]$Msg) Write-Host "  ⏳ $Msg" -ForegroundColor Yellow }
function Write-Info     { param([string]$Msg) Write-Host "  ℹ️  $Msg" -ForegroundColor Cyan    }
function Write-DryRun   { param([string]$Msg) Write-Host "  🔍 [DRY-RUN] $Msg" -ForegroundColor Magenta }
function Write-Step     { param([int]$Num, [string]$Msg)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "  STEP $Num — $Msg" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
}

# ── Banner ──────────────────────────────────────────────────────────────────
function Show-Banner {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                                                      ║" -ForegroundColor Cyan
    Write-Host "  ║     🚀  AI Dev Environment Bootstrap (Windows)  🚀   ║" -ForegroundColor Cyan
    Write-Host "  ║                                                      ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    if ($DryRun) {
        Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "  ║          DRY-RUN MODE — No changes will be made     ║" -ForegroundColor Magenta
        Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Magenta
        Write-Host ""
    }
}

# ── Help ────────────────────────────────────────────────────────────────────
function Show-Help {
    Show-Banner
    Write-Host "  USAGE:" -ForegroundColor White
    Write-Host "    .\bootstrap.ps1              Run full installation"
    Write-Host "    .\bootstrap.ps1 -DryRun      Preview actions without changes"
    Write-Host "    .\bootstrap.ps1 -Help        Show this help"
    Write-Host ""
    Write-Host "  INSTALL SEQUENCE:" -ForegroundColor White
    Write-Host "     1. Git                       (winget)"
    Write-Host "     2. Docker Desktop            (winget)"
    Write-Host "     3. Node.js 20+ LTS           (winget)"
    Write-Host "     4. Python 3.12               (winget)"
    Write-Host "     5. uv                        (astral.sh installer)"
    Write-Host "     6. Start Docker Engine        "
    Write-Host "     7. Docker Compose up          "
    Write-Host "     8. OpenCode CLI              (npm global)"
    Write-Host "     9. OpenSpec CLI              (npm global)"
    Write-Host "    10. Deploy MCP config         (~\.claude.json)"
    Write-Host "    11. Deploy OpenCode config    (~\.config\opencode\opencode.json)"
    Write-Host "    12. Deploy caveman prompt     (~\.claude\commands\caveman.md)"
    Write-Host "    13. Deploy OpenCode agents    (~\.config\opencode\agents\)"
    Write-Host ""
    Write-Host "  REQUIREMENTS:" -ForegroundColor White
    Write-Host "    • Windows 10/11 with PowerShell 5.1+"
    Write-Host "    • Administrator privileges (script will self-elevate)"
    Write-Host "    • winget (App Installer) available"
    Write-Host ""
}

if ($Help) {
    Show-Help
    exit 0
}

# ── Admin Elevation ────────────────────────────────────────────────────────
function Assert-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Info "Not running as Administrator — requesting elevation..."
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($DryRun) { $arguments += " -DryRun" }
        try {
            Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs -Wait
        } catch {
            Write-Err "Failed to elevate to Administrator. Please run this script as Admin."
            exit 1
        }
        exit 0
    }
    Write-Success "Running with Administrator privileges"
}

# ── PATH Refresh ────────────────────────────────────────────────────────────
function Refresh-Path {
    <#
    .SYNOPSIS
        Reload PATH from the registry so newly-installed tools are visible
        without restarting the shell.
    #>
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath"
    Write-Info "PATH refreshed from registry"
}

# ── Command existence helper ────────────────────────────────────────────────
function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# ── Winget install helper ───────────────────────────────────────────────────
function Install-ViaWinget {
    param(
        [string]$PackageId,
        [string]$FriendlyName,
        [string]$TestCommand
    )
    if ($TestCommand -and (Test-CommandExists $TestCommand)) {
        Write-Success "$FriendlyName is already installed"
        return
    }
    if ($DryRun) {
        Write-DryRun "Would install $FriendlyName via: winget install --id $PackageId -e"
        return
    }
    Write-Installing "Installing $FriendlyName..."
    $wingetArgs = @("install", "--id", $PackageId, "-e",
                    "--accept-source-agreements", "--accept-package-agreements")
    $proc = Start-Process -FilePath "winget" -ArgumentList $wingetArgs `
                          -NoNewWindow -Wait -PassThru
    Refresh-Path
    if ($proc.ExitCode -eq 0) {
        Write-Success "$FriendlyName installed successfully"
    } elseif ($proc.ExitCode -eq -1978335189) {
        # 0x8A150057 — already installed
        Write-Success "$FriendlyName is already installed (winget confirmed)"
    } else {
        Write-Err "$FriendlyName installation returned exit code $($proc.ExitCode)"
    }
}

# ── NPM global install helper ──────────────────────────────────────────────
function Install-NpmGlobal {
    param(
        [string]$Package,
        [string]$FriendlyName,
        [string]$TestCommand
    )
    if ($TestCommand -and (Test-CommandExists $TestCommand)) {
        Write-Success "$FriendlyName is already installed"
        return
    }
    if ($DryRun) {
        Write-DryRun "Would install $FriendlyName via: npm install -g $Package"
        return
    }
    Write-Installing "Installing $FriendlyName globally via npm..."
    $proc = Start-Process -FilePath "npm" -ArgumentList @("install", "-g", $Package) `
                          -NoNewWindow -Wait -PassThru
    Refresh-Path
    if ($proc.ExitCode -eq 0) {
        Write-Success "$FriendlyName installed successfully"
    } else {
        Write-Err "$FriendlyName npm install returned exit code $($proc.ExitCode)"
    }
}

# ════════════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════════════
Show-Banner
Assert-Admin

$scriptDir   = $PSScriptRoot
$configDir   = Join-Path $scriptDir "configs"
$agentsDir   = Join-Path $scriptDir "agents"
$userProfile = $env:USERPROFILE

Write-Info "Script directory : $scriptDir"
Write-Info "User profile     : $userProfile"
Write-Host ""

# ── Step 1: Git ─────────────────────────────────────────────────────────────
Write-Step 1 "Git"
Install-ViaWinget -PackageId "Git.Git" -FriendlyName "Git" -TestCommand "git"

# ── Step 2: Docker Desktop ──────────────────────────────────────────────────
Write-Step 2 "Docker Desktop"
Install-ViaWinget -PackageId "Docker.DockerDesktop" -FriendlyName "Docker Desktop" -TestCommand "docker"

# ── Step 3: Node.js 20+ LTS ────────────────────────────────────────────────
Write-Step 3 "Node.js 20+ LTS"
$nodeInstalled = $false
if (Test-CommandExists "node") {
    $nodeVer = (node --version 2>$null) -replace '^v', ''
    $nodeMajor = [int]($nodeVer -split '\.')[0]
    if ($nodeMajor -ge 20) {
        Write-Success "Node.js $nodeVer is already installed (>= 20)"
        $nodeInstalled = $true
    } else {
        Write-Info "Node.js $nodeVer found but < 20 — upgrading"
    }
}
if (-not $nodeInstalled) {
    Install-ViaWinget -PackageId "OpenJS.NodeJS.LTS" -FriendlyName "Node.js LTS" -TestCommand ""
}

# ── Step 4: Python 3.12 ────────────────────────────────────────────────────
Write-Step 4 "Python 3.12"
$pythonInstalled = $false
if (Test-CommandExists "python") {
    $pyVer = (python --version 2>&1) -replace '^Python ', ''
    if ($pyVer -match '^3\.12') {
        Write-Success "Python $pyVer is already installed"
        $pythonInstalled = $true
    } else {
        Write-Info "Python $pyVer found — installing 3.12 side-by-side"
    }
}
if (-not $pythonInstalled) {
    Install-ViaWinget -PackageId "Python.Python.3.12" -FriendlyName "Python 3.12" -TestCommand ""
}

# ── Step 5: uv ─────────────────────────────────────────────────────────────
Write-Step 5 "uv (Python package manager)"
if (Test-CommandExists "uv") {
    Write-Success "uv is already installed"
} elseif ($DryRun) {
    Write-DryRun "Would install uv via: irm https://astral.sh/uv/install.ps1 | iex"
} else {
    Write-Installing "Installing uv..."
    try {
        & ([scriptblock]::Create((Invoke-RestMethod "https://astral.sh/uv/install.ps1")))
        Refresh-Path
        Write-Success "uv installed successfully"
    } catch {
        Write-Err "uv installation failed: $_"
    }
}

# ── Step 6: Start Docker ───────────────────────────────────────────────────
Write-Step 6 "Start Docker Engine"
if ($DryRun) {
    Write-DryRun "Would start Docker Desktop and wait for engine readiness"
} else {
    # Check if Docker daemon is already responsive
    $dockerReady = $false
    try {
        $dockerInfo = docker info 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Docker engine is already running"
            $dockerReady = $true
        }
    } catch { }

    if (-not $dockerReady) {
        Write-Installing "Starting Docker Desktop..."
        $dockerPath = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
        if (-not (Test-Path $dockerPath)) {
            # Try alternate common location
            $dockerPath = "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
        }
        if (Test-Path $dockerPath) {
            Start-Process -FilePath $dockerPath
        } else {
            Write-Info "Docker Desktop executable not found at expected path — trying via shell..."
            Start-Process "Docker Desktop"
        }

        Write-Info "Waiting for Docker engine to be ready (up to 120s)..."
        $maxWait = 120
        $elapsed = 0
        $interval = 5
        while ($elapsed -lt $maxWait) {
            Start-Sleep -Seconds $interval
            $elapsed += $interval
            try {
                $null = docker info 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $dockerReady = $true
                    break
                }
            } catch { }
            Write-Host "    ⏳ Waiting... ($elapsed s)" -ForegroundColor Yellow
        }
        if ($dockerReady) {
            Write-Success "Docker engine is ready"
        } else {
            Write-Err "Docker engine did not become ready within ${maxWait}s — continuing anyway"
        }
    }
}

# ── Step 7: Docker Compose ─────────────────────────────────────────────────
Write-Step 7 "Docker Compose up"
$composeFile = Join-Path $scriptDir "docker-compose.yml"
if (-not (Test-Path $composeFile)) {
    $composeFile = Join-Path $scriptDir "compose.yml"
}
if (-not (Test-Path $composeFile)) {
    Write-Info "No docker-compose.yml or compose.yml found in $scriptDir — skipping"
} elseif ($DryRun) {
    Write-DryRun "Would run: docker compose up -d  (from $scriptDir)"
} else {
    Write-Installing "Running docker compose up -d..."
    $proc = Start-Process -FilePath "docker" -ArgumentList @("compose", "up", "-d") `
                          -WorkingDirectory $scriptDir -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -eq 0) {
        Write-Success "Docker Compose services started"
    } else {
        Write-Err "Docker Compose returned exit code $($proc.ExitCode)"
    }
}

# ── Step 8: OpenCode CLI ───────────────────────────────────────────────────
Write-Step 8 "OpenCode CLI"
Install-NpmGlobal -Package "opencode-ai" -FriendlyName "OpenCode CLI" -TestCommand "opencode"

# ── Step 9: OpenSpec CLI ───────────────────────────────────────────────────
Write-Step 9 "OpenSpec CLI"
Install-NpmGlobal -Package "@fission-ai/openspec@latest" -FriendlyName "OpenSpec CLI" -TestCommand "openspec"

# ── Step 10: Deploy MCP Config ─────────────────────────────────────────────
Write-Step 10 "Deploy MCP config → ~/.claude.json"

$claudeJsonPath   = Join-Path $userProfile ".claude.json"
$mcpSettingsFile  = Join-Path $configDir "mcp_settings.json"

if (-not (Test-Path $mcpSettingsFile)) {
    Write-Err "Source MCP settings not found: $mcpSettingsFile"
} elseif ($DryRun) {
    Write-DryRun "Would merge $mcpSettingsFile into $claudeJsonPath"
    Write-DryRun "Would apply Windows cmd /c wrapper for Serena"
} else {
    Write-Installing "Merging MCP config..."

    # Load source MCP settings
    $mcpSource = Get-Content -Raw $mcpSettingsFile | ConvertFrom-Json

    # Override Serena config with Windows-specific cmd /c wrapper
    $serenaConfig = [PSCustomObject]@{
        command = "cmd"
        args    = @("/c", "uvx", "--from", "git+https://github.com/oraios/serena",
                     "serena", "start-mcp-server", "--context", "claude-code",
                     "--project-from-cwd")
    }
    # Ensure mcpServers property exists on source
    if (-not ($mcpSource.PSObject.Properties.Name -contains "mcpServers")) {
        $mcpSource | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
    }
    # Set the Serena entry with the Windows wrapper
    if ($mcpSource.mcpServers.PSObject.Properties.Name -contains "serena") {
        $mcpSource.mcpServers.serena = $serenaConfig
    } else {
        $mcpSource.mcpServers | Add-Member -NotePropertyName "serena" -NotePropertyValue $serenaConfig
    }

    # Load or create existing .claude.json
    if (Test-Path $claudeJsonPath) {
        $claudeJson = Get-Content -Raw $claudeJsonPath | ConvertFrom-Json
        Write-Info "Existing .claude.json found — merging mcpServers (existing servers preserved)"

        if (-not ($claudeJson.PSObject.Properties.Name -contains "mcpServers")) {
            $claudeJson | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
        }

        # Merge: add new servers without overwriting existing ones
        foreach ($prop in $mcpSource.mcpServers.PSObject.Properties) {
            if (-not ($claudeJson.mcpServers.PSObject.Properties.Name -contains $prop.Name)) {
                $claudeJson.mcpServers | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
                Write-Info "  Added MCP server: $($prop.Name)"
            } else {
                Write-Info "  Skipped MCP server (already exists): $($prop.Name)"
            }
        }
    } else {
        Write-Info "No existing .claude.json — creating new file"
        $claudeJson = $mcpSource
    }

    $claudeJson | ConvertTo-Json -Depth 10 | Set-Content -Path $claudeJsonPath -Encoding UTF8
    Write-Success "MCP config deployed to $claudeJsonPath"
}

# ── Step 11: Deploy OpenCode Config ────────────────────────────────────────
Write-Step 11 "Deploy OpenCode config → ~/.config/opencode/opencode.json"

$opencodeSrc  = Join-Path $configDir "opencode.json"
$opencodeDest = Join-Path $userProfile ".config\opencode\opencode.json"
$opencodeDir  = Split-Path $opencodeDest -Parent

if (-not (Test-Path $opencodeSrc)) {
    Write-Err "Source not found: $opencodeSrc"
} elseif ($DryRun) {
    Write-DryRun "Would copy $opencodeSrc → $opencodeDest"
} else {
    if (-not (Test-Path $opencodeDir)) {
        New-Item -ItemType Directory -Path $opencodeDir -Force | Out-Null
        Write-Info "Created directory: $opencodeDir"
    }
    Copy-Item -Path $opencodeSrc -Destination $opencodeDest -Force
    Write-Success "OpenCode config deployed to $opencodeDest"
}

# ── Step 12: Deploy Caveman Prompt ─────────────────────────────────────────
Write-Step 12 "Deploy caveman prompt → ~/.claude/commands/caveman.md"

$cavemanSrc  = Join-Path $configDir "caveman_prompt.txt"
$cavemanDest = Join-Path $userProfile ".claude\commands\caveman.md"
$cavemanDir  = Split-Path $cavemanDest -Parent

if (-not (Test-Path $cavemanSrc)) {
    Write-Err "Source not found: $cavemanSrc"
} elseif ($DryRun) {
    Write-DryRun "Would copy $cavemanSrc → $cavemanDest"
} else {
    if (-not (Test-Path $cavemanDir)) {
        New-Item -ItemType Directory -Path $cavemanDir -Force | Out-Null
        Write-Info "Created directory: $cavemanDir"
    }
    Copy-Item -Path $cavemanSrc -Destination $cavemanDest -Force
    Write-Success "Caveman prompt deployed to $cavemanDest"
}

# ── Step 13: Deploy OpenCode Agents ────────────────────────────────────────
Write-Step 13 "Deploy OpenCode agents → ~/.config/opencode/agents/"

$agentsDest = Join-Path $userProfile ".config\opencode\agents"

if (-not (Test-Path $agentsDir)) {
    Write-Err "Source agents directory not found: $agentsDir"
} else {
    $agentFiles = Get-ChildItem -Path $agentsDir -Filter "*.md" -File -ErrorAction SilentlyContinue
    if ($null -eq $agentFiles -or $agentFiles.Count -eq 0) {
        Write-Info "No .md files found in $agentsDir — skipping"
    } elseif ($DryRun) {
        Write-DryRun "Would create directory: $agentsDest"
        foreach ($f in $agentFiles) {
            Write-DryRun "  Would copy: $($f.Name)"
        }
    } else {
        if (-not (Test-Path $agentsDest)) {
            New-Item -ItemType Directory -Path $agentsDest -Force | Out-Null
            Write-Info "Created directory: $agentsDest"
        }
        foreach ($f in $agentFiles) {
            Copy-Item -Path $f.FullName -Destination (Join-Path $agentsDest $f.Name) -Force
            Write-Info "  Copied agent: $($f.Name)"
        }
        Write-Success "$($agentFiles.Count) agent file(s) deployed to $agentsDest"
    }
}

# ════════════════════════════════════════════════════════════════════════════
#  POST-INSTALL VERIFICATION
# ════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "  POST-INSTALL VERIFICATION" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

Refresh-Path

# Build verification results
$checks = @(
    @{ Name = "Git";            Test = { if (Test-CommandExists "git")      { git --version 2>$null }       else { $null } } },
    @{ Name = "Docker";         Test = { if (Test-CommandExists "docker")   { docker --version 2>$null }    else { $null } } },
    @{ Name = "Node.js";        Test = { if (Test-CommandExists "node")     { node --version 2>$null }      else { $null } } },
    @{ Name = "Python";         Test = { if (Test-CommandExists "python")   { python --version 2>$null }    else { $null } } },
    @{ Name = "uv";             Test = { if (Test-CommandExists "uv")       { uv --version 2>$null }        else { $null } } },
    @{ Name = "OpenCode";       Test = { if (Test-CommandExists "opencode") { "installed" }                  else { $null } } },
    @{ Name = "OpenSpec";       Test = { if (Test-CommandExists "openspec") { "installed" }                  else { $null } } },
    @{ Name = ".claude.json";   Test = { if (Test-Path $claudeJsonPath)     { "exists" }                     else { $null } } },
    @{ Name = "opencode.json";  Test = { if (Test-Path $opencodeDest)       { "exists" }                     else { $null } } },
    @{ Name = "caveman.md";     Test = { if (Test-Path $cavemanDest)        { "exists" }                     else { $null } } }
)

# Check for deployed agent files
$agentCheckResult = $null
if (Test-Path $agentsDest) {
    $deployedAgents = Get-ChildItem -Path $agentsDest -Filter "*.md" -File -ErrorAction SilentlyContinue
    if ($null -ne $deployedAgents -and $deployedAgents.Count -gt 0) {
        $agentCheckResult = "$($deployedAgents.Count) file(s)"
    }
}
$checks += @{ Name = "Agents dir"; Test = { $agentCheckResult }.GetNewClosure() }

# Print summary table
Write-Host "  ┌──────────────────┬────────┬─────────────────────────────────┐" -ForegroundColor DarkGray
Write-Host "  │ Component        │ Status │ Details                         │" -ForegroundColor DarkGray
Write-Host "  ├──────────────────┼────────┼─────────────────────────────────┤" -ForegroundColor DarkGray

foreach ($check in $checks) {
    $result = try { & $check.Test } catch { $null }
    $name    = $check.Name.PadRight(16)
    if ($null -ne $result -and $result -ne "") {
        $status  = " ✅ "
        $detail  = "$result".Trim().PadRight(31)
        $color   = "Green"
    } else {
        $status  = " ❌ "
        $detail  = "not found".PadRight(31)
        $color   = "Red"
    }
    Write-Host "  │ " -NoNewline -ForegroundColor DarkGray
    Write-Host "$name" -NoNewline -ForegroundColor White
    Write-Host " │" -NoNewline -ForegroundColor DarkGray
    Write-Host "$status" -NoNewline -ForegroundColor $color
    Write-Host "│ " -NoNewline -ForegroundColor DarkGray
    Write-Host "$detail" -NoNewline -ForegroundColor $color
    Write-Host "│" -ForegroundColor DarkGray
}
Write-Host "  └──────────────────┴────────┴─────────────────────────────────┘" -ForegroundColor DarkGray

# ── Done ────────────────────────────────────────────────────────────────────
Write-Host ""
if ($DryRun) {
    Write-Host "  🔍 Dry run complete — no changes were made." -ForegroundColor Magenta
} else {
    Write-Host "  🎉 Bootstrap complete!" -ForegroundColor Green
    Write-Host "  💡 You may need to restart your terminal for all PATH changes to take effect." -ForegroundColor Yellow
}
Write-Host ""
