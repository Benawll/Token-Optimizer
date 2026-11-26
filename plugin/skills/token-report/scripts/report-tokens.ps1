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

# Date officielle d'installation de Token Optimizer (25 nov 2026 21:51 Paris = 20:51 UTC)
$PLUGIN_ACTIVATION_UTC = [datetime]::Parse("2026-11-25T20:51:08Z").ToUniversalTime()

$byModel = @{}
$byConversation = [System.Collections.Generic.List[object]]::new()
$byProject = @{}
$verboseOutputs = [System.Collections.Generic.List[object]]::new()

$totalInput = 0L; $totalCache = 0L; $totalOutput = 0L; $totalCostUsd = 0.0

# Séparation stricte : gains réels sous le plugin vs cache historique Google
$pluginInput = 0L; $pluginCache = 0L; $pluginOutput = 0L
$pluginSavedTokens = 0L; $pluginSavedEur = 0.0; $pluginCostEur = 0.0; $pluginSessionsCount = 0

$googleCacheSavedTokens = 0L; $googleCacheSavedEur = 0.0

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
    # Économie théorique totale comparée au tarif Neon brut
    $unoptimizedCostEur = (($m.inputTokens / 1e6) * $NEON_INPUT_RATE_EUR) + (($m.outputTokens / 1e6) * $NEON_OUTPUT_RATE_EUR)
    $sessionSavedEur = [math]::Max(0.0, [math]::Round($unoptimizedCostEur - $actualCostEur, 2))
    $sessionSavedTokens = $m.cacheReadTokens

    # Vérification si la session s'est déroulée avec le plugin actif
    $isPluginActive = ($file.LastWriteTimeUtc -ge $PLUGIN_ACTIVATION_UTC) -or ($sample -match "token-optimizer|Token Optimizer")

    $totalInput += $m.inputTokens
    $totalCache += $m.cacheReadTokens
    $totalOutput += $m.outputTokens
    $totalCostUsd += $m.estimatedUsd

    $googleCacheSavedTokens += $sessionSavedTokens
    $googleCacheSavedEur += $sessionSavedEur

    if ($isPluginActive) {
        $pluginSessionsCount++
        $pluginInput += $m.inputTokens
        $pluginCache += $m.cacheReadTokens
        $pluginOutput += $m.outputTokens
        $pluginSavedTokens += $sessionSavedTokens
        $pluginSavedEur += $sessionSavedEur
        $pluginCostEur += $actualCostEur
    }

    # Aggrégation par projet
    if (-not $byProject.ContainsKey($project)) {
        $byProject[$project] = @{
            project              = $project
            sessions             = 0
            pluginSessions       = 0
            turns                = 0
            inputTokens          = 0L
            pluginSavedTokens    = 0L
            googleCacheTokens    = 0L
            costEur              = 0.0
            pluginSavedEur       = 0.0
            googleCacheSavedEur  = 0.0
        }
    }
    $byProject[$project].sessions++
    $byProject[$project].turns += $m.turns
    $byProject[$project].inputTokens += $m.inputTokens
    $byProject[$project].costEur += $actualCostEur
    $byProject[$project].googleCacheTokens += $sessionSavedTokens
    $byProject[$project].googleCacheSavedEur += $sessionSavedEur

    if ($isPluginActive) {
        $byProject[$project].pluginSessions++
        $byProject[$project].pluginSavedTokens += $sessionSavedTokens
        $byProject[$project].pluginSavedEur += $sessionSavedEur
    }

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
        isPluginActive          = $isPluginActive
        lastUpdated             = $lastWriteFr
        lastUpdatedIso          = $lastWriteUtc
        plannerTurns            = $m.turns
        inputTokens             = $m.inputTokens
        cacheReadTokens         = $m.cacheReadTokens
        savedTokens             = $sessionSavedTokens
        cacheHitPct             = $m.cacheHitPct
        outputTokens            = $m.outputTokens
        avgContextTokens        = $m.avgContextTokens
        costEur                 = $actualCostEur
        savedEur                = $sessionSavedEur
        estimatedUsd            = $m.estimatedUsd
        projectedNext20TurnsUsd = $m.projectedNext20TurnsUsd
    })
}

$globalHit = if ($totalInput -gt 0) { [math]::Round(($totalCache / $totalInput) * 100, 1) } else { 0.0 }
$pluginHit = if ($pluginInput -gt 0) { [math]::Round(($pluginCache / $pluginInput) * 100, 1) } else { 0.0 }

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
        project             = $p.project
        sessions            = $p.sessions
        pluginSessions      = $p.pluginSessions
        turns               = $p.turns
        inputTokens         = $p.inputTokens
        pluginSavedTokens   = $p.pluginSavedTokens
        pluginSavedEur      = [math]::Round($p.pluginSavedEur, 2)
        googleCacheTokens   = $p.googleCacheTokens
        googleCacheSavedEur = [math]::Round($p.googleCacheSavedEur, 2)
        costEur             = [math]::Round($p.costEur, 2)
    })
}

[ordered]@{
    sessionsAnalyzed      = $byConversation.Count
    currency              = "EUR"
    timezone              = "Europe/Paris (UTC+1)"
    pluginInstalledAt     = "2026-11-25 21:51"
    
    # 1. ÉCONOMIES RÉELLES TOKEN OPTIMIZER (Sessions sous plugin)
    pluginSavings         = [ordered]@{
        sessionsCount   = $pluginSessionsCount
        savedTokens     = $pluginSavedTokens
        savedEur        = [math]::Round($pluginSavedEur, 2)
        actualCostEur   = [math]::Round($pluginCostEur, 2)
        cacheHitPct     = $pluginHit
    }

    # 2. CACHE HISTORIQUE GLOBAL GOOGLE (Toutes sessions confondues)
    googleCacheSavings    = [ordered]@{
        savedTokens     = $googleCacheSavedTokens
        savedEur        = [math]::Round($googleCacheSavedEur, 2)
        totalInput      = $totalInput
        cacheHitPct     = $globalHit
        actualCostEur   = [math]::Round($totalCostUsd * $USD_TO_EUR, 2)
    }

    byProject             = @($projectList | Sort-Object pluginSavedEur -Descending)
    byModel               = $modelSummary
    conversations         = @($byConversation)
    topVerboseToolOutputs = @($verboseOutputs | Sort-Object chars -Descending | Select-Object -First 8)
} | ConvertTo-Json -Depth 5
