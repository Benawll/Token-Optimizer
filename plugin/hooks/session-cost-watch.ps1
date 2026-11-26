param(
    [switch]$Force,
    [switch]$NoSaveState
)

$ErrorActionPreference = "SilentlyContinue"
try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Write-Output '{}'; exit 0 }
    $payload = $raw | ConvertFrom-Json
    $invNum = [int]($payload.invocationNum)
    $convId = [string]($payload.conversationId)
    $transcriptPath = [string]($payload.transcriptPath)

    if ([string]::IsNullOrWhiteSpace($transcriptPath) -or -not (Test-Path $transcriptPath)) {
        Write-Output '{}'
        exit 0
    }

    . (Join-Path $PSScriptRoot "..\lib\token-core.ps1")

    $checkFullCost = $Force -or ($invNum -eq 1) -or ($invNum -ge 10 -and ($invNum % 5 -eq 0))
    $metrics = if ($checkFullCost) {
        Get-TranscriptMetrics -TranscriptPath $transcriptPath
    }
    else {
        Get-TranscriptMetrics -TranscriptPath $transcriptPath -TailOnlyForLoops
    }

    $statePath = Join-Path $env:TEMP "token-optimizer-watch-state.json"
    $state = @{}
    if (Test-Path $statePath) {
        try {
            $loaded = Get-Content -Raw $statePath | ConvertFrom-Json
            foreach ($prop in $loaded.PSObject.Properties) {
                $arr = [System.Collections.Generic.List[string]]::new()
                foreach ($v in @($prop.Value)) {
                    foreach ($inner in @($v)) {
                        $sv = [string]$inner
                        if (-not [string]::IsNullOrWhiteSpace($sv)) { $arr.Add($sv) }
                    }
                }
                $state[$prop.Name] = @($arr)
            }
        }
        catch { $state = @{} }
    }
    $seen = if ($convId -and $state.ContainsKey($convId)) { @($state[$convId]) } else { @() }
    $newKeys = [System.Collections.Generic.List[string]]::new()
    $messages = [System.Collections.Generic.List[string]]::new()

    # 1. Zero-token Failure Loop Detector (runs on every invocation)
    if ($metrics.loopDetected) {
        $loopWindow = "LOOP_" + [math]::Floor($metrics.latestGenericStep / 6)
        if ($Force -or ($seen -notcontains $loopWindow)) {
            $newKeys.Add($loopWindow)
            $messages.Add(('**Token Optimizer — Boucle d''échec détectée ({0} erreurs rapprochées)** : évitez de brûler des tours en boucle — lancez `/plan` pour recadrer, `/fork` avant un autre essai, ou passez temporairement sur **Neon high**.' -f $metrics.recentFailureCount))
            if (-not $NoSaveState) { Write-TokenOptimizerEvent -EventType "loop_guard" -SavedTokens 0 -ConversationId $convId -Details @{ window = $loopWindow } }
        }
    }

    # 2. Zero-token Cost & Length Predictive Watch
    if ($checkFullCost -and $metrics.turns -gt 0) {
        $milestone = $null
        if ($metrics.turns -ge 40) { $milestone = "T40" }
        elseif ($metrics.turns -ge 25) { $milestone = "T25" }
        elseif ($metrics.turns -ge 15) { $milestone = "T15" }
        elseif ($metrics.lastContextTokens -ge 85000) { $milestone = "CTX85K" }
        elseif ($metrics.lastContextTokens -ge 60000) { $milestone = "CTX60K" }
        elseif ($metrics.estimatedUsd -ge 10.0) { $milestone = "USD10" }
        elseif ($metrics.estimatedUsd -ge 5.0) { $milestone = "USD5" }
        elseif ($metrics.estimatedUsd -ge 2.0) { $milestone = "USD2" }

        if ($Force -or ($milestone -and ($seen -notcontains $milestone))) {
            if ($milestone) { $newKeys.Add($milestone) }
            $invCulture = [System.Globalization.CultureInfo]::InvariantCulture
            $ctxK = [math]::Round($metrics.lastContextTokens / 1000, 1).ToString("0.0", $invCulture)
            $costStr = [math]::Round($metrics.estimatedUsd, 2).ToString("0.00", $invCulture)
            $projStr = [math]::Round($metrics.projectedNext20TurnsUsd, 2).ToString("0.00", $invCulture)
            $messages.Add(('**Token Optimizer — Prévision session ({0} tours)** : contexte **~{1}k** | cache hit **{2}%** | coût est. **${3}** | projection +20 tours : **+${4}**. Lancez `/handoff` pour repartir sur un fil propre.' -f $metrics.turns, $ctxK, $metrics.cacheHitPct, $costStr, $projStr))
            if (-not $NoSaveState -and $milestone) { Write-TokenOptimizerEvent -EventType "cost_watch" -SavedTokens 0 -ConversationId $convId -Details @{ milestone = $milestone } }
        }

        # 3. Zero-token Cache Thrashing Guard (model switches on large contexts > 60k)
        $cd = $metrics.cacheDiagnostics
        if ($cd -and $metrics.lastContextTokens -ge 60000 -and $cd.modelSwitches -ge 3) {
            $thrashKey = if ($cd.modelSwitches -ge 15) { "THRASH_15" } elseif ($cd.modelSwitches -ge 10) { "THRASH_10" } elseif ($cd.modelSwitches -ge 6) { "THRASH_6" } else { "THRASH_3" }
            if ($Force -or ($seen -notcontains $thrashKey)) {
                $newKeys.Add($thrashKey)
                $invC = [System.Globalization.CultureInfo]::InvariantCulture
                $ctxK2 = [math]::Round($metrics.lastContextTokens / 1000, 0).ToString("0", $invC)
                $swK = [math]::Round($cd.switchUncachedTokens / 1000, 0).ToString("0", $invC)
                $messages.Add(('**Token Optimizer — Alerte Cache Thrashing (0 token)** : **{0} changements de modèle** sur un contexte de **~{1}k** ont déjà coûté **~{2}k tokens non cachés**. Évitez les allers-retours courts sur gros contexte : restez sur le modèle chaud ou lancez `/compact` / une nouvelle session avant de changer de palier.' -f $cd.modelSwitches, $ctxK2, $swK))
                if (-not $NoSaveState) { Write-TokenOptimizerEvent -EventType "cost_watch" -SavedTokens 0 -ConversationId $convId -Details @{ milestone = $thrashKey } }
            }
        }
    }

    if ($messages.Count -eq 0) { Write-Output '{}'; exit 0 }

    if (-not $NoSaveState -and $convId -and $newKeys.Count -gt 0) {
        $merged = @(@($seen) + @($newKeys) | Select-Object -Unique)
        $state[$convId] = [string[]]$merged
        [System.IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
    }

    $md = $messages -join "`n"
    @{
        injectSteps = @(@{ systemMessage = @{ systemMessage = ""; metadata = @{ user_markdown = $md } } })
    } | ConvertTo-Json -Depth 6 -Compress | Write-Output
    exit 0
}
catch {
    Write-Output '{}'
    exit 0
}
