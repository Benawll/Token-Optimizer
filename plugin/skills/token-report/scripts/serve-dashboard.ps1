param(
    [int]$Port = 4891,
    [int]$Latest = 20,
    [string]$DashboardPath = (Join-Path $env:TEMP "token-optimizer-dashboard.html"),
    [switch]$NoOpen
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\..\..\lib\token-core.ps1")

$baseUrl = "http://127.0.0.1:$Port/"

# If already running on this port, open browser and exit cleanly
try {
    $ping = Invoke-RestMethod -Uri ($baseUrl + "api/live") -TimeoutSec 2 -ErrorAction Stop
    if ($ping -and $ping.ok) {
        if (-not $NoOpen) { Start-Process $baseUrl }
        exit 0
    }
}
catch {}

# Generate initial dashboard HTML
$genScript = Join-Path $PSScriptRoot "generate-dashboard.ps1"
& $genScript -Latest $Latest -OutputPath $DashboardPath | Out-Null

function Get-LiveCachePayload {
    $brainRoot = Join-Path $env:USERPROFILE ".gemini\antigravity\brain"
    $res = [ordered]@{
        ok                = $true
        serverUtc         = ([datetime]::UtcNow).ToString("o")
        conversationId    = ""
        lastModel         = "unknown"
        lastContextTokens = 0L
        cacheReadTokens   = 0L
        uncachedTokens    = 0L
        lastEventUtc      = $null
        idleSeconds       = 0
        remainingSeconds  = 300
        status            = "warm"
    }
    if (-not (Test-Path $brainRoot)) { return $res }

    $latestFile = Get-ChildItem -Path $brainRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName ".system_generated\logs\transcript.jsonl" } |
        Where-Object { Test-Path $_ } |
        ForEach-Object { Get-Item $_ } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $latestFile) { return $res }

    $res.conversationId = $latestFile.Directory.Parent.Parent.Name
    $tail = @(Get-Content -Path $latestFile.FullName -Tail 30 -ErrorAction SilentlyContinue)
    $lastEv = $null
    for ($i = $tail.Count - 1; $i -ge 0; $i--) {
        if ($tail[$i] -match '"type":"PLANNER_RESPONSE"') {
            try { $lastEv = $tail[$i] | ConvertFrom-Json; break } catch {}
        }
    }

    if ($lastEv) {
        $unc = [long]$lastEv.input_tokens
        $cac = [long]$lastEv.cache_read_tokens
        $evUtc = ConvertTo-UtcDateTime -Value $lastEv.created_at -FallbackUtc $latestFile.LastWriteTimeUtc
        $idleSec = [int][math]::Max(0, [math]::Floor(([datetime]::UtcNow - $evUtc).TotalSeconds))
        $remSec = [int][math]::Max(0, 300 - $idleSec)

        $res.lastModel = if ($lastEv.model) { [string]$lastEv.model } else { "unknown" }
        $res.uncachedTokens = $unc
        $res.cacheReadTokens = $cac
        $res.lastContextTokens = $unc + $cac
        $res.lastEventUtc = $evUtc.ToString("o")
        $res.idleSeconds = $idleSec
        $res.remainingSeconds = $remSec
        $res.status = if ($remSec -gt 120) { "warm" } elseif ($remSec -gt 0) { "warning" } else { "expired" }
    }
    return $res
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($baseUrl)
$listener.Start()

if (-not $NoOpen) {
    Start-Process $baseUrl
}

Write-Host "Token Optimizer Live Monitor actif sur $baseUrl (Ctrl+C pour arrêter)"

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $resp = $ctx.Response
        $path = $req.Url.AbsolutePath

        try {
            if ($path -eq "/" -or $path -eq "/dashboard.html") {
                $html = if (Test-Path $DashboardPath) {
                    [System.IO.File]::ReadAllText($DashboardPath, [System.Text.Encoding]::UTF8)
                } else {
                    "<html><body>Dashboard introuvable</body></html>"
                }
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
                $resp.StatusCode = 200
                $resp.ContentType = "text/html; charset=utf-8"
                $resp.Headers.Add("Cache-Control", "no-store")
                $resp.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            elseif ($path -eq "/api/live") {
                $json = (Get-LiveCachePayload) | ConvertTo-Json -Compress
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $resp.StatusCode = 200
                $resp.ContentType = "application/json; charset=utf-8"
                $resp.Headers.Add("Cache-Control", "no-store")
                $resp.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            elseif ($path -eq "/api/refresh") {
                & $genScript -Latest $Latest -OutputPath $DashboardPath | Out-Null
                $json = ([ordered]@{ ok = $true; refreshedAt = (Get-Date).ToString("HH:mm:ss") }) | ConvertTo-Json -Compress
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $resp.StatusCode = 200
                $resp.ContentType = "application/json; charset=utf-8"
                $resp.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            elseif ($path -eq "/api/stop") {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true,"stopping":true}')
                $resp.StatusCode = 200
                $resp.ContentType = "application/json; charset=utf-8"
                $resp.OutputStream.Write($bytes, 0, $bytes.Length)
                $resp.Close()
                break
            }
            else {
                $resp.StatusCode = 404
            }
        }
        finally {
            try { $resp.Close() } catch {}
        }
    }
}
finally {
    try { $listener.Stop(); $listener.Close() } catch {}
}
