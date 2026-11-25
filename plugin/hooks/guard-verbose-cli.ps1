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

    # 1. Block unbounded raw file dumps (cat/type/Get-Content/gc without limiter)
    $isRawDump = $cmd -match '(?i)(^|[;&|]\s*)(cat|type|Get-Content|gc)\s+'
    $hasLimiter = $cmd -match '(?i)(Select-Object|TotalCount|First|Last|Tail|Head|Measure-Object|ConvertFrom-Json|Select-String|Where-Object|ForEach-Object|Out-Null|Set-Content|>\s*\S|\|\s*(head|tail|grep|rg|jq|wc|awk|sed)\b)'

    if ($isRawDump -and -not $hasLimiter) {
        $resp = @{
            decision = "deny"
            reason   = "Token Optimizer: lecture brute non bornée détectée. Utilisez read_file (avec StartLine/EndLine) ou limitez la sortie (ex: | Select-Object -Last 50)."
        } | ConvertTo-Json -Compress
        Write-Output $resp
        exit 0
    }

    # 2. RTK-style transparent compression for single verbose dev commands
    $hasMetaSyntax = ($cmd -match '[|><;\r\n]') -or ($cmd -match '&&') -or ($cmd -match 'compress-cli\.ps1')
    $alreadyQuiet = $cmd -match '(?i)(--quiet|\s-q\b|--silent|--verbosity\s+(q|quiet|m|minimal)|--stat|--name-only|--oneline|\s-n\s+\d+|--max-count)'
    $isVerboseTarget = $cmd -match '(?i)^\s*(dotnet\s+(test|build|restore|publish)|npm\s+(test|install|ci|run\s+(build|test))|pnpm\s+(test|install|build)|yarn\s+(test|build|install)|pytest|python\s+-m\s+pytest|pip\s+install|uv\s+sync|cargo\s+(test|build|clippy|check)|go\s+(test|build)|mvn\s+(test|package)|(\./)?gradlew\s+(test|build)|git\s+(log|diff))\b'

    $wrapper = Join-Path $PSScriptRoot "compress-cli.ps1"
    if (-not $hasMetaSyntax -and -not $alreadyQuiet -and $isVerboseTarget -and (Test-Path $wrapper)) {
        $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($cmd))
        $wrappedCmd = ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -CmdBase64 "{1}"' -f $wrapper, $b64)
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
