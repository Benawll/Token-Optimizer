param(
    [int]$OlderThanDays = 30,
    [switch]$Apply,
    [string]$BrainRoot = (Join-Path $env:USERPROFILE ".gemini\antigravity\brain")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $BrainRoot)) {
    [ordered]@{ error = "Dossier brain introuvable : $BrainRoot" } | ConvertTo-Json
    exit 0
}

$cutoff = (Get-Date).AddDays(-$OlderThanDays)
$archiveDir = Join-Path (Split-Path -Parent $BrainRoot) "brain_archive"

$candidates = @(Get-ChildItem -Path $BrainRoot -Directory | Where-Object {
    $_.Name -ne "brain_archive" -and $_.LastWriteTime -lt $cutoff
})

$items = [System.Collections.Generic.List[object]]::new()
$totalBytes = 0L

foreach ($dir in $candidates) {
    $size = (Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if (-not $size) { $size = 0L }
    $totalBytes += [long]$size
    $items.Add([ordered]@{
        conversationId = $dir.Name
        lastWriteTime  = $dir.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        sizeMB         = [math]::Round($size / 1MB, 2)
    })

    if ($Apply) {
        if (-not (Test-Path $archiveDir)) {
            New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
        }
        $zipPath = Join-Path $archiveDir "$($dir.Name).zip"
        Compress-Archive -Path $dir.FullName -DestinationPath $zipPath -Force
        if (Test-Path $zipPath) {
            Remove-Item -Path $dir.FullName -Recurse -Force
        }
    }
}

[ordered]@{
    mode           = if ($Apply) { "archived" } else { "dry-run" }
    olderThanDays  = $OlderThanDays
    archiveDir     = $archiveDir
    candidateCount = $items.Count
    totalSizeMB    = [math]::Round($totalBytes / 1MB, 2)
    sessions       = @($items | Select-Object -First 20)
    note           = "Nettoyage disque et UI locale uniquement — n'affecte pas la facturation tokens des sessions actives."
} | ConvertTo-Json -Depth 4
