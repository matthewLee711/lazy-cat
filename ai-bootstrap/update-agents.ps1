<#
.SYNOPSIS
    Update OpenCode agent definitions on Windows.

.DESCRIPTION
    Copies agent .md files from .\agents\ to ~/.config/opencode/agents/
    Overwrites existing files. Safe to re-run.

.PARAMETER DryRun
    Preview changes without writing files.

.PARAMETER Help
    Show usage information.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$AgentsSrc  = Join-Path $PSScriptRoot "agents"
$AgentsDest = Join-Path $env:USERPROFILE ".config\opencode\agents"

# ── Help ─────────────────────────────────────────────────────────────────────
if ($Help) {
    Write-Host ""
    Write-Host "  Usage: .\update-agents.ps1 [-DryRun] [-Help]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Copies agent .md files from .\agents\ to ~/.config/opencode/agents/"
    Write-Host "  Overwrites existing files. Safe to re-run."
    Write-Host ""
    Write-Host "  -DryRun   Preview changes without writing files"
    Write-Host "  -Help     Show this message"
    Write-Host ""
    exit 0
}

# ── Banner ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║       OpenCode Agent Updater (Windows)           ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "  ▶ DRY-RUN MODE" -ForegroundColor Yellow
    Write-Host ""
}

# ── Validate source ─────────────────────────────────────────────────────────
if (-not (Test-Path $AgentsSrc)) {
    Write-Host "  ✗ Source directory not found: $AgentsSrc" -ForegroundColor Red
    exit 1
}

$agentFiles = Get-ChildItem -Path $AgentsSrc -Filter "*.md"
if ($agentFiles.Count -eq 0) {
    Write-Host "  ✗ No .md files found in $AgentsSrc" -ForegroundColor Red
    exit 1
}

Write-Host "  Source:  $AgentsSrc" -ForegroundColor DarkGray
Write-Host "  Target:  $AgentsDest" -ForegroundColor DarkGray
Write-Host ""

# ── Create target directory ─────────────────────────────────────────────────
if (-not (Test-Path $AgentsDest)) {
    if ($DryRun) {
        Write-Host "  [dry-run] Would create $AgentsDest" -ForegroundColor Magenta
    } else {
        New-Item -ItemType Directory -Path $AgentsDest -Force | Out-Null
        Write-Host "  ✓ Created $AgentsDest" -ForegroundColor Green
    }
}

# ── Copy each agent file ────────────────────────────────────────────────────
$updated = 0
$skipped = 0

foreach ($srcFile in $agentFiles) {
    $destFile = Join-Path $AgentsDest $srcFile.Name

    # Check if target is identical
    if (Test-Path $destFile) {
        $srcHash = (Get-FileHash $srcFile.FullName -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash $destFile -Algorithm SHA256).Hash
        if ($srcHash -eq $dstHash) {
            Write-Host "  ─  $($srcFile.Name) (unchanged)" -ForegroundColor Cyan
            $skipped++
            continue
        }
    }

    if ($DryRun) {
        if (Test-Path $destFile) {
            Write-Host "  [dry-run] Would update $($srcFile.Name)" -ForegroundColor Magenta
        } else {
            Write-Host "  [dry-run] Would create $($srcFile.Name)" -ForegroundColor Magenta
        }
    } else {
        Copy-Item $srcFile.FullName $destFile -Force
        if (Test-Path $destFile) {
            Write-Host "  ✓  $($srcFile.Name) (updated)" -ForegroundColor Green
        } else {
            Write-Host "  ✓  $($srcFile.Name) (created)" -ForegroundColor Green
        }
    }
    $updated++
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Summary: $updated updated, $skipped unchanged" -ForegroundColor White
Write-Host ""
