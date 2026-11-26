$ErrorActionPreference = "SilentlyContinue"
try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-Output '{"decision":"allow"}'
        exit 0
    }
    $payload = $raw | ConvertFrom-Json
    $cmd = [string]$payload.toolCall.args.CommandLine
    if ([string]::IsNullOrWhiteSpace($cmd)) {
        Write-Output '{"decision":"allow"}'
        exit 0
    }

    # 1. RTK-style transparent proxy compression (no blocking deny — avoids wasted retry turns!)
    $hasMetaSyntax = ($cmd -match '[|><;\r\n]') -or ($cmd -match '&&') -or ($cmd -match 'compress-cli\.ps1')
    $alreadyQuiet = $cmd -match '(?i)(--quiet|\s-q\b|--silent|--verbosity\s+(q|quiet|m|minimal)|--stat|--name-only|--oneline|\s-n\s+\d+|--max-count)'

    $isRawDump = $cmd -match '(?i)^\s*(cat|type|Get-Content|gc)\s+'
    $hasLimiter = $cmd -match '(?i)(Select-Object|TotalCount|First|Last|Tail|Head|Measure-Object|ConvertFrom-Json|Select-String|Where-Object|ForEach-Object|Out-Null|Set-Content|>\s*\S|\|\s*(head|tail|grep|rg|jq|wc|awk|sed)\b)'

    $isVerboseTarget = $cmd -match '(?i)^\s*(dotnet\s+(test|build|restore|publish)|npm\s+(test|install|ci|run\s+(build|test|lint))|pnpm\s+(test|install|build|lint)|yarn\s+(test|build|install|lint)|pytest|python\s+-m\s+pytest|pip\s+install|uv\s+sync|cargo\s+(test|build|clippy|check)|go\s+(test|build)|mvn\s+(test|package)|(\./)?gradlew\s+(test|build)|git\s+(log|diff|show|status)|docker\s+(logs|build|compose)|kubectl\s+logs|npx\s+(tsc|eslint|vitest|jest)|tsc|eslint|vitest|jest|ruff|mypy|tree|Get-ChildItem.*-Recurse)\b'

    $shouldWrapRaw = ($isRawDump -and -not $hasLimiter)
    if ($shouldWrapRaw) {
        # Allow raw reads under 800 lines to prevent repeated micro-reads doubling new input tokens
        if ($cmd -match '(?i)^\s*(?:cat|type|Get-Content|gc)\s+(?:-Path\s+)?["'']?([^"''\s;>|]+)["'']?\s*$') {
            $targetPath = $Matches[1]
            if (Test-Path $targetPath -PathType Leaf) {
                $lineCount = 0
                foreach ($ln in [System.IO.File]::ReadLines((Resolve-Path $targetPath).Path)) {
                    $lineCount++
                    if ($lineCount -ge 800) { break }
                }
                if ($lineCount -lt 800) {
                    $shouldWrapRaw = $false
                }
            }
        }
    }
    $shouldWrapCmd = (-not $alreadyQuiet -and $isVerboseTarget)

    $wrapper = Join-Path $PSScriptRoot "compress-cli.ps1"
    if (-not $hasMetaSyntax -and ($shouldWrapRaw -or $shouldWrapCmd) -and (Test-Path $wrapper)) {
        if ($shouldWrapRaw) {
            . (Join-Path $PSScriptRoot "..\lib\token-core.ps1")
            Write-TokenOptimizerEvent -EventType "cli_wrap_raw" -SavedTokens 0 -ConversationId ([string]$payload.conversationId) -Details @{ cmd = $cmd.Substring(0, [math]::Min(80, $cmd.Length)) }
        }
        $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($cmd))
        $rawFlag = if ($shouldWrapRaw) { " -MinLines 800" } else { "" }
        $wrappedCmd = ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -CmdBase64 "{1}"{2}' -f $wrapper, $b64, $rawFlag)
        $resp = @{
            decision  = "allow"
            overwrite = @{
                CommandLine = $wrappedCmd
            }
        } | ConvertTo-Json -Compress -Depth 4
        Write-Output $resp
        exit 0
    }
}
catch {
    # Fail open to avoid blocking user workflows on unexpected input.
}

Write-Output '{"decision":"allow"}'
exit 0
