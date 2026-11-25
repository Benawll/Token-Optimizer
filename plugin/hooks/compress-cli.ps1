param(
    [Parameter(Mandatory = $true)]
    [string]$CmdBase64
)

$ErrorActionPreference = "Continue"
$origCmd = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($CmdBase64))
$utf16B64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($origCmd))

# Execute command via -EncodedCommand so quotes, variables, and special chars are never stripped
$rawLines = @(& powershell -NoProfile -EncodedCommand $utf16B64 2>&1 | ForEach-Object { [string]$_ })
$exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }

# Strip ANSI escape codes and carriage-return spinner overwrites (PS 5.1 + PS 7 compatible)
$ansiPattern = ([string][char]27) + '\[[0-9;?]*[ -/]*[@-~]'
$crChar = [string][char]13
$cleaned = [System.Collections.Generic.List[string]]::new()
$prevBlank = $false
foreach ($line in $rawLines) {
    $s = $line -replace $ansiPattern, ""
    if ($s.Contains($crChar)) {
        $parts = $s -split $crChar
        $s = $parts[-1]
    }
    $s = $s.TrimEnd()
    $isBlank = [string]::IsNullOrWhiteSpace($s)
    if ($isBlank -and $prevBlank) { continue }
    $prevBlank = $isBlank
    $cleaned.Add($s)
}

$totalChars = ($cleaned -join "`n").Length
if ($cleaned.Count -le 45 -and $totalChars -le 3500) {
    if ($cleaned.Count -gt 0) {
        $cleaned -join "`n" | Write-Output
    }
    exit $exitCode
}

# Context-Mode style local log sandbox (prune logs older than 24h)
$sandboxDir = Join-Path $env:TEMP "to-sandbox"
if (-not (Test-Path $sandboxDir)) {
    New-Item -ItemType Directory -Path $sandboxDir -Force | Out-Null
}
$cutoff = (Get-Date).AddHours(-24)
Get-ChildItem -Path $sandboxDir -Filter "cmd-*.log" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    Remove-Item -Force -ErrorAction SilentlyContinue

$hex = ([Guid]::NewGuid().ToString("N")).Substring(0, 4)
$logName = "cmd-{0}-{1}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $hex
$logPath = Join-Path $sandboxDir $logName
[System.IO.File]::WriteAllLines($logPath, $cleaned, [System.Text.UTF8Encoding]::new($false))

# Extract high-signal lines: header (5) + unique errors/warnings (up to 35) + tail (15)
$kept = [System.Collections.Generic.List[string]]::new()
$emittedSet = [System.Collections.Generic.HashSet[string]]::new()

$headCount = 0
for ($i = 0; $i -lt $cleaned.Count -and $headCount -lt 5; $i++) {
    if (-not [string]::IsNullOrWhiteSpace($cleaned[$i])) {
        $kept.Add($cleaned[$i])
        [void]$emittedSet.Add("$i")
        $headCount++
    }
}

$errRegex = '(?i)(error|fail|failed|exception|traceback|fatal|panic|assert|\bCS\d{4}\b|\bTS\d{4}\b|\bERR!|\bWARN\b|^\s*at\s|^\s*File\s+")'
$errCounts = [ordered]@{}
$errOrder = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $cleaned.Count; $i++) {
    if ($emittedSet.Contains("$i")) { continue }
    $ln = $cleaned[$i]
    if ($ln -match $errRegex) {
        if (-not $errCounts.Contains($ln)) {
            $errCounts[$ln] = 0
            $errOrder.Add($ln)
        }
        $errCounts[$ln]++
        [void]$emittedSet.Add("$i")
    }
}

if ($errOrder.Count -gt 0) {
    $kept.Add("--- [Erreurs / Avertissements extraits] ---")
    $shownErr = 0
    foreach ($msg in $errOrder) {
        if ($shownErr -ge 35) { break }
        $cnt = $errCounts[$msg]
        if ($cnt -gt 1) { $kept.Add("$msg [x$cnt]") } else { $kept.Add($msg) }
        $shownErr++
    }
}

$tailIndices = [System.Collections.Generic.List[int]]::new()
for ($i = $cleaned.Count - 1; $i -ge 0 -and $tailIndices.Count -lt 15; $i--) {
    if (-not $emittedSet.Contains("$i") -and -not [string]::IsNullOrWhiteSpace($cleaned[$i])) {
        $tailIndices.Add($i)
    }
}
if ($tailIndices.Count -gt 0) {
    $kept.Add("--- [Fin de sortie] ---")
    $tailIndices.Reverse()
    foreach ($idx in $tailIndices) {
        $kept.Add($cleaned[$idx])
    }
}

$origCount = $cleaned.Count
$keptCount = $kept.Count
$pct = if ($origCount -gt 0) { [math]::Round((1 - ($keptCount / $origCount)) * 100) } else { 0 }
$kept.Add(('[Token Optimizer: {0} -> {1} lignes (-{2}%) | Exit: {3} | Log complet: {4} (rg/read_file si besoin)]' -f $origCount, $keptCount, $pct, $exitCode, $logPath))

$kept -join "`n" | Write-Output
exit $exitCode
