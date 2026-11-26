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

    $cleanPrompt = if (-not [string]::IsNullOrWhiteSpace($prompt)) {
        ($prompt -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()
    } else { "" }

    # 0. Heavy / Orchestrator startup nudge (turn 1 only, short non-architectural prompt)
    if ($steps -le 1 -and $curModel -match '(?i)(neon|pro|orchestrator|auto)' -and $cleanPrompt.Length -gt 0 -and $cleanPrompt.Length -lt 120 -and ($cleanPrompt -notmatch '(?i)\b(architecture|architect|plan|audit|refonte|redesign|refactor|migration|forensic|root[- ]cause|design system)\b')) {
        $kStart = if ($convId) { "$convId::heavystart" } else { "global::heavystart" }
        if (-not $state.ContainsKey($kStart)) {
            $state[$kStart] = $steps; $stateDirty = $true
            $alerts.Add("💡 Modèle lourd ou Orchestrator actif : passe sur Gemini 4 Hydrogen (Low) fixe pour préserver le cache et ton quota hebdo.")
        }
    }

    # 1. Real-time Cache Health Monitor & Session Guardrails
    if (-not [string]::IsNullOrWhiteSpace($transcriptPath) -and (Test-Path $transcriptPath)) {
        . (Join-Path $PSScriptRoot "..\lib\token-core.ps1")
        $sessionTurns = 0
        foreach ($ln in [System.IO.File]::ReadLines($transcriptPath)) {
            if ($ln -match '"type":"PLANNER_RESPONSE"') { $sessionTurns++ }
        }
        $tailLines = @(Get-Content -Path $transcriptPath -Tail 30 -ErrorAction SilentlyContinue)
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
            $idleSec = ([datetime]::UtcNow - $lastUtc).TotalSeconds

            # 1A. Cold cache (>5 min) on heavy context (>50k tok)
            if ($idleSec -gt 300 -and $lastCtx -gt 50000) {
                $kCliff = if ($convId) { "$convId::cliff" } else { "global::cliff" }
                $lastStepC = if ($state.ContainsKey($kCliff)) { [int]$state[$kCliff] } else { -999 }
                if (($steps - $lastStepC) -ge 8) {
                    $state[$kCliff] = $steps; $stateDirty = $true
                    $alerts.Add("❄️ Cache expiré (>5 min) sur un contexte lourd (>50k tok). Lance /handoff pour repartir sur un fil léger.")
                }
            }

            # 1B. Mid-thread model switch warning (ONLY while cache is warm: <= 300s)
            if ($idleSec -le 300 -and -not [string]::IsNullOrWhiteSpace($curModel) -and $curModel -ne "auto" -and -not [string]::IsNullOrWhiteSpace($lastModel) -and $curModel.ToLowerInvariant() -ne $lastModel.ToLowerInvariant() -and $lastCtx -ge 30000) {
                $kSw = if ($convId) { "$convId::modelswitch" } else { "global::modelswitch" }
                $lastStepS = if ($state.ContainsKey($kSw)) { [int]$state[$kSw] } else { -999 }
                if (($steps - $lastStepS) -ge 6) {
                    $state[$kSw] = $steps; $stateDirty = $true
                    $ctxK = [math]::Round($lastCtx / 1000, 0)
                    $alerts.Add(('**Token Optimizer — Rupture de cache détectée (0 token)** : changement de modèle (`{0}` → `{1}`) sur cache chaud (~{2}k). Règle **1 session = 1 modèle** : lance `/handoff` pour changer de palier.' -f $lastModel, $curModel, $ctxK))
                }
            }

            # 1C. Orchestrator / auto drift (>40k context)
            if (($curModel -match '(?i)(orchestrator|auto)' -or $lastModel -match '(?i)(orchestrator|auto)') -and $lastCtx -gt 40000) {
                $kOrch = if ($convId) { "$convId::orch40k" } else { "global::orch40k" }
                $lastStepO = if ($state.ContainsKey($kOrch)) { [int]$state[$kOrch] } else { -999 }
                if (($steps - $lastStepO) -ge 8) {
                    $state[$kOrch] = $steps; $stateDirty = $true
                    $alerts.Add("⚠️ Contexte > 40k sous Orchestrator : ses bascules internes cassent le cache. Lance /handoff et passe sur Hydrogen (Low) fixe.")
                }
            }

            # 1D. Heavy session / context (>25 turns or >60k tok)
            if ($sessionTurns -gt 25 -or $lastCtx -gt 60000) {
                $kHeavy = if ($convId) { "$convId::heavy60k" } else { "global::heavy60k" }
                $lastStepH = if ($state.ContainsKey($kHeavy)) { [int]$state[$kHeavy] } else { -999 }
                if (($steps - $lastStepH) -ge 10) {
                    $state[$kHeavy] = $steps; $stateDirty = $true
                    $alerts.Add("⚠️ Session lourde (>25 tours ou >60k tok). Lance /handoff pour repartir sur un fil propre.")
                }
            }

            # 1E. Hydrogen escalation on 3 consecutive tool failures or 3 repeated edits on the same file
            if ($curModel -match '(?i)hydrogen' -or $lastModel -match '(?i)hydrogen') {
                $consecFailures = 0
                $editCounts = @{}
                $maxSameEdit = 0
                for ($i = $tailLines.Count - 1; $i -ge 0; $i--) {
                    try { $evItem = $tailLines[$i] | ConvertFrom-Json } catch { continue }
                    if ($evItem.type -eq "TOOL_RESPONSE" -or $evItem.role -eq "tool") {
                        $txt = [string]$evItem.content
                        $isErr = ($evItem.is_error -eq $true) -or ($txt -match '(?i)(Command exited with code [1-9]|Target not found|Error:|Exception:|Failed to)')
                        if ($isErr) { $consecFailures++ } else { break }
                    }
                    if ($evItem.tool_calls) {
                        foreach ($tc in @($evItem.tool_calls)) {
                            $fn = [string]$tc.name
                            if ($fn -match '^(edit_file|write_file|replace_file_content|multi_replace_file_content)$') {
                                $fp = [string]$tc.arguments.Path
                                if (-not $fp) { $fp = [string]$tc.arguments.TargetFile }
                                if ($fp) {
                                    if (-not $editCounts.ContainsKey($fp)) { $editCounts[$fp] = 0 }
                                    $editCounts[$fp]++
                                    if ($editCounts[$fp] -gt $maxSameEdit) { $maxSameEdit = $editCounts[$fp] }
                                }
                            }
                        }
                    }
                }
                if ($consecFailures -ge 3 -or $maxSameEdit -ge 3) {
                    $kEsc = if ($convId) { "$convId::h2n" } else { "global::h2n" }
                    $lastStepE = if ($state.ContainsKey($kEsc)) { [int]$state[$kEsc] } else { -999 }
                    if (($steps - $lastStepE) -ge 6) {
                        $state[$kEsc] = $steps; $stateDirty = $true
                        $alerts.Add("⚠️ Blocage détecté sous Hydrogen (3 tentatives). Lance /handoff puis ouvre une nouvelle session sur Gemini 4 Neon (Medium).")
                    }
                }
            }
        }
    }

    # 2. Workflow Nudge (/grill-me & /btw)
    if (-not [string]::IsNullOrWhiteSpace($cleanPrompt) -and ($cleanPrompt -notmatch '(?i)/(grill-me|btw|plan|swarm|compact|goal|automation|handoff)\b')) {
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
