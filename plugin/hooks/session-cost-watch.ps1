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

    $checkFullCost = $Force -or ($invNum -ge 20 -and ($invNum % 5 -eq 0))
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
            foreach ($prop in $loaded.PSObject.Properties) { $state[$prop.Name] = @($prop.Value) }
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
        }
    }

    # 2. Zero-token Cost & Length Predictive Watch
    if ($checkFullCost -and $metrics.turns -gt 0) {
        $milestone = $null
        if ($metrics.turns -ge 120) { $milestone = "T120" }
        elseif ($metrics.turns -ge 70) { $milestone = "T70" }
        elseif ($metrics.turns -ge 35) { $milestone = "T35" }
        elseif ($metrics.lastContextTokens -ge 150000) { $milestone = "CTX150K" }
        elseif ($metrics.estimatedUsd -ge 10.0) { $milestone = "USD10" }
        elseif ($metrics.estimatedUsd -ge 5.0) { $milestone = "USD5" }
        elseif ($metrics.estimatedUsd -ge 2.0) { $milestone = "USD2" }

        if ($Force -or ($milestone -and ($seen -notcontains $milestone))) {
            if ($milestone) { $newKeys.Add($milestone) }
            $invCulture = [System.Globalization.CultureInfo]::InvariantCulture
            $ctxK = [math]::Round($metrics.lastContextTokens / 1000, 1).ToString("0.0", $invCulture)
            $costStr = [math]::Round($metrics.estimatedUsd, 2).ToString("0.00", $invCulture)
            $projStr = [math]::Round($metrics.projectedNext20TurnsUsd, 2).ToString("0.00", $invCulture)
            $messages.Add(('**Token Optimizer — Prévision session ({0} tours)** : contexte **~{1}k** | cache hit **{2}%** | coût est. **${3}** | projection +20 tours : **+${4}**. Lancez `/compact` ou demandez un handoff `token-report` pour ouvrir une nouvelle session sans perte.' -f $metrics.turns, $ctxK, $metrics.cacheHitPct, $costStr, $projStr))
        }
    }

    if ($messages.Count -eq 0) { Write-Output '{}'; exit 0 }

    if (-not $NoSaveState -and $convId -and $newKeys.Count -gt 0) {
        $state[$convId] = @($seen + $newKeys | Select-Object -Unique)
        $state | ConvertTo-Json -Depth 4 | Set-Content -Path $statePath -Encoding UTF8
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
