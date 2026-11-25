$ErrorActionPreference = "SilentlyContinue"
try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Write-Output '{}'; exit 0 }
    $payload = $raw | ConvertFrom-Json

    $wsRaw = if ($payload.workspacePaths -and $payload.workspacePaths.Count -gt 0) { [string]$payload.workspacePaths[0] }
             elseif ($payload.cwd) { [string]$payload.cwd }
             else { $null }
    if ([string]::IsNullOrWhiteSpace($wsRaw)) { Write-Output '{}'; exit 0 }
    if ($wsRaw -match '^file:///') { $wsRaw = ([Uri]$wsRaw).LocalPath }
    if (-not (Test-Path $wsRaw)) { Write-Output '{}'; exit 0 }

    . (Join-Path $PSScriptRoot "..\lib\token-core.ps1")
    $stackInfo = Get-WorkspaceStackInfo -WorkspacePath $wsRaw
    $ws = $stackInfo.workspace
    $stacks = @($stackInfo.detectedStacks)
    $alerts = [System.Collections.Generic.List[string]]::new()

    # 1. Check .antigravityignore & stack drift
    $ignorePath = Join-Path $ws ".antigravityignore"
    if (-not (Test-Path $ignorePath)) {
        $stackTxt = if ($stacks.Count -gt 0) { $stacks -join ", " } else { "générique" }
        $alerts.Add(('`.antigravityignore` manquant (stacks : {0}) — lancez **token-setup** (`-Mode sync -Apply`).' -f $stackTxt))
    }
    else {
        $ignoreLines = @(Get-Content $ignorePath | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") })
        $keyByStack = @{
            "web-js-ts" = @("node_modules/", "dist/"); "python" = @(".venv/", "__pycache__/")
            "dotnet-csharp" = @("bin/", "obj/"); "unity" = @("Library/", "Temp/")
            "3d-blender" = @("*.blend1"); "rust" = @("target/"); "go" = @("vendor/")
            "java" = @(".gradle/", "build/"); "c-cpp" = @("build/")
        }
        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($st in $stacks) {
            if ($keyByStack.ContainsKey($st)) {
                foreach ($m in $keyByStack[$st]) { if ($ignoreLines -notcontains $m) { $missing.Add($m) } }
            }
        }
        if ($missing.Count -gt 0) {
            $alerts.Add(('Exclusions recommandées absentes de `.antigravityignore` (`{0}`) — lancez **token-setup**.' -f ($missing -join ', ')))
        }
    }

    # 2. Check GEMINI.md / AGENTS.md size
    foreach ($rf in @("GEMINI.md", "AGENTS.md")) {
        $p = Join-Path $ws $rf
        if (Test-Path $p) {
            $len = (Get-Item $p).Length
            if ($len -gt 24000) { $alerts.Add(('`{0}` dépasse 24 KB ({1} o) et sera tronqué par Antigravity.' -f $rf, $len)) }
            elseif ($len -gt 4096) { $alerts.Add(('`{0}` fait {1} o (> 4 KB recommandés) ; déplacez les procédures longues dans `.agents/skills/`.' -f $rf, $len)) }
        }
    }

    # 3. Check unused heavy 3D/Unity MCP servers
    $mcpPath = Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json"
    if (Test-Path $mcpPath) {
        $mcp = Get-Content -Raw $mcpPath | ConvertFrom-Json
        if ($mcp.mcpServers) {
            $activeMcp = @($mcp.mcpServers.PSObject.Properties.Name)
            $isGameOr3d = ($stacks -contains "unity") -or ($stacks -contains "3d-blender")
            if (-not $isGameOr3d) {
                $unusedHeavy = @($activeMcp | Where-Object { $_ -in @("unity", "blender", "game-assets") })
                if ($unusedHeavy.Count -gt 0) {
                    $alerts.Add(('MCP 3D/Unity actifs inutilement (`{0}`) — profil `minimal` recommandé via **token-mcp**.' -f ($unusedHeavy -join ', ')))
                }
            }
        }
    }

    if ($alerts.Count -eq 0) { Write-Output '{}'; exit 0 }

    $md = "**Token Optimizer — Audit automatique (0 token modèle)**`n- " + ($alerts -join "`n- ")
    @{
        injectSteps = @(@{ systemMessage = @{ systemMessage = ""; metadata = @{ user_markdown = $md } } })
    } | ConvertTo-Json -Depth 6 -Compress | Write-Output
    exit 0
}
catch {
    Write-Output '{}'
    exit 0
}
