# Shared core library for Token Optimizer plugin (zero external dependencies)

function Get-WorkspaceStackInfo {
    param([string]$WorkspacePath = ".")

    $root = if (Test-Path $WorkspacePath) { (Resolve-Path $WorkspacePath).Path } else { $WorkspacePath }

    function Test-StackFiles {
        param([string[]]$Patterns)
        foreach ($p in $Patterns) {
            if (Get-ChildItem -Path $root -Filter $p -File -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1) {
                return $true
            }
        }
        return $false
    }

    $stacks = [System.Collections.Generic.List[string]]::new()
    $ignores = [System.Collections.Generic.List[string]]::new()
    $tests = [System.Collections.Generic.List[string]]::new()
    $lints = [System.Collections.Generic.List[string]]::new()

    $ignores.AddRange([string[]]@(
        ".git/", "logs/", "*.log", "*.map", "*.min.js", "*.min.css",
        "*.png", "*.jpg", "*.jpeg", "*.webp", "*.mp4", "*.zip", "*.pdf"
    ))

    if (Test-StackFiles @("package.json", "tsconfig.json", "next.config.*", "vite.config.*")) {
        $stacks.Add("web-js-ts")
        $ignores.AddRange([string[]]@(
            "node_modules/", "dist/", "build/", ".next/", ".nuxt/", ".vite/", ".turbo/",
            "coverage/", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb"
        ))
        if (Test-Path (Join-Path $root "pnpm-lock.yaml")) { $tests.Add("pnpm test -- --silent"); $lints.Add("pnpm lint") }
        elseif (Test-Path (Join-Path $root "yarn.lock")) { $tests.Add("yarn test --silent"); $lints.Add("yarn lint") }
        else { $tests.Add("npm test -- --silent"); $lints.Add("npm run lint") }
    }

    if (Test-StackFiles @("pyproject.toml", "requirements.txt", "uv.lock", "poetry.lock")) {
        $stacks.Add("python")
        $ignores.AddRange([string[]]@(
            ".venv/", "venv/", "__pycache__/", "*.pyc", ".pytest_cache/",
            ".mypy_cache/", ".ruff_cache/", "htmlcov/", "uv.lock", "poetry.lock"
        ))
        $tests.Add("pytest -q")
        $lints.Add("ruff check .")
    }

    if (Test-StackFiles @("*.sln", "*.csproj")) {
        $stacks.Add("dotnet-csharp")
        $ignores.AddRange([string[]]@(
            "bin/", "obj/", ".vs/", "packages/", "TestResults/",
            "*.nupkg", "*.exe", "*.dll", "*.pdb", "*.gz"
        ))
        $tests.Add("dotnet test --verbosity quiet")
        $lints.Add("dotnet build --verbosity quiet")
    }

    if ((Test-Path (Join-Path $root "ProjectSettings\ProjectVersion.txt")) -or ((Test-Path (Join-Path $root "Assets")) -and (Test-Path (Join-Path $root "Packages\manifest.json")))) {
        $stacks.Add("unity")
        $ignores.AddRange([string[]]@("Library/", "Temp/", "Logs/", "UserSettings/", "Builds/", "*.meta"))
    }

    if (Test-StackFiles @("*.blend")) {
        $stacks.Add("3d-blender")
        $ignores.AddRange([string[]]@("*.blend1", "*.blend2", "renders/", "cache/", "*.exr", "*.hdr"))
    }

    if (Test-StackFiles @("Cargo.toml")) {
        $stacks.Add("rust")
        $ignores.AddRange([string[]]@("target/", "Cargo.lock"))
        $tests.Add("cargo test -q")
        $lints.Add("cargo clippy -q")
    }

    if (Test-StackFiles @("go.mod")) {
        $stacks.Add("go")
        $ignores.AddRange([string[]]@("vendor/", "go.sum"))
        $tests.Add("go test ./...")
        $lints.Add("go vet ./...")
    }

    if (Test-StackFiles @("pom.xml", "build.gradle", "build.gradle.kts")) {
        $stacks.Add("java")
        $ignores.AddRange([string[]]@("target/", "build/", ".gradle/", "*.class", "*.jar"))
        if (Test-Path (Join-Path $root "pom.xml")) { $tests.Add("mvn test -q") } else { $tests.Add("./gradlew test --quiet") }
    }

    if (Test-StackFiles @("CMakeLists.txt", "Makefile")) {
        $stacks.Add("c-cpp")
        $ignores.AddRange([string[]]@("build/", "out/", "cmake-build-*/", "*.o", "*.so", "*.dll", "*.exe"))
        $tests.Add("ctest --output-on-failure")
    }

    return [ordered]@{
        workspace         = $root
        detectedStacks    = @($stacks)
        suggestedTests    = @($tests | Select-Object -Unique)
        suggestedLints    = @($lints | Select-Object -Unique)
        recommendedIgnore = @($ignores | Select-Object -Unique)
    }
}

function Write-TokenOptimizerEvent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EventType,
        [long]$SavedTokens = 0L,
        [string]$ConversationId = "",
        [hashtable]$Details = $null
    )
    try {
        $cfgDir = Join-Path $env:USERPROFILE ".gemini\config"
        if (-not (Test-Path $cfgDir)) {
            New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
        }
        $ledgerPath = Join-Path $cfgDir "token-optimizer-events.jsonl"
        $rec = [ordered]@{
            ts          = (Get-Date).ToUniversalTime().ToString("o")
            event       = $EventType
            convId      = $ConversationId
            savedTokens = $SavedTokens
        }
        if ($Details) { $rec["details"] = $Details }
        $line = ($rec | ConvertTo-Json -Compress -Depth 4) + "`n"
        [System.IO.File]::AppendAllText($ledgerPath, $line, [System.Text.UTF8Encoding]::new($false))
    }
    catch {
        # Never fail a hook or skill because of telemetry logging
    }
}

function ConvertTo-UtcDateTime {
    param($Value, [datetime]$FallbackUtc = ([datetime]::UtcNow))
    if ($null -eq $Value) { return $FallbackUtc }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) {
            return [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
        }
        return $Value.ToUniversalTime()
    }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $FallbackUtc }
    try {
        return [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    }
    catch {
        return $FallbackUtc
    }
}

function Get-ModelQuotaProfile {
    <#
    .SYNOPSIS
    Returns quota weight tier and nominal API pricing rates for a model name.
    #>
    param([string]$Model)
    $m = if ($Model) { $Model.ToLowerInvariant() } else { "" }
    if (($m -match 'hydrogen' -and $m -match 'low') -or ($m -match 'flash|lite|worker')) {
        return [ordered]@{ tier = "light"; weight = 1.0; uncachedUsdPerM = 0.30; cachedUsdPerM = 0.03; outUsdPerM = 2.50 }
    }
    elseif ($m -match 'hydrogen') {
        return [ordered]@{ tier = "mid"; weight = 5.0; uncachedUsdPerM = 1.50; cachedUsdPerM = 0.15; outUsdPerM = 7.50 }
    }
    elseif ($m -match 'neon|claude|orchestrator|opus|sonnet|gemini-.*pro') {
        return [ordered]@{ tier = "heavy"; weight = 10.0; uncachedUsdPerM = 3.00; cachedUsdPerM = 0.15; outUsdPerM = 15.00 }
    }
    return [ordered]@{ tier = "unknown"; weight = $null; uncachedUsdPerM = $null; cachedUsdPerM = $null; outUsdPerM = $null }
}

function Get-ModelEstimatedUsd {
    param([string]$Model, [long]$UncachedIn, [long]$CachedIn, [long]$OutTokens)
    $prof = Get-ModelQuotaProfile -Model $Model
    if ($null -eq $prof.weight) { return $null }
    return ($UncachedIn * $prof.uncachedUsdPerM / 1e6) + ($CachedIn * $prof.cachedUsdPerM / 1e6) + ($OutTokens * $prof.outUsdPerM / 1e6)
}

function Get-TranscriptMetrics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TranscriptPath,
        [switch]$TailOnlyForLoops,
        [nullable[datetime]]$PluginInstalledUtc = $null
    )

    function New-TurnBucket {
        return @{
            turns                     = 0
            knownTurns                = 0
            uncachedTokens            = 0L
            cacheReadTokens           = 0L
            outputTokens              = 0L
            rawTokens                 = 0L
            effBaseTokens             = 0.0
            knownEffBaseTokens        = 0.0
            quotaTokens               = 0.0
            estimatedUsd              = 0.0
            lightTurns                = 0
            midTurns                  = 0
            heavyTurns                = 0
            unknownTurns              = 0
            modelSwitches             = 0
            switchUncachedTokens      = 0L
            idleMisses                = 0
            idleUncachedTokens        = 0L
            prefixBreaks              = 0
            prefixBreakUncachedTokens = 0L
            byDepth                   = @{
                "1-15"  = @{ turns = 0; uncached = 0L; cached = 0L; out = 0L; raw = 0L }
                "16-30" = @{ turns = 0; uncached = 0L; cached = 0L; out = 0L; raw = 0L }
                "31-60" = @{ turns = 0; uncached = 0L; cached = 0L; out = 0L; raw = 0L }
                "61+"   = @{ turns = 0; uncached = 0L; cached = 0L; out = 0L; raw = 0L }
            }
        }
    }

    $turns = 0
    $totalIn = 0L
    $totalCache = 0L
    $totalOut = 0L
    $totalCost = 0.0
    $lastContext = 0L
    $lastModel = "hydrogen"
    $prevPlannerModel = ""
    $prevPlannerUtc = $null
    $sessSwitches = 0; $sessSwitchUnc = 0L
    $sessIdles = 0; $sessIdleUnc = 0L
    $sessBreaks = 0; $sessBreakUnc = 0L
    $byModel = @{}
    $verboseOutputs = [System.Collections.Generic.List[object]]::new()
    $recentGenerics = [System.Collections.Generic.Queue[object]]::new()

    $preBucket = New-TurnBucket
    $postBucket = New-TurnBucket
    $hooks = [ordered]@{
        cliDenials         = 0
        cliCompressions    = 0
        cliLinesSaved      = 0
        sessionAudits      = 0
        costWatchAlerts    = 0
        modelAuditBadges   = 0
    }
    $firstEventUtc = $null
    $lastEventUtc = $null
    $earliestPluginMarkerUtc = $null

    $fileItem = Get-Item -Path $TranscriptPath -ErrorAction SilentlyContinue
    $fileUtc = if ($fileItem) { $fileItem.LastWriteTimeUtc } else { [datetime]::UtcNow }
    $installCutUtc = if ($null -ne $PluginInstalledUtc) { ([datetime]$PluginInstalledUtc).ToUniversalTime() } else { $null }

    $linesToScan = if ($TailOnlyForLoops) {
        @(Get-Content -Path $TranscriptPath -Tail 24 -ErrorAction SilentlyContinue)
    }
    else {
        [System.IO.File]::ReadLines($TranscriptPath)
    }

    $failRegex = '(?i)(Command exited with code [1-9]|exit status [1-9]|\berror CS\d+|\berror TS\d+|Traceback \(most recent|\bFAIL\b|\bException:)'

    foreach ($line in $linesToScan) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $ev = $line | ConvertFrom-Json } catch { continue }

        $evUtc = ConvertTo-UtcDateTime -Value $ev.created_at -FallbackUtc $fileUtc
        if (-not $TailOnlyForLoops) {
            if ($null -eq $firstEventUtc -or $evUtc -lt $firstEventUtc) { $firstEventUtc = $evUtc }
            if ($null -eq $lastEventUtc -or $evUtc -gt $lastEventUtc) { $lastEventUtc = $evUtc }
        }
        $isPost = ($null -ne $installCutUtc) -and ($evUtc -ge $installCutUtc)

        if (-not $TailOnlyForLoops -and $ev.type -eq "PLANNER_RESPONSE") {
            $turns++
            $mName = if ($ev.model) { [string]$ev.model } else { "unknown" }
            $lastModel = $mName.ToLowerInvariant()
            # In Antigravity transcripts: input_tokens = uncached input, cache_read_tokens = cached input
            $uncached = [long]($ev.input_tokens)
            $cached = [long]($ev.cache_read_tokens)
            $inTok = $uncached + $cached
            $outTok = [long]($ev.output_tokens)
            $rawTok = $inTok + $outTok
            # Google native cache discount (5% weight) applied symmetrically before and after plugin
            $effBaseTok = [double]$uncached + ([double]$cached * 0.05) + ([double]$outTok * 5.0)
            $lastContext = $inTok

            $totalIn += $inTok
            $totalCache += $cached
            $totalOut += $outTok

            $prof = Get-ModelQuotaProfile -Model $mName
            $est = Get-ModelEstimatedUsd -Model $mName -UncachedIn $uncached -CachedIn $cached -OutTokens $outTok

            if (-not $byModel.ContainsKey($mName)) {
                $byModel[$mName] = @{
                    turns           = 0
                    tier            = $prof.tier
                    weight          = $prof.weight
                    inputTokens     = 0L
                    cacheReadTokens = 0L
                    outputTokens    = 0L
                    estimatedUsd    = 0.0
                }
            }
            $byModel[$mName].turns++
            $byModel[$mName].inputTokens += $inTok
            $byModel[$mName].cacheReadTokens += $cached
            $byModel[$mName].outputTokens += $outTok

            if ($null -ne $est) {
                $byModel[$mName].estimatedUsd += $est
                $totalCost += $est
            }

            $bkt = if ($isPost) { $postBucket } else { $preBucket }
            $bkt.turns++
            $bkt.uncachedTokens += $uncached
            $bkt.cacheReadTokens += $cached
            $bkt.outputTokens += $outTok
            $bkt.rawTokens += $rawTok
            $bkt.effBaseTokens += $effBaseTok
            $dKey = if ($turns -le 15) { "1-15" } elseif ($turns -le 30) { "16-30" } elseif ($turns -le 60) { "31-60" } else { "61+" }
            $db = $bkt.byDepth[$dKey]
            $db.turns++
            $db.uncached += $uncached
            $db.cached += $cached
            $db.out += $outTok
            $db.raw += $rawTok

            # Classify major cache misses (warm model switch <300s vs >5m TTL pause vs prefix break)
            $gapMin = if ($null -ne $prevPlannerUtc) { ($evUtc - $prevPlannerUtc).TotalMinutes } else { 0.0 }
            if ($turns -gt 1) {
                if ($prevPlannerModel -ne "" -and $mName -ne $prevPlannerModel -and $gapMin -lt 5.0 -and $uncached -gt 15000) {
                    $bkt.modelSwitches++; $bkt.switchUncachedTokens += $uncached
                    $sessSwitches++; $sessSwitchUnc += $uncached
                }
                elseif ($gapMin -ge 5.0 -and $uncached -gt 15000) {
                    $bkt.idleMisses++; $bkt.idleUncachedTokens += $uncached
                    $sessIdles++; $sessIdleUnc += $uncached
                }
                elseif ($uncached -gt 20000) {
                    $bkt.prefixBreaks++; $bkt.prefixBreakUncachedTokens += $uncached
                    $sessBreaks++; $sessBreakUnc += $uncached
                }
            }
            $prevPlannerModel = $mName
            $prevPlannerUtc = $evUtc

            if ($null -ne $prof.weight) {
                $bkt.knownTurns++
                $bkt.knownEffBaseTokens += $effBaseTok
                $bkt.quotaTokens += ($effBaseTok * [double]$prof.weight)
                if ($null -ne $est) { $bkt.estimatedUsd += $est }
                if ($prof.tier -eq "light") { $bkt.lightTurns++ }
                elseif ($prof.tier -eq "mid") { $bkt.midTurns++ }
                elseif ($prof.tier -eq "heavy") { $bkt.heavyTurns++ }
            }
            else {
                $bkt.unknownTurns++
            }

            if ($isPost -and $ev.content -and ([string]$ev.content -match '\[Audit Mod[èe]le\s*:')) {
                $hooks.modelAuditBadges++
            }
        }
        elseif (($ev.type -eq "GENERIC" -or $ev.type -eq "SYSTEM_MESSAGE") -and $ev.content) {
            $txt = [string]$ev.content
            if ($ev.type -eq "GENERIC") {
                $recentGenerics.Enqueue([ordered]@{
                    stepIndex = $ev.step_index
                    isFailure = ($txt -match $failRegex)
                })
                while ($recentGenerics.Count -gt 8) { [void]$recentGenerics.Dequeue() }

                if (-not $TailOnlyForLoops -and $txt.Length -ge 4000) {
                    $preview = $txt.Substring(0, [math]::Min(90, $txt.Length)) -replace '[\r\n]+', ' '
                    $verboseOutputs.Add([ordered]@{
                        stepIndex = $ev.step_index
                        chars     = $txt.Length
                        estTokens = [math]::Ceiling($txt.Length / 4)
                        preview   = $preview
                    })
                }
            }

            if (-not $TailOnlyForLoops) {
                # Ignore code dumps from read_file when counting live plugin hook interventions
                $isCodeRead = ($txt -match 'Showing lines \d+-\d+ of \d+') -or ($txt -match '\$resp\s*=')
                if (-not $isCodeRead) {
                    if ($txt -match 'Token Optimizer — Audit automatique|Token Optimizer — Prévision|Boucle d''échec détectée|lecture brute non bornée détectée|\[Token Optimizer:\s*\d+\s*->\s*\d+\s*lignes') {
                        if ($null -eq $earliestPluginMarkerUtc -or $evUtc -lt $earliestPluginMarkerUtc) {
                            $earliestPluginMarkerUtc = $evUtc
                        }
                    }
                    if ($isPost) {
                        if ($txt -match 'lecture brute non born') { $hooks.cliDenials++ }
                        foreach ($cm in [regex]::Matches($txt, '\[Token Optimizer:\s*(\d+)\s*->\s*(\d+)\s*lignes')) {
                            $hooks.cliCompressions++
                            $hooks.cliLinesSaved += [math]::Max(0, ([int]$cm.Groups[1].Value - [int]$cm.Groups[2].Value))
                        }
                        if ($txt -match 'Audit automatique \(0 token') { $hooks.sessionAudits++ }
                        if ($txt -match 'Prévision session|Boucle d''échec détectée') { $hooks.costWatchAlerts++ }
                    }
                }
            }
        }
    }

    $recentArr = @($recentGenerics.ToArray())
    $recentFailures = @($recentArr | Where-Object { $_.isFailure })
    $latestStepIdx = if ($recentArr.Count -gt 0) { [int]$recentArr[-1].stepIndex } else { 0 }

    $hitPct = if ($totalIn -gt 0) { [math]::Round(($totalCache / $totalIn) * 100, 1) } else { 0.0 }
    $steadyDenom = [math]::Max(1L, (($totalIn - $totalCache) - $sessSwitchUnc - $sessIdleUnc) + $totalCache)
    $steadyHitPct = if ($totalIn -gt 0) { [math]::Round(([math]::Min($totalCache, $steadyDenom) / $steadyDenom) * 100, 1) } else { 0.0 }
    $avgCtx = if ($turns -gt 0) { [long][math]::Round($totalIn / $turns) } else { 0L }
    $avgOut = if ($turns -gt 0) { [double]$totalOut / $turns } else { 0.0 }
    $lastProf = Get-ModelQuotaProfile -Model $lastModel
    $outRate = if ($null -ne $lastProf.outUsdPerM) { [double]$lastProf.outUsdPerM } else { 7.50 }
    $cacheRate = if ($null -ne $lastProf.cachedUsdPerM) { [double]$lastProf.cachedUsdPerM } else { 0.15 }
    $proj20 = if ($turns -gt 0) { [math]::Round(20 * (($lastContext * $cacheRate / 1e6) + ($avgOut * $outRate / 1e6)), 4) } else { 0.0 }

    return [ordered]@{
        turns                   = $turns
        inputTokens             = $totalIn
        cacheReadTokens         = $totalCache
        cacheHitPct             = $hitPct
        outputTokens            = $totalOut
        avgContextTokens        = $avgCtx
        lastContextTokens       = $lastContext
        lastModel               = $lastModel
        estimatedUsd            = [math]::Round($totalCost, 4)
        projectedNext20TurnsUsd = $proj20
        byModel                 = $byModel
        verboseOutputs          = @($verboseOutputs)
        recentFailureCount      = $recentFailures.Count
        loopDetected            = ($recentFailures.Count -ge 3)
        latestGenericStep       = $latestStepIdx
        cacheDiagnostics        = [ordered]@{
            steadyCacheHitPct         = $steadyHitPct
            modelSwitches             = $sessSwitches
            switchUncachedTokens      = $sessSwitchUnc
            idleMisses                = $sessIdles
            idleUncachedTokens        = $sessIdleUnc
            prefixBreaks              = $sessBreaks
            prefixBreakUncachedTokens = $sessBreakUnc
        }
        pre                     = $preBucket
        post                    = $postBucket
        hooks                   = $hooks
        firstEventUtc           = $firstEventUtc
        lastEventUtc            = $lastEventUtc
        earliestPluginMarkerUtc = $earliestPluginMarkerUtc
    }
}
