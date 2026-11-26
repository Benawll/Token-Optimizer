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

$script:LiveTranscriptCache = @{}
$script:LiveProjectCache = @{}

function Get-LiveProjectName {
    param(
        [string]$TranscriptPath,
        [string]$ConversationId
    )
    if ($ConversationId -and $script:LiveProjectCache.ContainsKey($ConversationId)) {
        return $script:LiveProjectCache[$ConversationId]
    }
    $candidates = [System.Collections.Generic.List[string]]::new()
    $headLines = Get-Content -Path $TranscriptPath -TotalCount 40 -ErrorAction SilentlyContinue
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
                if ($first -ieq 'Users' -and $segs.Count -ge 3) {
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
    $winner = if ($candidates.Count -gt 0) {
        ($candidates | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
    } else { "Général" }
    if ($ConversationId) { $script:LiveProjectCache[$ConversationId] = $winner }
    return $winner
}

function Get-LiveSessionMetrics {
    param([System.IO.FileInfo]$File)
    $key = $File.FullName
    $ticks = $File.LastWriteTimeUtc.Ticks
    $len = $File.Length
    if ($script:LiveTranscriptCache.ContainsKey($key)) {
        $cached = $script:LiveTranscriptCache[$key]
        if ($cached.ticks -eq $ticks -and $cached.length -eq $len) {
            return $cached
        }
    }

    $turns = 0
    $lastLine = $null
    foreach ($ln in [System.IO.File]::ReadLines($File.FullName)) {
        if ($ln -match '"type":"PLANNER_RESPONSE"') {
            $turns++
            $lastLine = $ln
        }
    }

    $lastModel = "unknown"
    $unc = 0L
    $cac = 0L
    $evUtc = $File.LastWriteTimeUtc
    if ($lastLine) {
        try {
            $lastEv = $lastLine | ConvertFrom-Json
            if ($lastEv.model) { $lastModel = [string]$lastEv.model }
            $unc = [long]$lastEv.input_tokens
            $cac = [long]$lastEv.cache_read_tokens
            $evUtc = ConvertTo-UtcDateTime -Value $lastEv.created_at -FallbackUtc $File.LastWriteTimeUtc
        } catch {}
    }

    $entry = @{
        ticks             = $ticks
        length            = $len
        turns             = $turns
        lastModel         = $lastModel
        uncachedTokens    = $unc
        cacheReadTokens   = $cac
        lastContextTokens = ($unc + $cac)
        lastEventUtc      = $evUtc
    }
    $script:LiveTranscriptCache[$key] = $entry
    return $entry
}

function Get-HandoffLevel {
    param([int]$Turns, [long]$CtxTokens)
    if ($Turns -ge 120 -or $CtxTokens -ge 150000) { return "urgent" }
    if ($Turns -ge 70 -or $CtxTokens -ge 110000) { return "handoff" }
    if ($Turns -ge 35 -or $CtxTokens -ge 75000) { return "watch" }
    return "ok"
}

function Get-ArchiveStatus {
    param([double]$AgeDays)
    if ($AgeDays -ge 30) { return "ready" }
    if ($AgeDays -ge 21) { return "soon" }
    return "active"
}

function Get-LiveCachePayload {
    $brainRoot = Join-Path $env:USERPROFILE ".gemini\antigravity\brain"
    $res = [ordered]@{
        ok                  = $true
        serverUtc           = ([datetime]::UtcNow).ToString("o")
        conversationId      = ""
        project             = "Général"
        turns               = 0
        lastModel           = "unknown"
        lastContextTokens   = 0L
        cacheReadTokens     = 0L
        uncachedTokens      = 0L
        lastEventUtc        = $null
        idleSeconds         = 0
        remainingSeconds    = 300
        status              = "warm"
        ageDays             = 0.0
        handoffLevel        = "ok"
        archiveStatus       = "active"
        recentConversations = @()
    }
    if (-not (Test-Path $brainRoot)) { return $res }

    $recentFiles = @(Get-ChildItem -Path $brainRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName ".system_generated\logs\transcript.jsonl" } |
        Where-Object { Test-Path $_ } |
        ForEach-Object { Get-Item $_ } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 5)

    if ($recentFiles.Count -eq 0) { return $res }

    $nowUtc = [datetime]::UtcNow
    $recentList = [System.Collections.Generic.List[object]]::new()

    foreach ($tf in $recentFiles) {
        $cid = $tf.Directory.Parent.Parent.Name
        $proj = Get-LiveProjectName -TranscriptPath $tf.FullName -ConversationId $cid
        $met = Get-LiveSessionMetrics -File $tf
        $evUtc = $met.lastEventUtc
        $idleSec = [int][math]::Max(0, [math]::Floor(($nowUtc - $evUtc).TotalSeconds))
        $remSec = [int][math]::Max(0, 300 - $idleSec)
        $ageDays = [math]::Round(($nowUtc - $evUtc).TotalDays, 1)
        $st = if ($remSec -gt 120) { "warm" } elseif ($remSec -gt 0) { "warning" } else { "expired" }
        $hLvl = Get-HandoffLevel -Turns $met.turns -CtxTokens $met.lastContextTokens
        $aStat = Get-ArchiveStatus -AgeDays $ageDays

        $recentList.Add([ordered]@{
            conversationId    = $cid
            project           = $proj
            turns             = $met.turns
            lastModel         = $met.lastModel
            lastContextTokens = $met.lastContextTokens
            uncachedTokens    = $met.uncachedTokens
            cacheReadTokens   = $met.cacheReadTokens
            lastEventUtc      = $evUtc.ToString("o")
            idleSeconds       = $idleSec
            remainingSeconds  = $remSec
            status            = $st
            ageDays           = $ageDays
            handoffLevel      = $hLvl
            archiveStatus     = $aStat
        })
    }

    $top = $recentList[0]
    $res.conversationId = $top.conversationId
    $res.project = $top.project
    $res.turns = $top.turns
    $res.lastModel = $top.lastModel
    $res.lastContextTokens = $top.lastContextTokens
    $res.cacheReadTokens = $top.cacheReadTokens
    $res.uncachedTokens = $top.uncachedTokens
    $res.lastEventUtc = $top.lastEventUtc
    $res.idleSeconds = $top.idleSeconds
    $res.remainingSeconds = $top.remainingSeconds
    $res.status = $top.status
    $res.ageDays = $top.ageDays
    $res.handoffLevel = $top.handoffLevel
    $res.archiveStatus = $top.archiveStatus
    $res.recentConversations = @($recentList)
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
                $json = (Get-LiveCachePayload) | ConvertTo-Json -Depth 5 -Compress
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
