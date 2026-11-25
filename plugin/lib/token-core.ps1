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

function Get-ModelEstimatedUsd {
    param([string]$Model, [long]$UncachedIn, [long]$CachedIn, [long]$OutTokens)
    $m = if ($Model) { $Model.ToLowerInvariant() } else { "" }
    if ($m -match 'neon') {
        return ($UncachedIn * 3.00 / 1e6) + ($CachedIn * 0.15 / 1e6) + ($OutTokens * 15.00 / 1e6)
    }
    elseif ($m -match 'hydrogen') {
        return ($UncachedIn * 1.50 / 1e6) + ($CachedIn * 0.15 / 1e6) + ($OutTokens * 7.50 / 1e6)
    }
    return $null
}

function Get-TranscriptMetrics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TranscriptPath,
        [switch]$TailOnlyForLoops
    )

    $turns = 0
    $totalIn = 0L
    $totalCache = 0L
    $totalOut = 0L
    $totalCost = 0.0
    $lastContext = 0L
    $lastModel = "neon"
    $byModel = @{}
    $verboseOutputs = [System.Collections.Generic.List[object]]::new()
    $recentGenerics = [System.Collections.Generic.Queue[object]]::new()

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

        if (-not $TailOnlyForLoops -and $ev.type -eq "PLANNER_RESPONSE") {
            $turns++
            $mName = if ($ev.model) { [string]$ev.model } else { "unknown" }
            $lastModel = $mName.ToLowerInvariant()
            # In Antigravity transcripts: input_tokens = uncached input, cache_read_tokens = cached input
            $uncached = [long]($ev.input_tokens)
            $cached = [long]($ev.cache_read_tokens)
            $inTok = $uncached + $cached
            $outTok = [long]($ev.output_tokens)
            $lastContext = $inTok

            $totalIn += $inTok
            $totalCache += $cached
            $totalOut += $outTok

            if (-not $byModel.ContainsKey($mName)) {
                $byModel[$mName] = @{ turns = 0; inputTokens = 0L; cacheReadTokens = 0L; outputTokens = 0L; estimatedUsd = 0.0 }
            }
            $byModel[$mName].turns++
            $byModel[$mName].inputTokens += $inTok
            $byModel[$mName].cacheReadTokens += $cached
            $byModel[$mName].outputTokens += $outTok

            $est = Get-ModelEstimatedUsd -Model $mName -UncachedIn $uncached -CachedIn $cached -OutTokens $outTok
            if ($null -ne $est) {
                $byModel[$mName].estimatedUsd += $est
                $totalCost += $est
            }
        }
        elseif ($ev.type -eq "GENERIC" -and $ev.content) {
            $txt = [string]$ev.content
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
    }

    $recentArr = @($recentGenerics.ToArray())
    $recentFailures = @($recentArr | Where-Object { $_.isFailure })
    $latestStepIdx = if ($recentArr.Count -gt 0) { [int]$recentArr[-1].stepIndex } else { 0 }

    $hitPct = if ($totalIn -gt 0) { [math]::Round(($totalCache / $totalIn) * 100, 1) } else { 0.0 }
    $avgCtx = if ($turns -gt 0) { [long][math]::Round($totalIn / $turns) } else { 0L }
    $avgOut = if ($turns -gt 0) { [double]$totalOut / $turns } else { 0.0 }
    $outRate = if ($lastModel -match 'hydrogen') { 7.50 } else { 15.00 }
    $proj20 = if ($turns -gt 0) { [math]::Round(20 * (($lastContext * 0.15 / 1e6) + ($avgOut * $outRate / 1e6)), 4) } else { 0.0 }

    return [ordered]@{
        turns                   = $turns
        inputTokens             = $totalIn
        cacheReadTokens         = $totalCache
        cacheHitPct             = $hitPct
        outputTokens            = $totalOut
        avgContextTokens        = $avgCtx
        lastContextTokens       = $lastContext
        estimatedUsd            = [math]::Round($totalCost, 4)
        projectedNext20TurnsUsd = $proj20
        byModel                 = $byModel
        verboseOutputs          = @($verboseOutputs)
        recentFailureCount      = $recentFailures.Count
        loopDetected            = ($recentFailures.Count -ge 3)
        latestGenericStep       = $latestStepIdx
    }
}
