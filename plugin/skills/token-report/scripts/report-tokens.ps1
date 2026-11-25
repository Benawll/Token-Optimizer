param(
    [int]$Latest = 10,
    [string]$ConversationId = ""
)

$ErrorActionPreference = "SilentlyContinue"
. (Join-Path $PSScriptRoot "..\..\..\lib\token-core.ps1")

$brainRoot = Join-Path $env:USERPROFILE ".gemini\antigravity\brain"
if (-not (Test-Path $brainRoot)) {
    [ordered]@{ error = "Dossier brain Antigravity introuvable : $brainRoot" } | ConvertTo-Json
    exit 0
}

$transcripts = if ($ConversationId) {
    $target = Join-Path $brainRoot "$ConversationId\.system_generated\logs\transcript.jsonl"
    if (Test-Path $target) { @(Get-Item $target) } else { @() }
}
else {
    Get-ChildItem -Path $brainRoot -Directory |
        ForEach-Object { Join-Path $_.FullName ".system_generated\logs\transcript.jsonl" } |
        Where-Object { Test-Path $_ } |
        ForEach-Object { Get-Item $_ } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $Latest
}

$byModel = @{}
$byConversation = [System.Collections.Generic.List[object]]::new()
$verboseOutputs = [System.Collections.Generic.List[object]]::new()

$totalInput = 0L; $totalCache = 0L; $totalOutput = 0L; $totalCostUsd = 0.0

foreach ($file in $transcripts) {
    $convId = $file.Directory.Parent.Parent.Name
    $m = Get-TranscriptMetrics -TranscriptPath $file.FullName

    $totalInput += $m.inputTokens
    $totalCache += $m.cacheReadTokens
    $totalOutput += $m.outputTokens
    $totalCostUsd += $m.estimatedUsd

    foreach ($k in $m.byModel.Keys) {
        $src = $m.byModel[$k]
        if (-not $byModel.ContainsKey($k)) {
            $byModel[$k] = @{ turns = 0; inputTokens = 0L; cacheReadTokens = 0L; outputTokens = 0L; estimatedUsd = 0.0 }
        }
        $byModel[$k].turns += $src.turns
        $byModel[$k].inputTokens += $src.inputTokens
        $byModel[$k].cacheReadTokens += $src.cacheReadTokens
        $byModel[$k].outputTokens += $src.outputTokens
        $byModel[$k].estimatedUsd += $src.estimatedUsd
    }

    foreach ($v in $m.verboseOutputs) {
        $verboseOutputs.Add([ordered]@{
            conversationId = $convId
            stepIndex      = $v.stepIndex
            chars          = $v.chars
            estTokens      = $v.estTokens
            preview        = $v.preview
        })
    }

    $byConversation.Add([ordered]@{
        conversationId          = $convId
        lastUpdated             = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        plannerTurns            = $m.turns
        inputTokens             = $m.inputTokens
        cacheReadTokens         = $m.cacheReadTokens
        cacheHitPct             = $m.cacheHitPct
        outputTokens            = $m.outputTokens
        avgContextTokens        = $m.avgContextTokens
        estimatedUsd            = $m.estimatedUsd
        projectedNext20TurnsUsd = $m.projectedNext20TurnsUsd
    })
}

$globalHit = if ($totalInput -gt 0) { [math]::Round(($totalCache / $totalInput) * 100, 1) } else { 0.0 }
$modelSummary = @{}
foreach ($k in $byModel.Keys) {
    $item = $byModel[$k]
    $mHit = if ($item.inputTokens -gt 0) { [math]::Round(($item.cacheReadTokens / $item.inputTokens) * 100, 1) } else { 0.0 }
    $modelSummary[$k] = [ordered]@{
        turns           = $item.turns
        inputTokens     = $item.inputTokens
        cacheReadTokens = $item.cacheReadTokens
        cacheHitPct     = $mHit
        outputTokens    = $item.outputTokens
        estimatedUsd    = [math]::Round($item.estimatedUsd, 4)
    }
}

[ordered]@{
    sessionsAnalyzed      = $byConversation.Count
    totals                = [ordered]@{
        inputTokens     = $totalInput
        cacheReadTokens = $totalCache
        cacheHitPct     = $globalHit
        outputTokens    = $totalOutput
        estimatedUsd    = [math]::Round($totalCostUsd, 4)
    }
    byModel               = $modelSummary
    conversations         = @($byConversation)
    topVerboseToolOutputs = @($verboseOutputs | Sort-Object chars -Descending | Select-Object -First 8)
} | ConvertTo-Json -Depth 5
