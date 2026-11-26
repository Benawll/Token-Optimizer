param(
    [int]$Latest = 20,
    [string]$OutputPath = (Join-Path $env:TEMP "token-optimizer-dashboard.html"),
    [switch]$Open
)

$ErrorActionPreference = "Stop"
$reportScript = Join-Path $PSScriptRoot "report-tokens.ps1"
$jsonRaw = & powershell -NoProfile -ExecutionPolicy Bypass -File $reportScript -Latest $Latest
$data = $jsonRaw | ConvertFrom-Json
$tot = $data.totals

$templatePath = Join-Path $PSScriptRoot "..\templates\dashboard.html"
if (-not (Test-Path $templatePath)) {
    throw "Template HTML introuvable : $templatePath"
}

$templateHtml = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)
$genDate = (Get-Date).ToString("dd/MM/yyyy HH:mm")

# Remplacement strict sans toucher au JavaScript interne
$finalHtml = $templateHtml.Replace("/*__DATA_JSON__*/", $jsonRaw).Replace("__GEN_DATE__", $genDate)

[System.IO.File]::WriteAllText($OutputPath, $finalHtml, [System.Text.UTF8Encoding]::new($false))

if ($Open) {
    Start-Process $OutputPath
}

[ordered]@{
    dashboardPath    = $OutputPath
    opened           = [bool]$Open
    currency         = "EUR (€)"
    timezone         = "Europe/Paris"
    sessionsAnalyzed = $data.sessionsAnalyzed
    totalSavedTokens = $tot.savedTokens
    totalSavedEur    = $tot.savedEur
    actualCostEur    = $tot.costEur
} | ConvertTo-Json -Depth 3
