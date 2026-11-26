$ErrorActionPreference = "SilentlyContinue"
try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Write-Output '{}'; exit 0 }
    $payload = $raw | ConvertFrom-Json

    # Fire only once at the start of a user turn (invocationNum == 1)
    $invNum = [int]($payload.invocationNum)
    if ($invNum -ne 1) { Write-Output '{}'; exit 0 }

    $convId = [string]($payload.conversationId)
    $steps = [int]($payload.initialNumSteps)
    $prompt = [string]($payload.lastUserInput)
    $transcriptPath = [string]($payload.transcriptPath)
    $curModel = [string]($payload.modelName)

    $alerts = [System.Collections.Generic.List[string]]::new()

    $statePath = Join-Path $env:TEMP "token-optimizer-nudge-state.json"
    $state = @{}
    if (Test-Path $statePath) {
        try {
            $loaded = Get-Content -Raw $statePath | ConvertFrom-Json
            foreach ($p in $loaded.PSObject.Properties) { $state[$p.Name] = $p.Value }
        } catch { $state = @{} }
    }
    $stateDirty = $false

    # 1. Real-time Cache Health Monitor (Highbeam-style: 5-min cache cliff & mid-thread model switch)
    if (-not [string]::IsNullOrWhiteSpace($transcriptPath) -and (Test-Path $transcriptPath)) {
        . (Join-Path $PSScriptRoot "..\lib\token-core.ps1")
        $tailLines = @(Get-Content -Path $transcriptPath -Tail 25 -ErrorAction SilentlyContinue)
        $lastEv = $null
        for ($i = $tailLines.Count - 1; $i -ge 0; $i--) {
            if ($tailLines[$i] -match '"type":"PLANNER_RESPONSE"') {
                try { $lastEv = $tailLines[$i] | ConvertFrom-Json; break } catch {}
            }
        }
        if ($lastEv) {
            $lastCtx = [long]$lastEv.input_tokens + [long]$lastEv.cache_read_tokens
            $lastModel = [string]$lastEv.model
            $lastUtc = ConvertTo-UtcDateTime -Value $lastEv.created_at
            $idleMin = ([datetime]::UtcNow - $lastUtc).TotalMinutes
            $ctxK = [math]::Round($lastCtx / 1000, 0)

            # 1A. 5-min implicit cache cliff check
            if ($idleMin -ge 5.0 -and $lastCtx -ge 40000) {
                $kCliff = if ($convId) { "$convId::cliff" } else { "global::cliff" }
                $lastStepC = if ($state.ContainsKey($kCliff)) { [int]$state[$kCliff] } else { -999 }
                if (($steps - $lastStepC) -ge 8) {
                    $state[$kCliff] = $steps; $stateDirty = $true
                    $minStr = [math]::Round($idleMin, 0)
                    $alerts.Add(('**Token Optimizer — Cache Cliff (> 5 min d''inactivité, 0 token)** : dernière requête il y a **{0} min** sur **~{1}k**. Le cache implicite a expiré : pour une nouvelle tâche, ouvrir un nouveau fil ciblé ou lancer `/compact` évite de repayer l''historique à froid.' -f $minStr, $ctxK))
                }
            }

            # 1B. Mid-thread model switch warning
            if (-not [string]::IsNullOrWhiteSpace($curModel) -and $curModel -ne "auto" -and -not [string]::IsNullOrWhiteSpace($lastModel) -and $curModel.ToLowerInvariant() -ne $lastModel.ToLowerInvariant() -and $lastCtx -ge 30000) {
                $kSw = if ($convId) { "$convId::modelswitch" } else { "global::modelswitch" }
                $lastStepS = if ($state.ContainsKey($kSw)) { [int]$state[$kSw] } else { -999 }
                if (($steps - $lastStepS) -ge 6) {
                    $state[$kSw] = $steps; $stateDirty = $true
                    $alerts.Add(('**Token Optimizer — Rupture de cache détectée (0 token)** : changement de modèle (`{0}` → `{1}`) sur un contexte de **~{2}k**. Règle **1 session = 1 modèle** : ouvrez plutôt un nouveau fil ciblé pour changer de palier.' -f $lastModel, $curModel, $ctxK))
                }
            }
        }
    }

    # 2. Workflow Nudge (/grill-me & /btw)
    if (-not [string]::IsNullOrWhiteSpace($prompt) -and ($prompt -notmatch '(?i)/(grill-me|btw|plan|swarm|compact|goal|automation)\b')) {
        $cleanPrompt = ($prompt -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()
        if ($cleanPrompt.Length -ge 25) {
            $needsGrill = ($cleanPrompt.Length -ge 60) -and ($cleanPrompt -match '(?i)\b(refonte|redesign|architecture|refaire|repenser|reconstruct|refactor|migration|cr[ée]er une app|nouveau projet|design system|tableau de bord complet|dashboard complet|from scratch|overhaul)\b')
            $needsBtw = (-not $needsGrill) -and ($steps -ge 20) -and ($cleanPrompt.Length -le 260) -and ($cleanPrompt -match '(?i)\b(d''ailleurs|au fait|petite question|hors[- ]sujet|au passage|pourquoi.*quota|comment marche|c''est quoi la diff[ée]rence|by the way|quick question)\b')

            if ($needsGrill -or $needsBtw) {
                $nudgeType = if ($needsGrill) { "grill" } else { "btw" }
                $key = if ($convId) { "$convId::$nudgeType" } else { "global::$nudgeType" }
                $lastStep = if ($state.ContainsKey($key)) { [int]$state[$key] } else { -999 }
                if (($steps - $lastStep) -ge 12) {
                    $state[$key] = $steps; $stateDirty = $true
                    if ($needsGrill) {
                        $alerts.Add("**Token Optimizer — Cadrage recommandé (0 token)** : demande structurante détectée. Pensez à **`/grill-me`** pour verrouiller les choix en amont et éviter des allers-retours coûteux.")
                    } else {
                        $alerts.Add("**Token Optimizer — Question parallèle (0 token)** : dans une session longue, pensez à **`/btw`** pour poser un détour rapide sans alourdir le contexte principal.")
                    }
                }
            }
        }
    }

    if ($stateDirty) {
        [System.IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 3), [System.Text.UTF8Encoding]::new($false))
    }

    if ($alerts.Count -eq 0) { Write-Output '{}'; exit 0 }

    @{
        injectSteps = @(@{
            systemMessage = @{
                systemMessage = ""
                metadata      = @{ user_markdown = ($alerts -join "`n") }
            }
        })
    } | ConvertTo-Json -Depth 6 -Compress | Write-Output
    exit 0
}
catch {
    Write-Output '{}'
    exit 0
}
