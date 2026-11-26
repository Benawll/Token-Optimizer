param(
    [int]$Latest = 20,
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

$USD_TO_EUR = 0.92
$NEON_INPUT_RATE_EUR = 2.76  # 3.00 USD * 0.92
$NEON_OUTPUT_RATE_EUR = 13.80 # 15.00 USD * 0.92

$byModel = @{}
$byConversation = [System.Collections.Generic.List[object]]::new()
$byProject = @{}
$verboseOutputs = [System.Collections.Generic.List[object]]::new()

$totalInput = 0L; $totalCache = 0L; $totalOutput = 0L; $totalCostUsd = 0.0
$totalSavedTokens = 0L; $totalSavedEur = 0.0

foreach ($file in $transcripts) {
    $convId = $file.Directory.Parent.Parent.Name
    $m = Get-TranscriptMetrics -TranscriptPath $file.FullName

    # Détection du projet via le contenu initial
    $sample = Get-Content $file.FullName -TotalCount 40 -ErrorAction SilentlyContinue | Out-String
    $project = "Général"
    if ($sample -match "Career-ops|career_ops|Candidatures") {
        $project = "Career Ops"
    } elseif ($sample -match "Token[ -]Optimizer") {
        $project = "Token Optimizer"
    } elseif ($sample -match "Awll|awll|utility") {
        $project = "Awll"
    }

    $actualCostEur = [math]::Round($m.estimatedUsd * $USD_TO_EUR, 4)
    # Estimation des économies : sans cache ni optimisation, chaque tour d'input au tarif Neon standard
    $unoptimizedCostEur = (($m.inputTokens / 1e6) * $NEON_INPUT_RATE_EUR) + (($m.outputTokens / 1e6) * $NEON_OUTPUT_RATE_EUR)
    $savedEur = [math]::Max(0.0, [math]::Round($unoptimizedCostEur - $actualCostEur, 2))
    $savedTokens = $m.cacheReadTokens

    $totalInput += $m.inputTokens
    $totalCache += $m.cacheReadTokens
    $totalOutput += $m.outputTokens
    $totalCostUsd += $m.estimatedUsd
    $totalSavedTokens += $savedTokens
    $totalSavedEur += $savedEur

    # Aggrégation par projet
    if (-not $byProject.ContainsKey($project)) {
        $byProject[$project] = @{
            project      = $project
            sessions     = 0
            turns        = 0
            inputTokens  = 0L
            savedTokens  = 0L
            costEur      = 0.0
            savedEur     = 0.0
        }
    }
    $byProject[$project].sessions++
    $byProject[$project].turns += $m.turns
    $byProject[$project].inputTokens += $m.inputTokens
    $byProject[$project].savedTokens += $savedTokens
    $byProject[$project].costEur += $actualCostEur
    $byProject[$project].savedEur += $savedEur

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
            project        = $project
            stepIndex      = $v.stepIndex
            chars          = $v.chars
            estTokens      = $v.estTokens
            preview        = $v.preview
        })
    }

    $lastWriteUtc = $file.LastWriteTimeUtc.ToString("o")
    $lastWriteFr = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm")

    $byConversation.Add([ordered]@{
        conversationId          = $convId
        project                 = $project
        lastUpdated             = $lastWriteFr
        lastUpdatedIso          = $lastWriteUtc
        plannerTurns            = $m.turns
        inputTokens             = $m.inputTokens
        cacheReadTokens         = $m.cacheReadTokens
        savedTokens             = $savedTokens
        cacheHitPct             = $m.cacheHitPct
        outputTokens            = $m.outputTokens
        avgContextTokens        = $m.avgContextTokens
        costEur                 = $actualCostEur
        savedEur                = $savedEur
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
        costEur         = [math]::Round($item.estimatedUsd * $USD_TO_EUR, 4)
        estimatedUsd    = [math]::Round($item.estimatedUsd, 4)
    }
}

$projectList = [System.Collections.Generic.List[object]]::new()
foreach ($pk in $byProject.Keys) {
    $p = $byProject[$pk]
    $projectList.Add([ordered]@{
        project     = $p.project
        sessions    = $p.sessions
        turns       = $p.turns
        inputTokens = $p.inputTokens
        savedTokens = $p.savedTokens
        costEur     = [math]::Round($p.costEur, 2)
        savedEur    = [math]::Round($p.savedEur, 2)
    })
}

[ordered]@{
    sessionsAnalyzed      = $byConversation.Count
    currency              = "EUR"
    timezone              = "Europe/Paris (UTC+1)"
    totals                = [ordered]@{
        inputTokens     = $totalInput
        cacheReadTokens = $totalCache
        cacheHitPct     = $globalHit
        outputTokens    = $totalOutput
        savedTokens     = $totalSavedTokens
        costEur         = [math]::Round($totalCostUsd * $USD_TO_EUR, 2)
        savedEur        = [math]::Round($totalSavedEur, 2)
        estimatedUsd    = [math]::Round($totalCostUsd, 4)
    }
    byProject             = @($projectList | Sort-Object savedEur -Descending)
    byModel               = $modelSummary
    conversations         = @($byConversation)
    topVerboseToolOutputs = @($verboseOutputs | Sort-Object chars -Descending | Select-Object -First 8)
} | ConvertTo-Json -Depth 5
