param(
    [ValidateSet("status", "auto", "switch")]
    [string]$Action = "status",
    [ValidateSet("minimal", "gamedev", "full", "none")]
    [string]$Profile = "minimal",
    [string]$WorkspacePath = ".",
    [string]$ConfigPath = (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json"),
    [string]$BackupPath = (Join-Path $env:USERPROFILE ".gemini\config\mcp_profiles\full-catalog.json")
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\..\..\lib\token-core.ps1")

function Read-McpMap {
    param([string]$Path)
    $map = [ordered]@{}
    if (Test-Path $Path) {
        $obj = Get-Content -Raw $Path | ConvertFrom-Json
        if ($obj -and $obj.mcpServers) {
            foreach ($p in $obj.mcpServers.PSObject.Properties) { $map[$p.Name] = $p.Value }
        }
    }
    return $map
}

function Write-McpMap {
    param([string]$Path, [System.Collections.IDictionary]$Map)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $json = ([ordered]@{ mcpServers = $Map }) | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($Path, $json + "`n", [System.Text.UTF8Encoding]::new($false))
}

$activeMap = Read-McpMap -Path $ConfigPath
$stacks = if (Test-Path $WorkspacePath) { (Get-WorkspaceStackInfo -WorkspacePath $WorkspacePath).detectedStacks } else { @() }
$recommended = if (($stacks -contains "unity") -or ($stacks -contains "3d-blender")) { "gamedev" } else { "minimal" }

if ($Action -eq "status") {
    $backupMap = Read-McpMap -Path $BackupPath
    [ordered]@{
        action             = "status"
        configPath         = $ConfigPath
        backupCatalogPath  = $BackupPath
        backupExists       = (Test-Path $BackupPath)
        detectedStacks     = $stacks
        recommendedProfile = $recommended
        activeServers      = @($activeMap.Keys)
        catalogServers     = if ($backupMap.Count -gt 0) { @($backupMap.Keys) } else { @($activeMap.Keys) }
    } | ConvertTo-Json -Depth 4
    exit 0
}

$catalog = Read-McpMap -Path $BackupPath
foreach ($k in $activeMap.Keys) { $catalog[$k] = $activeMap[$k] }
Write-McpMap -Path $BackupPath -Map $catalog

$targetProfile = if ($Action -eq "auto") { $recommended } else { $Profile }
$heavyGameServers = @("unity", "blender", "game-assets")
$newMap = [ordered]@{}

switch ($targetProfile) {
    "none"    { }
    "minimal" { foreach ($k in $catalog.Keys) { if ($k -notin $heavyGameServers) { $newMap[$k] = $catalog[$k] } } }
    "gamedev" { foreach ($k in $catalog.Keys) { if (($k -in $heavyGameServers) -or ($k -eq "git")) { $newMap[$k] = $catalog[$k] } } }
    "full"    { foreach ($k in $catalog.Keys) { $newMap[$k] = $catalog[$k] } }
}

Write-McpMap -Path $ConfigPath -Map $newMap
$removedCount = [math]::Max(0, ($catalog.Count - $newMap.Count))
Write-TokenOptimizerEvent -EventType "mcp_trim" -SavedTokens 0 -Details @{
    profile        = $targetProfile
    removedServers = $removedCount
    activeServers  = $newMap.Count
}

[ordered]@{
    action            = $Action
    appliedProfile    = $targetProfile
    configPath        = $ConfigPath
    backupCatalogPath = $BackupPath
    activeServers     = @($newMap.Keys)
    catalogServers    = @($catalog.Keys)
    note              = "Prend effet après rechargement / nouvelle session Antigravity."
} | ConvertTo-Json -Depth 4
