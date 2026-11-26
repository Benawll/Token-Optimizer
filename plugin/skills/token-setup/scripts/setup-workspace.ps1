param(
    [string]$WorkspacePath = ".",
    [ValidateSet("audit", "sync")]
    [string]$Mode = "audit",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\..\..\lib\token-core.ps1")

$stackInfo = Get-WorkspaceStackInfo -WorkspacePath $WorkspacePath
$root = $stackInfo.workspace
$ignorePath = Join-Path $root ".antigravityignore"
$hasIgnore = Test-Path $ignorePath

$existingIgnoreLines = if ($hasIgnore) {
    @(Get-Content $ignorePath | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") })
}
else { @() }

$missingIgnores = [System.Collections.Generic.List[string]]::new()
foreach ($pattern in $stackInfo.recommendedIgnore) {
    if ($existingIgnoreLines -notcontains $pattern) {
        $missingIgnores.Add($pattern)
    }
}

# Rules health & budget audit
$ruleFiles = [System.Collections.Generic.List[object]]::new()
$candidateRules = @(
    (Join-Path $root "GEMINI.md"),
    (Join-Path $root "AGENTS.md")
)
$wsRulesDir = Join-Path $root ".agents\rules"
if (Test-Path $wsRulesDir) {
    Get-ChildItem -Path $wsRulesDir -Filter "*.md" -File -ErrorAction SilentlyContinue | ForEach-Object { $candidateRules += $_.FullName }
}
$globalConfig = Join-Path $env:USERPROFILE ".gemini\config"
foreach ($gf in @("GEMINI.md", "AGENTS.md")) {
    $gp = Join-Path $globalConfig $gf
    if (Test-Path $gp) { $candidateRules += $gp }
}

$totalRuleBytes = 0
foreach ($rf in ($candidateRules | Select-Object -Unique)) {
    if (Test-Path $rf) {
        $len = (Get-Item $rf).Length
        $totalRuleBytes += $len
        $head = (Get-Content $rf -TotalCount 15 -ErrorAction SilentlyContinue) -join "`n"
        $dynPrefix = $head -match '(?i)(\b20\d{2}-\d{2}-\d{2}\b|current time|last updated\s*:|uuid)'
        $status = if ($len -gt 24000) { "CRITICAL_OVER_24KB" } elseif ($len -gt 4096) { "WARN_OVER_4KB" } else { "OK" }
        $ruleFiles.Add([ordered]@{
            path             = $rf
            bytes            = $len
            estimatedTokens  = [math]::Ceiling($len / 4)
            status           = $status
            dynamicPrefixHit = $dynPrefix
        })
    }
}

if ($Mode -eq "sync") {
    $syncResult = "dry-run"
    if ($Apply -and $missingIgnores.Count -gt 0) {
        if (-not $hasIgnore) {
            $lines = @("# Token Optimizer — .antigravityignore (auto-generated)") + $missingIgnores
            [System.IO.File]::WriteAllLines($ignorePath, $lines, [System.Text.UTF8Encoding]::new($false))
            $syncResult = "created"
        }
        else {
            $block = "`n# --- Token Optimizer auto-sync ---`n" + ($missingIgnores -join "`n") + "`n"
            [System.IO.File]::AppendAllText($ignorePath, $block, [System.Text.UTF8Encoding]::new($false))
            $syncResult = "appended-lossless"
        }
        Write-TokenOptimizerEvent -EventType "setup_apply" -SavedTokens 0 -Details @{ addedIgnores = $missingIgnores.Count }
    }
    elseif ($Apply) {
        $syncResult = "already-up-to-date"
    }

    [ordered]@{
        workspace          = $root
        detectedStacks     = $stackInfo.detectedStacks
        suggestedTests     = $stackInfo.suggestedTests
        suggestedLints     = $stackInfo.suggestedLints
        syncStatus         = $syncResult
        ignoreFileExists   = (Test-Path $ignorePath)
        missingIgnoreCount = $missingIgnores.Count
        missingIgnores     = @($missingIgnores)
        rulesHealth        = @($ruleFiles)
    } | ConvertTo-Json -Depth 4
    exit 0
}

# Mode = audit: also scan largest non-ignored files & global MCPs
$excludeRegex = '\\(\.git|node_modules|\.venv|venv|target|dist|build|\.next|vendor|\.gradle|__pycache__|bin|obj|\.vs|Library|Temp)(\\|$)'
$largestFiles = Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $excludeRegex } |
    Sort-Object Length -Descending |
    Select-Object -First 15 |
    ForEach-Object {
        $rel = $_.FullName.Substring($root.Length).TrimStart('\', '/')
        [ordered]@{
            path            = $rel
            bytes           = $_.Length
            estimatedTokens = [math]::Ceiling($_.Length / 4)
        }
    }

$mcpPath = Join-Path $globalConfig "mcp_config.json"
$mcpServers = @()
if (Test-Path $mcpPath) {
    $mcpJson = Get-Content -Raw $mcpPath | ConvertFrom-Json
    if ($mcpJson.mcpServers) { $mcpServers = @($mcpJson.mcpServers.PSObject.Properties.Name) }
}

$findings = [System.Collections.Generic.List[string]]::new()
if (-not $hasIgnore) { $findings.Add("HIGH: .antigravityignore manquant à la racine.") }
elseif ($missingIgnores.Count -gt 0) { $findings.Add("MEDIUM: $($missingIgnores.Count) motifs recommandés absents de .antigravityignore.") }
if (($totalRuleBytes / 4) -gt 15000) { $findings.Add("HIGH: Budget agrégé de règles élevé (>15k tokens est. / plafond 20k).") }
$isGameOr3d = ($stackInfo.detectedStacks -contains "unity") -or ($stackInfo.detectedStacks -contains "3d-blender")
$unusedHeavyMcp = @($mcpServers | Where-Object { $_ -in @("unity", "blender", "game-assets") })
if (-not $isGameOr3d -and $unusedHeavyMcp.Count -gt 0) {
    $findings.Add("MEDIUM: MCP 3D/Unity actifs inutilement ($($unusedHeavyMcp -join ', ')) — profil 'minimal' recommandé via token-mcp.")
}

[ordered]@{
    workspace            = $root
    detectedStacks       = $stackInfo.detectedStacks
    hasAntigravityIgnore = $hasIgnore
    missingIgnoreCount   = $missingIgnores.Count
    rulesAudit           = [ordered]@{
        files                = @($ruleFiles)
        totalBytes           = $totalRuleBytes
        totalEstimatedTokens = [math]::Ceiling($totalRuleBytes / 4)
        antigravityLimit     = "24000 bytes/file, 20000 tokens aggregate"
    }
    globalMcpServers     = [ordered]@{
        count = $mcpServers.Count
        names = $mcpServers
    }
    top15LargestFiles    = @($largestFiles)
    findings             = @($findings)
} | ConvertTo-Json -Depth 5
