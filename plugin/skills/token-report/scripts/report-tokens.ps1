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
    @(
        Get-ChildItem -Path $brainRoot -Directory |
            ForEach-Object { Join-Path $_.FullName ".system_generated\logs\transcript.jsonl" } |
            Where-Object { Test-Path $_ } |
            ForEach-Object { Get-Item $_ } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $Latest
    )
}

function Get-DynamicPluginInstallUtc {
    param([object[]]$TranscriptFiles)

    $candidates = [System.Collections.Generic.List[datetime]]::new()
    $configRoot = Join-Path $env:USERPROFILE ".gemini\config"
    $metaPath = Join-Path $configRoot "token-optimizer-meta.json"

    if (Test-Path $metaPath) {
        try {
            $meta = Get-Content -Raw -Path $metaPath -ErrorAction Stop | ConvertFrom-Json
            if ($meta.installedAtUtc) {
                return (ConvertTo-UtcDateTime -Value $meta.installedAtUtc).ToUniversalTime()
            }
        }
        catch {}
    }

    $pluginManifest = Join-Path $configRoot "plugins\token-optimizer\plugin.json"
    if (Test-Path $pluginManifest) {
        $candidates.Add((Get-Item $pluginManifest).CreationTimeUtc)
    }

    $markerRegex = 'Token Optimizer — Audit automatique|Token Optimizer — Prévision|Boucle d''échec détectée|lecture brute non bornée détectée|\[Token Optimizer:\s*\d+\s*->\s*\d+\s*lignes'
    foreach ($tf in $TranscriptFiles) {
        foreach ($ln in [System.IO.File]::ReadLines($tf.FullName)) {
            if ($ln -notmatch $markerRegex) { continue }
            if ($ln -notmatch '"type":"(GENERIC|SYSTEM_MESSAGE)"') { continue }
            if ($ln -match 'Showing lines \d+-\d+|\$resp\s*=') { continue }
            if ($ln -match '"created_at":"([^"]+)"') {
                $dt = ConvertTo-UtcDateTime -Value $matches[1] -FallbackUtc $tf.LastWriteTimeUtc
                $candidates.Add($dt)
                break
            }
        }
    }

    if ($candidates.Count -eq 0) {
        return (Get-Date).ToUniversalTime()
    }

    $earliest = ($candidates | Sort-Object | Select-Object -First 1).ToUniversalTime()

    if (-not (Test-Path $metaPath)) {
        try {
            if (-not (Test-Path $configRoot)) {
                New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
            }
            $metaObj = [ordered]@{ installedAtUtc = $earliest.ToString("o") } | ConvertTo-Json
            [System.IO.File]::WriteAllText($metaPath, $metaObj, [System.Text.UTF8Encoding]::new($false))
        }
        catch {}
    }

    return $earliest
}

function Get-TranscriptProjectName {
    param(
        [string]$TranscriptPath,
        [hashtable]$CanonicalNames
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    $headLines = Get-Content -Path $TranscriptPath -TotalCount 60 -ErrorAction SilentlyContinue
    $winRegex = '(?i)(?:file:///|(?<![a-zA-Z0-9_]))([C-Z]):[/\\]+([^"''\r\n<>|?*`{}\[\](),;=]+)'

    foreach ($ln in $headLines) {
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        try { $ev = $ln | ConvertFrom-Json } catch { continue }
        $tcJson = if ($ev.tool_calls) { $ev.tool_calls | ConvertTo-Json -Compress -Depth 4 } else { "" }
        $blob = ([string]$ev.content) + " " + $tcJson

        foreach ($m in [regex]::Matches($blob, $winRegex)) {
            $rawRest = $m.Groups[2].Value
            try { $rawRest = [Uri]::UnescapeDataString($rawRest) } catch {}
            $normRest = $rawRest -replace '\\+', '/'
            $segs = @($normRest -split '/' | Where-Object { $_ -and $_.Trim() -ne '' })
            if ($segs.Count -eq 0) { continue }

            $first = $segs[0].Trim()
            $pick = $null

            if ($first -match '^(?i)(Users|Windows|Program Files|Program Files \(x86\)|ProgramData|AppData|temp|tmp|PerfLogs|\$Recycle\.Bin)$') {
                if ($first -ieq 'Windows' -and $segs.Count -ge 3 -and $segs[1] -ieq 'System32' -and $segs[2] -notmatch '\.(exe|dll|cmd|ps1|bat)$') {
                    $pick = $segs[2].Trim()
                }
                elseif ($first -ieq 'Users' -and $segs.Count -ge 3) {
                    $uSub = $segs[2].Trim()
                    if ($uSub -match '^(?i)(Desktop|Documents|Projects|Repos|Dev|Work|Workspace|GitHub|Source)$' -and $segs.Count -ge 4) {
                        $pick = $segs[3].Trim()
                    }
                    elseif ($uSub -notmatch '^(?i)(\.gemini|AppData|\.vscode|\.antigravity|\.cursor|Downloads|Temp|\.ssh|\.npm|\.cache)$') {
                        $pick = $uSub
                    }
                }
            }
            else {
                $pick = $first
            }

            if (-not $pick) { continue }
            if ($pick -match '\.[a-zA-Z0-9]{1,5}$') { continue }
            if ($pick -match '^(?i)(node_modules|\.git|system_generated|brain|antigravity|temp|tmp)$') { continue }
            if ($pick.Length -lt 2 -or $pick.Length -gt 48) { continue }

            $candidates.Add($pick)
        }
    }

    if ($candidates.Count -eq 0) { return "Général" }

    $winner = ($candidates | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
    $lowerKey = $winner.ToLowerInvariant()

    if (-not $CanonicalNames.ContainsKey($lowerKey)) {
        $CanonicalNames[$lowerKey] = $winner
    }
    elseif ($winner -cmatch '[A-Z]' -and $CanonicalNames[$lowerKey] -cnotmatch '[A-Z]') {
        $CanonicalNames[$lowerKey] = $winner
    }

    return $CanonicalNames[$lowerKey]
}

function Get-AntigravityLiveQuota {
    $res = [ordered]@{
        available        = $false
        source           = "unavailable"
        inferredTierHint = "auto"
        overusageActive  = $false
        useAiCredits     = $false
        remainingCredits = $null
        upgradeUri       = ""
        gemini           = [ordered]@{
            weeklyPct     = $null
            weeklyReset   = $null
            weeklyDesc    = ""
            fiveHourPct   = $null
            fiveHourReset = $null
            fiveHourDesc  = ""
        }
        claudeGpt        = [ordered]@{
            weeklyPct   = $null
            fiveHourPct = $null
        }
    }

    # Check non-secret overage config flag if present
    $cfgRoot = Join-Path $env:USERPROFILE ".gemini"
    foreach ($cfgPath in @(
        (Join-Path $cfgRoot "config\config.json"),
        (Join-Path $cfgRoot "antigravity-cli\settings.json")
    )) {
        if (Test-Path $cfgPath) {
            try {
                $cObj = Get-Content -Raw -Path $cfgPath | ConvertFrom-Json
                if ($null -ne $cObj.useAiCredits) {
                    $res.useAiCredits = [bool]$cObj.useAiCredits
                }
            }
            catch {}
        }
    }

    $agyCmd = Get-Command agy -ErrorAction SilentlyContinue
    if (-not $agyCmd) { return $res }

    try {
        $uRaw = & $agyCmd.Source -p "/usage" --output-format json --print-timeout 6s 2>$null
        $uJsonLine = ($uRaw | Where-Object { $_ -match '^\{' } | Select-Object -Last 1)
        if ($uJsonLine) {
            $uObj = $uJsonLine | ConvertFrom-Json
            if ($uObj.status -eq "SUCCESS" -and $uObj.command.data.groups) {
                $res.available = $true
                $res.source = "agy-cli"
                foreach ($grp in @($uObj.command.data.groups)) {
                    $gName = [string]$grp.name
                    foreach ($b in @($grp.buckets)) {
                        $remPct = if ($null -ne $b.remaining_fraction) { [math]::Round([double]$b.remaining_fraction * 100, 1) } else { $null }
                        $rst = if ($b.reset_time -and $b.reset_time -notmatch '^1970-') { [string]$b.reset_time } else { $null }
                        if ($gName -match 'Gemini') {
                            if ($b.window -eq "weekly") {
                                $res.gemini.weeklyPct = $remPct
                                $res.gemini.weeklyReset = $rst
                                $res.gemini.weeklyDesc = [string]$b.description
                            }
                            elseif ($b.window -eq "5h") {
                                $res.gemini.fiveHourPct = $remPct
                                $res.gemini.fiveHourReset = $rst
                                $res.gemini.fiveHourDesc = [string]$b.description
                            }
                        }
                        elseif ($gName -match 'Claude|GPT') {
                            if ($b.window -eq "weekly") { $res.claudeGpt.weeklyPct = $remPct }
                            elseif ($b.window -eq "5h") { $res.claudeGpt.fiveHourPct = $remPct }
                        }
                    }
                }
            }
        }
    }
    catch {}

    try {
        $cRaw = & $agyCmd.Source -p "/credits" --output-format json --print-timeout 6s 2>$null
        $cJsonLine = ($cRaw | Where-Object { $_ -match '^\{' } | Select-Object -Last 1)
        if ($cJsonLine) {
            $cObj = $cJsonLine | ConvertFrom-Json
            if ($cObj.status -eq "SUCCESS" -and $cObj.command.data) {
                $res.remainingCredits = [double]($cObj.command.data.remaining_credits)
                $res.upgradeUri = [string]$cObj.command.data.upgrade_uri
            }
        }
    }
    catch {}

    # Detect active overusage cleanly
    $hitLimit = ($null -ne $res.gemini.weeklyPct -and $res.gemini.weeklyPct -le 0) -or ($null -ne $res.gemini.fiveHourPct -and $res.gemini.fiveHourPct -le 0)
    $hasCreds = ($null -ne $res.remainingCredits -and $res.remainingCredits -gt 0) -or $res.useAiCredits
    $res.overusageActive = ($hitLimit -and $hasCreds)

    if ($null -ne $res.gemini.fiveHourPct -and $res.gemini.fiveHourPct -ge 0) {
        # Having a 5-hour rolling sprint bucket alongside weekly indicates a rolling paid tier when confirmed
        $res.inferredTierHint = if ($res.remainingCredits -gt 0) { "paid_with_credits" } else { "rolling_5h_weekly" }
    }

    return $res
}

function Get-MechanismsState {
    $cfgRoot = Join-Path $env:USERPROFILE ".gemini\config"
    $fullMcpPath = Join-Path $cfgRoot "mcp_profiles\full-catalog.json"
    $curMcpPath = Join-Path $cfgRoot "mcp_config.json"

    $catalogServers = @()
    $activeServers = @()
    if (Test-Path $fullMcpPath) {
        try {
            $fj = Get-Content -Raw $fullMcpPath | ConvertFrom-Json
            if ($fj.mcpServers) { $catalogServers = @($fj.mcpServers.PSObject.Properties.Name) }
        } catch {}
    }
    if (Test-Path $curMcpPath) {
        try {
            $cj = Get-Content -Raw $curMcpPath | ConvertFrom-Json
            if ($cj.mcpServers) { $activeServers = @($cj.mcpServers.PSObject.Properties.Name) }
        } catch {}
    }
    if ($catalogServers.Count -eq 0) { $catalogServers = $activeServers }
    $disabledServers = @($catalogServers | Where-Object { $activeServers -notcontains $_ })

    # Sandbox CLI logs currently present
    $sandboxDir = Join-Path $env:TEMP "to-sandbox"
    $sandboxLogs = @()
    $sandboxBytes = 0L
    if (Test-Path $sandboxDir) {
        $sandboxLogs = @(Get-ChildItem -Path $sandboxDir -Filter "cmd-*.log" -File -ErrorAction SilentlyContinue)
        foreach ($sf in $sandboxLogs) { $sandboxBytes += $sf.Length }
    }

    # Historical watch-state detections (cleanly parses even previously concatenated keys)
    $watchStatePath = Join-Path $env:TEMP "token-optimizer-watch-state.json"
    $histLoops = 0
    $histMilestones = 0
    if (Test-Path $watchStatePath) {
        try {
            $ws = Get-Content -Raw $watchStatePath | ConvertFrom-Json
            foreach ($prop in $ws.PSObject.Properties) {
                $joined = (@($prop.Value) -join " ")
                $histLoops += ([regex]::Matches($joined, 'LOOP_\d+')).Count
                $histMilestones += ([regex]::Matches($joined, '(T\d+|CTX\d+K|USD\d+)')).Count
            }
        } catch {}
    }

    # Append-only telemetry ledger
    $ledgerPath = Join-Path $cfgRoot "token-optimizer-events.jsonl"
    $ledger = @{
        events = 0; cliDenials = 0; cliDenyTokens = 0L
        cliCompressions = 0; cliCompressTokens = 0L
        outlines = 0; outlineTokens = 0L
        mcpTrims = 0; setupApplies = 0; sessionAudits = 0
        loopGuards = 0; costWatches = 0
        byConv = @{}
    }
    if (Test-Path $ledgerPath) {
        foreach ($ln in [System.IO.File]::ReadLines($ledgerPath)) {
            if ([string]::IsNullOrWhiteSpace($ln)) { continue }
            try { $ev = $ln | ConvertFrom-Json } catch { continue }
            $ledger.events++
            $tok = [long]($ev.savedTokens)
            $cid = [string]($ev.convId)
            if ($cid) {
                if (-not $ledger.byConv.ContainsKey($cid)) {
                    $ledger.byConv[$cid] = @{ denials = 0; compresses = 0; outlines = 0; savedTokens = 0L; zeroTokWatches = 0 }
                }
            }
            switch ([string]$ev.event) {
                "cli_deny" {
                    $ledger.cliDenials++; $ledger.cliDenyTokens += $tok
                    if ($cid) { $ledger.byConv[$cid].denials++; $ledger.byConv[$cid].savedTokens += $tok }
                }
                "cli_compress" {
                    $ledger.cliCompressions++; $ledger.cliCompressTokens += $tok
                    if ($cid) { $ledger.byConv[$cid].compresses++; $ledger.byConv[$cid].savedTokens += $tok }
                }
                "code_outline" {
                    $ledger.outlines++; $ledger.outlineTokens += $tok
                    if ($cid) { $ledger.byConv[$cid].outlines++; $ledger.byConv[$cid].savedTokens += $tok }
                }
                "mcp_trim"      { $ledger.mcpTrims++ }
                "setup_apply"   { $ledger.setupApplies++ }
                "session_audit" {
                    $ledger.sessionAudits++
                    if ($cid) { $ledger.byConv[$cid].zeroTokWatches++ }
                }
                "loop_guard"    {
                    $ledger.loopGuards++
                    if ($cid) { $ledger.byConv[$cid].zeroTokWatches++ }
                }
                "cost_watch"    {
                    $ledger.costWatches++
                    if ($cid) { $ledger.byConv[$cid].zeroTokWatches++ }
                }
            }
        }
    }

    return [ordered]@{
        mcpCatalogCount   = $catalogServers.Count
        mcpActiveCount    = $activeServers.Count
        mcpActive         = @($activeServers)
        mcpDisabled       = @($disabledServers)
        mcpDisabledCount  = $disabledServers.Count
        sandboxFiles      = $sandboxLogs.Count
        sandboxBytes      = $sandboxBytes
        histLoops         = $histLoops
        histMilestones    = $histMilestones
        ledger            = $ledger
    }
}

$USD_TO_EUR = 0.92
$pluginInstalledUtc = Get-DynamicPluginInstallUtc -TranscriptFiles $transcripts
$tzInfo = [System.TimeZoneInfo]::Local
$tzOffset = (Get-Date).ToString("zzz")
$timezoneLabel = "$($tzInfo.StandardName) (UTC$tzOffset)"

$liveQuota = Get-AntigravityLiveQuota
$mechState = Get-MechanismsState
$ledger = $mechState.ledger

$canonicalProjects = @{}
# Map subagent conversationId -> parent conversationId using Antigravity's native subagents index
$subagentParentMap = @{}
foreach ($bDir in @(Get-ChildItem -Path $brainRoot -Directory -ErrorAction SilentlyContinue)) {
    $subFolder = Join-Path $bDir.FullName ".system_generated\subagents"
    if (Test-Path $subFolder) {
        foreach ($sf in @(Get-ChildItem -Path $subFolder -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
            $subagentParentMap[$sf.BaseName] = $bDir.Name
        }
    }
}

# Pre-resolve project names (Pass A) including parent transcripts so subagents always inherit cleanly
$directProjectMap = @{}
foreach ($tf in $transcripts) {
    $cid = $tf.Directory.Parent.Parent.Name
    $directProjectMap[$cid] = Get-TranscriptProjectName -TranscriptPath $tf.FullName -CanonicalNames $canonicalProjects
}
foreach ($tf in $transcripts) {
    $cid = $tf.Directory.Parent.Parent.Name
    if ($subagentParentMap.ContainsKey($cid)) {
        $parentCid = $subagentParentMap[$cid]
        if (-not $directProjectMap.ContainsKey($parentCid)) {
            $pTrans = Join-Path $brainRoot "$parentCid\.system_generated\logs\transcript.jsonl"
            if (Test-Path $pTrans) {
                $directProjectMap[$parentCid] = Get-TranscriptProjectName -TranscriptPath $pTrans -CanonicalNames $canonicalProjects
            }
        }
    }
}

$byModel = @{}
$byProject = @{}
$byConversation = [System.Collections.Generic.List[object]]::new()
$verboseOutputs = [System.Collections.Generic.List[object]]::new()

$preAll = @{
    turns = 0; knownTurns = 0; uncached = 0L; cached = 0L; out = 0L; raw = 0L; usd = 0.0
    light = 0; mid = 0; heavy = 0; unknown = 0
    switches = 0; switchUnc = 0L; idles = 0; idleUnc = 0L; breaks = 0; breakUnc = 0L
}
$postAll = @{
    sessions = 0; turns = 0; knownTurns = 0; uncached = 0L; cached = 0L; out = 0L; raw = 0L; usd = 0.0
    light = 0; mid = 0; heavy = 0; unknown = 0
    switches = 0; switchUnc = 0L; idles = 0; idleUnc = 0L; breaks = 0; breakUnc = 0L
}
$hooksAll = @{
    cliDenials = 0; cliCompressions = 0; cliLinesSaved = 0
    sessionAudits = 0; costWatchAlerts = 0; modelAuditBadges = 0
}

foreach ($file in $transcripts) {
    $convId = $file.Directory.Parent.Parent.Name
    $project = if ($directProjectMap.ContainsKey($convId)) { $directProjectMap[$convId] } else { "Général" }
    $isSubagent = $false
    $parentConvId = ""
    if ($subagentParentMap.ContainsKey($convId)) {
        $isSubagent = $true
        $parentConvId = $subagentParentMap[$convId]
        if ($directProjectMap.ContainsKey($parentConvId) -and $directProjectMap[$parentConvId] -ne "Général") {
            $project = $directProjectMap[$parentConvId]
        }
    }
    $m = Get-TranscriptMetrics -TranscriptPath $file.FullName -PluginInstalledUtc $pluginInstalledUtc

    $pre = $m.pre
    $post = $m.post
    $hk = $m.hooks

    $preAll.turns += $pre.turns; $preAll.knownTurns += $pre.knownTurns
    $preAll.uncached += $pre.uncachedTokens; $preAll.cached += $pre.cacheReadTokens
    $preAll.out += $pre.outputTokens; $preAll.raw += $pre.rawTokens; $preAll.usd += $pre.estimatedUsd
    $preAll.light += $pre.lightTurns; $preAll.mid += $pre.midTurns
    $preAll.heavy += $pre.heavyTurns; $preAll.unknown += $pre.unknownTurns
    $preAll.switches += $pre.modelSwitches; $preAll.switchUnc += $pre.switchUncachedTokens
    $preAll.idles += $pre.idleMisses; $preAll.idleUnc += $pre.idleUncachedTokens
    $preAll.breaks += $pre.prefixBreaks; $preAll.breakUnc += $pre.prefixBreakUncachedTokens
    if (-not $preDepthAll) {
        $preDepthAll = @{
            "1-15" = @{ turns = 0; uncached = 0L; cached = 0L; out = 0L; raw = 0L }
            "16-30" = @{ turns = 0; uncached = 0L; cached = 0L; out = 0L; raw = 0L }
            "31-60" = @{ turns = 0; uncached = 0L; cached = 0L; out = 0L; raw = 0L }
            "61+" = @{ turns = 0; uncached = 0L; cached = 0L; out = 0L; raw = 0L }
        }
        $postDepthAll = @{
            "1-15" = @{ turns = 0 }
            "16-30" = @{ turns = 0 }
            "31-60" = @{ turns = 0 }
            "61+" = @{ turns = 0 }
        }
    }
    foreach ($dk in @("1-15", "16-30", "31-60", "61+")) {
        if ($pre.byDepth -and $pre.byDepth[$dk]) {
            $preDepthAll[$dk].turns += $pre.byDepth[$dk].turns
            $preDepthAll[$dk].uncached += $pre.byDepth[$dk].uncached
            $preDepthAll[$dk].cached += $pre.byDepth[$dk].cached
            $preDepthAll[$dk].out += $pre.byDepth[$dk].out
            $preDepthAll[$dk].raw += $pre.byDepth[$dk].raw
        }
        if ($post.byDepth -and $post.byDepth[$dk]) {
            $postDepthAll[$dk].turns += $post.byDepth[$dk].turns
        }
    }

    if ($post.turns -gt 0) { $postAll.sessions++ }
    $postAll.turns += $post.turns; $postAll.knownTurns += $post.knownTurns
    $postAll.uncached += $post.uncachedTokens; $postAll.cached += $post.cacheReadTokens
    $postAll.out += $post.outputTokens; $postAll.raw += $post.rawTokens; $postAll.usd += $post.estimatedUsd
    $postAll.light += $post.lightTurns; $postAll.mid += $post.midTurns
    $postAll.heavy += $post.heavyTurns; $postAll.unknown += $post.unknownTurns
    $postAll.switches += $post.modelSwitches; $postAll.switchUnc += $post.switchUncachedTokens
    $postAll.idles += $post.idleMisses; $postAll.idleUnc += $post.idleUncachedTokens
    $postAll.breaks += $post.prefixBreaks; $postAll.breakUnc += $post.prefixBreakUncachedTokens

    $hooksAll.cliDenials += $hk.cliDenials
    $hooksAll.cliCompressions += $hk.cliCompressions
    $hooksAll.cliLinesSaved += $hk.cliLinesSaved
    $hooksAll.sessionAudits += $hk.sessionAudits
    $hooksAll.costWatchAlerts += $hk.costWatchAlerts
    $hooksAll.modelAuditBadges += $hk.modelAuditBadges

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

    foreach ($k in $m.byModel.Keys) {
        $src = $m.byModel[$k]
        if (-not $byModel.ContainsKey($k)) {
            $byModel[$k] = @{
                turns           = 0
                tier            = $src.tier
                weight          = $src.weight
                inputTokens     = 0L
                cacheReadTokens = 0L
                outputTokens    = 0L
                estimatedUsd    = 0.0
            }
        }
        $byModel[$k].turns += $src.turns
        $byModel[$k].inputTokens += $src.inputTokens
        $byModel[$k].cacheReadTokens += $src.cacheReadTokens
        $byModel[$k].outputTokens += $src.outputTokens
        $byModel[$k].estimatedUsd += $src.estimatedUsd
    }

    $pluginStatus = if ($post.turns -gt 0 -and $pre.turns -gt 0) {
        "mixed"
    } elseif ($post.turns -gt 0) {
        "active"
    } else {
        "before"
    }

    # Combine transcript-measured hook tokens with real ledger tokens for this session
    $convLedger = if ($ledger.byConv.ContainsKey($convId)) { $ledger.byConv[$convId] } else { $null }
    $convHookTokens = ([long]$hk.cliLinesSaved * 10L) + ([long]$hk.cliDenials * 8000L)
    if ($convLedger -and $convLedger.savedTokens -gt $convHookTokens) {
        $convHookTokens = [long]$convLedger.savedTokens
    }

    # Check if this session is on a non-3D/Unity workspace benefiting from MCP schema trimming
    $is3dProj = $project -match '(?i)(unity|blender|godot|unreal|3d)'
    $convMcpSavedTokens = if ($post.turns -gt 0 -and -not $is3dProj -and $mechState.mcpDisabledCount -gt 0) {
        # Conservative 1,500 schema tokens avoided per disabled heavy MCP server per turn
        [long]($post.turns * $mechState.mcpDisabledCount * 1500)
    } else {
        0L
    }

    $convWatchCount = $hk.sessionAudits + $hk.costWatchAlerts
    if ($convLedger) { $convWatchCount = [math]::Max($convWatchCount, $convLedger.zeroTokWatches) }

    $hookTotalConv = $hk.cliDenials + $hk.cliCompressions + $convWatchCount + $hk.modelAuditBadges

    if (-not $byProject.ContainsKey($project)) {
        $byProject[$project] = @{
            project      = $project
            sessions     = 0
            postSessions = 0
            totalTurns   = 0
            postTurns    = 0
            postRaw      = 0L
            postUncached = 0L
            postCached   = 0L
            postOutput   = 0L
            postCostUsd  = 0.0
            directSaved  = 0L
            mcpSaved     = 0L
            hookHits     = 0
        }
    }
    $projRec = $byProject[$project]
    $projRec.sessions++
    if ($post.turns -gt 0) { $projRec.postSessions++ }
    $projRec.totalTurns += $m.turns
    $projRec.postTurns += $post.turns
    $projRec.postRaw += $post.rawTokens
    $projRec.postUncached += $post.uncachedTokens
    $projRec.postCached += $post.cacheReadTokens
    $projRec.postOutput += $post.outputTokens
    $projRec.postCostUsd += $post.estimatedUsd
    $projRec.directSaved += $convHookTokens
    $projRec.mcpSaved += $convMcpSavedTokens
    $projRec.hookHits += $hookTotalConv

    $lastUtc = if ($m.lastEventUtc) { $m.lastEventUtc } else { $file.LastWriteTimeUtc }
    $lastLocal = $lastUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm")
    $postCtxTok = $post.uncachedTokens + $post.cacheReadTokens
    $postCachePct = if ($postCtxTok -gt 0) { [math]::Round(($post.cacheReadTokens / $postCtxTok) * 100, 1) } else { $m.cacheHitPct }

    $byConversation.Add([ordered]@{
        conversationId          = $convId
        project                 = $project
        isSubagent              = $isSubagent
        parentConversationId    = $parentConvId
        pluginStatus            = $pluginStatus
        lastUpdated             = $lastLocal
        lastUpdatedIso          = $lastUtc.ToString("o")
        lastModel               = $m.lastModel
        lastContextTokens       = $m.lastContextTokens
        totalTurns              = $m.turns
        preTurns                = $pre.turns
        postTurns               = $post.turns
        postRawTokens           = $post.rawTokens
        postUncachedTokens      = $post.uncachedTokens
        postCacheReadTokens     = $post.cacheReadTokens
        postOutputTokens        = $post.outputTokens
        postCacheHitPct         = $postCachePct
        postModelSwitches       = $post.modelSwitches
        postSwitchUncached      = $post.switchUncachedTokens
        postIdleMisses          = $post.idleMisses
        postIdleUncached        = $post.idleUncachedTokens
        postPrefixBreaks        = $post.prefixBreaks
        postBreakUncached       = $post.prefixBreakUncachedTokens
        postCostUsd             = [math]::Round($post.estimatedUsd, 4)
        postLightTurns          = $post.lightTurns
        postMidTurns            = $post.midTurns
        postHeavyTurns          = $post.heavyTurns
        directSavedTokens       = $convHookTokens
        mcpSavedTokens          = $convMcpSavedTokens
        totalInputTokens        = $m.inputTokens
        totalCacheReadTokens    = $m.cacheReadTokens
        cacheHitPct             = $m.cacheHitPct
        totalOutputTokens       = $m.outputTokens
        totalCostUsd            = $m.estimatedUsd
        projectedNext20TurnsUsd = $m.projectedNext20TurnsUsd
        hooks                   = [ordered]@{
            cliDenials       = $hk.cliDenials
            cliCompressions  = $hk.cliCompressions
            cliLinesSaved    = $hk.cliLinesSaved
            zeroTokWatches   = $convWatchCount
            modelAuditBadges = $hk.modelAuditBadges
            total            = $hookTotalConv
        }
    })
}

# Pure Token Baseline (PRE plugin — depth-matched by session turn index!)
$preTotalIn = $preAll.uncached + $preAll.cached
$preCacheHit = if ($preTotalIn -gt 0) { [math]::Round(($preAll.cached / $preTotalIn) * 100, 1) } else { 0.0 }
$preAvgRaw = if ($preAll.turns -gt 0) { [math]::Round($preAll.raw / $preAll.turns, 1) } else { 0.0 }
$preAvgCtx = if ($preAll.turns -gt 0) { [math]::Round($preTotalIn / $preAll.turns, 1) } else { 0.0 }
$preAvgUnc = if ($preAll.turns -gt 0) { [math]::Round($preAll.uncached / $preAll.turns, 1) } else { 0.0 }
$preAvgOut = if ($preAll.turns -gt 0) { [math]::Round($preAll.out / $preAll.turns, 1) } else { 0.0 }
if ($postAll.turns -gt 0 -and $preAll.turns -ge 20 -and $preDepthAll -and $postDepthAll) {
    $wRaw = 0.0; $wCtx = 0.0; $wUnc = 0.0; $wOut = 0.0; $wCached = 0.0; $wTurns = 0
    foreach ($dk in @("1-15", "16-30", "31-60", "61+")) {
        $pt = $postDepthAll[$dk].turns
        if ($pt -le 0) { continue }
        $pd = $preDepthAll[$dk]
        if ($pd.turns -gt 0) {
            $wRaw += ($pd.raw / $pd.turns) * $pt
            $wCtx += (($pd.uncached + $pd.cached) / $pd.turns) * $pt
            $wUnc += ($pd.uncached / $pd.turns) * $pt
            $wOut += ($pd.out / $pd.turns) * $pt
            $wCached += ($pd.cached / $pd.turns) * $pt
        } else {
            $wRaw += $preAvgRaw * $pt
            $wCtx += $preAvgCtx * $pt
            $wUnc += $preAvgUnc * $pt
            $wOut += $preAvgOut * $pt
            $wCached += ($preAll.cached / $preAll.turns) * $pt
        }
        $wTurns += $pt
    }
    if ($wTurns -gt 0) {
        $preAvgRaw = [math]::Round($wRaw / $wTurns, 1)
        $preAvgCtx = [math]::Round($wCtx / $wTurns, 1)
        $preAvgUnc = [math]::Round($wUnc / $wTurns, 1)
        $preAvgOut = [math]::Round($wOut / $wTurns, 1)
        $preCacheHit = if ($wCtx -gt 0) { [math]::Round(($wCached / $wCtx) * 100, 1) } else { 0.0 }
    }
}
$baselineSource = if ($preAll.turns -ge 20) { "personal" } else { "mechanisms_only" }
$preKnownMixSum = [math]::Max(1, ($preAll.light + $preAll.mid + $preAll.heavy))

# Pure Token Post Summary
$postTotalIn = $postAll.uncached + $postAll.cached
$postCacheHit = if ($postTotalIn -gt 0) { [math]::Round(($postAll.cached / $postTotalIn) * 100, 1) } else { 0.0 }
$postAvgRaw = if ($postAll.turns -gt 0) { [math]::Round($postAll.raw / $postAll.turns, 1) } else { 0.0 }
$postAvgCtx = if ($postAll.turns -gt 0) { [math]::Round($postTotalIn / $postAll.turns, 1) } else { 0.0 }
$postAvgUnc = if ($postAll.turns -gt 0) { [math]::Round($postAll.uncached / $postAll.turns, 1) } else { 0.0 }
$postAvgOut = if ($postAll.turns -gt 0) { [math]::Round($postAll.out / $postAll.turns, 1) } else { 0.0 }
$postKnownMixSum = [math]::Max(1, ($postAll.light + $postAll.mid + $postAll.heavy))

$globalIn = $preTotalIn + $postTotalIn
$globalCached = $preAll.cached + $postAll.cached
$globalHit = if ($globalIn -gt 0) { [math]::Round(($globalCached / $globalIn) * 100, 1) } else { 0.0 }

$modelSummary = [ordered]@{}
foreach ($k in ($byModel.Keys | Sort-Object { $byModel[$_].estimatedUsd } -Descending)) {
    $item = $byModel[$k]
    $mHit = if ($item.inputTokens -gt 0) { [math]::Round(($item.cacheReadTokens / $item.inputTokens) * 100, 1) } else { 0.0 }
    $modelSummary[$k] = [ordered]@{
        turns           = $item.turns
        tier            = $item.tier
        weight          = $item.weight
        inputTokens     = $item.inputTokens
        cacheReadTokens = $item.cacheReadTokens
        cacheHitPct     = $mHit
        outputTokens    = $item.outputTokens
        estimatedUsd    = [math]::Round($item.estimatedUsd, 4)
        costEur         = [math]::Round($item.estimatedUsd * $USD_TO_EUR, 4)
    }
}

$projectList = [System.Collections.Generic.List[object]]::new()
foreach ($pk in $byProject.Keys) {
    $p = $byProject[$pk]
    $projectList.Add([ordered]@{
        project      = $p.project
        sessions     = $p.sessions
        postSessions = $p.postSessions
        totalTurns   = $p.totalTurns
        postTurns    = $p.postTurns
        postRaw      = $p.postRaw
        postUncached = $p.postUncached
        postCached   = $p.postCached
        postOutput   = $p.postOutput
        postCostUsd  = [math]::Round($p.postCostUsd, 4)
        directSaved  = $p.directSaved
        mcpSaved     = $p.mcpSaved
        hookHits     = $p.hookHits
    })
}

# Reconcile cumulative telemetry from both transcripts, watch-state, sandbox logs & ledger
$totalCliDenials = [math]::Max($hooksAll.cliDenials, $ledger.cliDenials)
$totalCliComp = [math]::Max($hooksAll.cliCompressions, [math]::Max($ledger.cliCompressions, $mechState.sandboxFiles))
$totalWatchEvents = [math]::Max(($hooksAll.sessionAudits + $hooksAll.costWatchAlerts), ($mechState.histLoops + $mechState.histMilestones + $ledger.sessionAudits + $ledger.loopGuards + $ledger.costWatches))

$liveConv = if ($byConversation.Count -gt 0) { $byConversation[0] } else { $null }

[ordered]@{
    sessionsAnalyzed   = $byConversation.Count
    timezone           = $timezoneLabel
    usdToEur           = $USD_TO_EUR
    pluginInstalledAt  = $pluginInstalledUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm")
    pluginInstalledUtc = $pluginInstalledUtc.ToString("o")

    liveSession        = if ($liveConv) {
        [ordered]@{
            conversationId    = $liveConv.conversationId
            project           = $liveConv.project
            lastModel         = $liveConv.lastModel
            lastContextTokens = $liveConv.lastContextTokens
            lastEventUtc      = $liveConv.lastUpdatedIso
            turns             = $liveConv.totalTurns
            ageDays           = [math]::Round(([datetime]::UtcNow - (ConvertTo-UtcDateTime -Value $liveConv.lastUpdatedIso)).TotalDays, 1)
        }
    } else { $null }

    antigravityLive    = $liveQuota

    mechanisms = [ordered]@{
        mcpCatalogCount   = $mechState.mcpCatalogCount
        mcpActiveCount    = $mechState.mcpActiveCount
        mcpActive         = @($mechState.mcpActive)
        mcpDisabled       = @($mechState.mcpDisabled)
        mcpDisabledCount  = $mechState.mcpDisabledCount
        cliDenials        = $totalCliDenials
        cliCompressions   = $totalCliComp
        cliLinesSaved     = $hooksAll.cliLinesSaved
        sandboxFiles      = $mechState.sandboxFiles
        sandboxBytes      = $mechState.sandboxBytes
        outlinesCount     = $ledger.outlines
        outlineTokens     = $ledger.outlineTokens
        cliLedgerTokens   = ($ledger.cliDenyTokens + $ledger.cliCompressTokens)
        zeroTokLoops      = [math]::Max($mechState.histLoops, $ledger.loopGuards)
        zeroTokMilestones = [math]::Max($mechState.histMilestones, $ledger.costWatches)
        zeroTokAudits     = [math]::Max($hooksAll.sessionAudits, $ledger.sessionAudits)
        zeroTokTotal      = $totalWatchEvents
        modelAuditBadges  = $hooksAll.modelAuditBadges
    }

    baseline = [ordered]@{
        source            = $baselineSource
        preTurns          = $preAll.turns
        avgRawPerTurn     = $preAvgRaw
        avgContextPerTurn = $preAvgCtx
        avgUncachedPerTurn = $preAvgUnc
        avgOutputPerTurn  = $preAvgOut
        avgCacheHitPct    = $preCacheHit
        # Advisor visibility only — never used as fake token savings!
        modelMixPct       = [ordered]@{
            light = [math]::Round(($preAll.light / $preKnownMixSum) * 100, 1)
            mid   = [math]::Round(($preAll.mid / $preKnownMixSum) * 100, 1)
            heavy = [math]::Round(($preAll.heavy / $preKnownMixSum) * 100, 1)
        }
    }

    postSummary = [ordered]@{
        postSessions       = $postAll.sessions
        postTurns          = $postAll.turns
        uncachedTokens     = $postAll.uncached
        cacheReadTokens    = $postAll.cached
        outputTokens       = $postAll.out
        rawTokens          = $postAll.raw
        estimatedUsd       = [math]::Round($postAll.usd, 4)
        avgRawPerTurn      = $postAvgRaw
        avgContextPerTurn  = $postAvgCtx
        avgUncachedPerTurn = $postAvgUnc
        avgOutputPerTurn   = $postAvgOut
        avgCacheHitPct     = $postCacheHit
        # Advisor visibility only — never used as fake token savings!
        modelMixPct        = [ordered]@{
            light = [math]::Round(($postAll.light / $postKnownMixSum) * 100, 1)
            mid   = [math]::Round(($postAll.mid / $postKnownMixSum) * 100, 1)
            heavy = [math]::Round(($postAll.heavy / $postKnownMixSum) * 100, 1)
        }
    }

    googleNativeCache = [ordered]@{
        cachedTokens           = $globalCached
        totalInputTokens       = $globalIn
        globalCacheHitPct      = $globalHit
        preCacheHitPct         = $preCacheHit
        postCacheHitPct        = $postCacheHit
        cacheDeltaPts          = [math]::Round($postCacheHit - $preCacheHit, 1)
        preSteadyCacheHitPct   = if ($preTotalIn -gt 0) { [math]::Round(($preAll.cached / [math]::Max(1L, ($preAll.uncached - $preAll.switchUnc - $preAll.idleUnc) + $preAll.cached)) * 100, 1) } else { 0.0 }
        postSteadyCacheHitPct  = if ($postTotalIn -gt 0) { [math]::Round(($postAll.cached / [math]::Max(1L, ($postAll.uncached - $postAll.switchUnc - $postAll.idleUnc) + $postAll.cached)) * 100, 1) } else { 0.0 }
        postModelSwitches      = $postAll.switches
        postSwitchUncached     = $postAll.switchUnc
        postIdleMisses         = $postAll.idles
        postIdleUncached       = $postAll.idleUnc
        postPrefixBreaks       = $postAll.breaks
        postBreakUncached      = $postAll.breakUnc
    }

    byProject             = @($projectList | Sort-Object @{ Expression = "postTurns"; Descending = $true }, @{ Expression = "totalTurns"; Descending = $true })
    byModel               = $modelSummary
    conversations         = @($byConversation)
    topVerboseToolOutputs = @($verboseOutputs | Sort-Object chars -Descending | Select-Object -First 8)
} | ConvertTo-Json -Depth 6
