param(
    [int]$Latest = 20,
    [string]$OutputPath = (Join-Path $env:TEMP "token-optimizer-dashboard.html"),
    [switch]$Open
)

$ErrorActionPreference = "Stop"
$reportScript = Join-Path $PSScriptRoot "report-tokens.ps1"
$jsonRaw = (& $reportScript -Latest $Latest) -join "`n"
$data = $jsonRaw | ConvertFrom-Json

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
    dashboardPath     = $OutputPath
    opened            = [bool]$Open
    timezone          = $data.timezone
    pluginInstalledAt = $data.pluginInstalledAt
    baselineSource    = $data.baseline.source
    preTurns          = $data.baseline.preTurns
    postTurns         = $data.postSummary.postTurns
    liveQuotaAvail    = $data.antigravityLive.available
    geminiWeeklyPct   = $data.antigravityLive.gemini.weeklyPct
    gemini5hPct       = $data.antigravityLive.gemini.fiveHourPct
    sessionsAnalyzed  = $data.sessionsAnalyzed
} | ConvertTo-Json -Depth 3
