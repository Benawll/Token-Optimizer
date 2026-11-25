param(
    [string]$ConversationId = "",
    [string]$BrainRoot = (Join-Path $env:USERPROFILE ".gemini\antigravity\brain")
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $BrainRoot)) {
    [ordered]@{ error = "Dossier brain introuvable : $BrainRoot" } | ConvertTo-Json
    exit 0
}

$transcript = if ($ConversationId) {
    $p = Join-Path $BrainRoot "$ConversationId\.system_generated\logs\transcript.jsonl"
    if (Test-Path $p) { Get-Item $p } else { $null }
}
else {
    Get-ChildItem -Path $BrainRoot -Directory |
        ForEach-Object { Join-Path $_.FullName ".system_generated\logs\transcript.jsonl" } |
        Where-Object { Test-Path $_ } |
        ForEach-Object { Get-Item $_ } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

if (-not $transcript) {
    [ordered]@{ error = "Aucun transcript trouvé." } | ConvertTo-Json
    exit 0
}

$cid = $transcript.Directory.Parent.Parent.Name
$userInputs = [System.Collections.Generic.List[string]]::new()
$turns = 0
$lastModel = "unknown"

foreach ($line in [System.IO.File]::ReadLines($transcript.FullName)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $ev = $line | ConvertFrom-Json } catch { continue }
    if ($ev.type -eq "USER_INPUT" -and $ev.content) {
        $txt = ([string]$ev.content) -replace '<[^>]+>', ' ' -replace '\s+', ' '
        $txt = $txt.Trim()
        if ($txt.Length -gt 140) { $txt = $txt.Substring(0, 137) + "..." }
        if ($txt) { $userInputs.Add($txt) }
    }
    elseif ($ev.type -eq "PLANNER_RESPONSE") {
        $turns++
        if ($ev.model) { $lastModel = [string]$ev.model }
    }
}

$recentRequests = @($userInputs | Select-Object -Last 4)
$handoffLines = @(
    "# Handoff de session ($cid)",
    "- **Tours précédents** : $turns (dernier modèle : $lastModel)",
    "- **Dernières demandes utilisateur** :"
) + ($recentRequests | ForEach-Object { "  - $_" }) + @(
    "- **Prochaine étape** : [compléter en 1 ligne avant d'envoyer dans une nouvelle session]"
)

[ordered]@{
    conversationId = $cid
    turns          = $turns
    handoffText    = ($handoffLines -join "`n")
} | ConvertTo-Json -Depth 3
