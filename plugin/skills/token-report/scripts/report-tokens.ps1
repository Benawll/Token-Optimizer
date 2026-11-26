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
# Date officielle d'installation de Token Optimizer (25 nov 2026 21:51 Paris = 20:51 UTC)
$PLUGIN_ACTIVATION_UTC = [datetime]::Parse("2026-11-25T20:51:08Z").ToUniversalTime()

$byModel = @{}
$byConversation = [System.Collections.Generic.List[object]]::new()
$byProject = @{}
$verboseOutputs = [System.Collections.Generic.List[object]]::new()

$totalInput = 0L; $totalCache = 0L; $totalOutput = 0L; $totalCostUsd = 0.0

# 1. MÉTRIQUES EXCLUSIVES TOKEN OPTIMIZER (uniquement sessions sous plugin)
$pluginSessionsCount = 0
$pluginArbitrageSavedEur = 0.0
$pluginCliSavedTokens = 0L
$pluginActualCostEur = 0.0
$pluginInputTokens = 0L
$pluginCacheTokens = 0L

# 2. MÉTRIQUES CACHE NATIF GOOGLE (infrastructure globale présente par défaut)
$googleNativeCacheTokens = 0L
$googleNativeCacheEur = 0.0

foreach ($file in $transcripts) {
    $convId = $file.Directory.Parent.Parent.Name
    $m = Get-TranscriptMetrics -TranscriptPath $file.FullName

    # Détection du projet
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
    $totalInput += $m.inputTokens
    $totalCache += $m.cacheReadTokens
    $totalOutput += $m.outputTokens
    $totalCostUsd += $m.estimatedUsd

    # A. Valeur du cache natif Google (économies d'infrastructure Google, avec ou sans plugin)
    # Gain du cache = tokens en cache valorisés à l'écart de prix plein vs cache (2.85 USD / M)
    $sessionGoogleCacheEur = [math]::Round((($m.cacheReadTokens / 1e6) * 2.85) * $USD_TO_EUR, 2)
    $googleNativeCacheTokens += $m.cacheReadTokens
    $googleNativeCacheEur += $sessionGoogleCacheEur

    # B. Valeur EXCLUSIVE du plugin Token Optimizer
    # Le plugin n'existait pas avant le 25 nov 21:51
    $isPluginActive = ($file.LastWriteTimeUtc -ge $PLUGIN_ACTIVATION_UTC) -or ($sample -match "token-optimizer|Token Optimizer")

    # Calcul de l'économie d'arbitrage de modèle du plugin :
    # Si la session a tourné sur Flash/Hydrogen au lieu de Neon, même avec le cache, Neon facture plus cher
    # Coût Neon avec cache = (Uncached * 3.00 + Cached * 0.15 + Out * 15.00)
    $uncachedIn = [math]::Max(0L, $m.inputTokens - $m.cacheReadTokens)
    $neonCostIfUnoptimizedUsd = ($uncachedIn * 3.00 / 1e6) + ($m.cacheReadTokens * 0.15 / 1e6) + ($m.outputTokens * 15.00 / 1e6)
    $sessionArbitrageEur = if ($isPluginActive) {
        [math]::Max(0.0, [math]::Round(($neonCostIfUnoptimizedUsd - $m.estimatedUsd) * $USD_TO_EUR, 2))
    } else {
        0.0
    }

    # Calcul des tokens CLI compressés/tronqués par le plugin
    $sessionCliSavedTokens = 0L
    foreach ($v in $m.verboseOutputs) {
        $verboseOutputs.Add([ordered]@{
            conversationId = $convId
            project        = $project
            stepIndex      = $v.stepIndex
            chars          = $v.chars
            estTokens      = $v.estTokens
            preview        = $v.preview
        })
        if ($isPluginActive -and $v.estTokens -gt 1000) {
            $sessionCliSavedTokens += ($v.estTokens - 1000)
        }
    }

    if ($isPluginActive) {
        $pluginSessionsCount++
        $pluginArbitrageSavedEur += $sessionArbitrageEur
        $pluginCliSavedTokens += $sessionCliSavedTokens
        $pluginActualCostEur += $actualCostEur
        $pluginInputTokens += $m.inputTokens
        $pluginCacheTokens += $m.cacheReadTokens
    }

    # Aggrégation par projet
    if (-not $byProject.ContainsKey($project)) {
        $byProject[$project] = @{
            project              = $project
            sessions             = 0
            pluginSessions       = 0
            turns                = 0
            costEur              = 0.0
            pluginArbitrageEur   = 0.0
            pluginCliTokens      = 0L
            googleCacheTokens    = 0L
            googleCacheEur       = 0.0
        }
    }
    $byProject[$project].sessions++
    $byProject[$project].turns += $m.turns
    $byProject[$project].costEur += $actualCostEur
    $byProject[$project].googleCacheTokens += $m.cacheReadTokens
    $byProject[$project].googleCacheEur += $sessionGoogleCacheEur

    if ($isPluginActive) {
        $byProject[$project].pluginSessions++
        $byProject[$project].pluginArbitrageEur += $sessionArbitrageEur
        $byProject[$project].pluginCliTokens += $sessionCliSavedTokens
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

    $lastWriteUtc = $file.LastWriteTimeUtc.ToString("o")
    $lastWriteFr = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm")

    $sessionTheorique = $actualCostEur + $sessionArbitrageEur
    $sessionReductionPct = if ($isPluginActive -and $sessionTheorique -gt 0) {
        [math]::Round(($sessionArbitrageEur / $sessionTheorique) * 100, 1)
    } else {
        0.0
    }

    $byConversation.Add([ordered]@{
        conversationId        = $convId
        project               = $project
        isPluginActive        = $isPluginActive
        lastUpdated           = $lastWriteFr
        lastUpdatedIso        = $lastWriteUtc
        plannerTurns          = $m.turns
        inputTokens           = $m.inputTokens
        cacheReadTokens       = $m.cacheReadTokens
        cacheHitPct           = $m.cacheHitPct
        outputTokens          = $m.outputTokens
        costEur               = $actualCostEur
        pluginArbitrageEur    = $sessionArbitrageEur
        reductionPct          = $sessionReductionPct
        pluginCliSavedTokens  = $sessionCliSavedTokens
        googleCacheEur        = $sessionGoogleCacheEur
        projectedNext20Turns  = [math]::Round(($m.projectedNext20TurnsUsd * $USD_TO_EUR), 2)
    })
}

$globalHit = if ($totalInput -gt 0) { [math]::Round(($totalCache / $totalInput) * 100, 1) } else { 0.0 }
$pluginHit = if ($pluginInputTokens -gt 0) { [math]::Round(($pluginCacheTokens / $pluginInputTokens) * 100, 1) } else { 0.0 }

$totalTheoreticalEur = $pluginActualCostEur + $pluginArbitrageSavedEur
$reductionPct = if ($totalTheoreticalEur -gt 0) { [math]::Round(($pluginArbitrageSavedEur / $totalTheoreticalEur) * 100, 1) } else { 0.0 }
$roiMultiplier = if ($pluginActualCostEur -gt 0) { [math]::Round($pluginArbitrageSavedEur / $pluginActualCostEur, 1) } else { 0.0 }

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
        project            = $p.project
        sessions           = $p.sessions
        pluginSessions     = $p.pluginSessions
        turns              = $p.turns
        pluginArbitrageEur = [math]::Round($p.pluginArbitrageEur, 2)
        pluginCliTokens    = $p.pluginCliTokens
        googleCacheTokens  = $p.googleCacheTokens
        googleCacheEur     = [math]::Round($p.googleCacheEur, 2)
        costEur            = [math]::Round($p.costEur, 2)
    })
}

[ordered]@{
    sessionsAnalyzed      = $byConversation.Count
    currency              = "EUR"
    timezone              = "Europe/Paris (UTC+1)"
    pluginInstalledAt     = "2026-11-25 21:51"
    
    # 1. ÉCONOMIES EXCLUSIVES TOKEN OPTIMIZER
    tokenOptimizerGains   = [ordered]@{
        sessionsProtected  = $pluginSessionsCount
        arbitrageSavedEur  = [math]::Round($pluginArbitrageSavedEur, 2)
        cliSavedTokens     = $pluginCliSavedTokens
        pluginActualCost   = [math]::Round($pluginActualCostEur, 2)
        reductionPct       = $reductionPct
        roiMultiplier      = $roiMultiplier
        pluginCacheHitPct  = $pluginHit
    }

    # 2. CACHE NATIF GOOGLE (INFRASTRUCTURE PAR DÉFAUT)
    googleNativeCache     = [ordered]@{
        cachedTokens       = $googleNativeCacheTokens
        cacheHitPct        = $globalHit
        equivalentValueEur = [math]::Round($googleNativeCacheEur, 2)
        totalInputTokens   = $totalInput
    }

    byProject             = @($projectList | Sort-Object pluginArbitrageEur -Descending)
    byModel               = $modelSummary
    conversations         = @($byConversation)
    topVerboseToolOutputs = @($verboseOutputs | Sort-Object chars -Descending | Select-Object -First 8)
} | ConvertTo-Json -Depth 5
