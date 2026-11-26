param(
    [string]$ConversationId = "",
    [string]$BrainRoot = (Join-Path $env:USERPROFILE ".gemini\antigravity\brain"),
    [switch]$CreateConversation,
    [string]$Title = "",
    [string]$Model = "",
    [string]$NextStep = "",
    [string]$PromptText = ""
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

$nextLine = if (-not [string]::IsNullOrWhiteSpace($NextStep)) {
    $NextStep.Trim()
} else {
    "[compléter en 1 ligne avant d'envoyer dans une nouvelle session]"
}
$recentRequests = @($userInputs | Select-Object -Last 4)
$handoffLines = @(
    "# Handoff de session ($cid)",
    "- **Tours précédents** : $turns (dernier modèle : $lastModel)",
    "- **Dernières demandes utilisateur** :"
) + ($recentRequests | ForEach-Object { "  - $_" }) + @(
    "- **Prochaine étape** : $nextLine"
)
$handoffText = $handoffLines -join "`n"
$finalPrompt = if (-not [string]::IsNullOrWhiteSpace($PromptText)) { $PromptText } else { $handoffText }

$created = $false
$newConvId = ""
$createError = ""

if ($CreateConversation) {
    $lsAddr = $env:ANTIGRAVITY_LS_ADDRESS
    $csrf = $env:ANTIGRAVITY_CSRF_TOKEN
    if ([string]::IsNullOrWhiteSpace($lsAddr) -or [string]::IsNullOrWhiteSpace($csrf)) {
        $createError = "Variables ANTIGRAVITY_LS_ADDRESS ou ANTIGRAVITY_CSRF_TOKEN indisponibles."
    }
    else {
        try {
            $shortId = $cid.Substring(0, [math]::Min(8, $cid.Length))
            $convTitle = if (-not [string]::IsNullOrWhiteSpace($Title)) { $Title } else { "Handoff — $shortId" }
            $bodyObj = [ordered]@{
                title  = $convTitle
                tags   = @("handoff")
                prompt = @([ordered]@{ text = $finalPrompt })
            }
            if (-not [string]::IsNullOrWhiteSpace($env:ANTIGRAVITY_PROJECT_ID)) {
                $bodyObj.projectId = $env:ANTIGRAVITY_PROJECT_ID
            }
            if (-not [string]::IsNullOrWhiteSpace($Model)) {
                $bodyObj.model = $Model
            }
            $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes(($bodyObj | ConvertTo-Json -Depth 5 -Compress))
            $headers = @{
                "Connect-Protocol-Version" = "1"
                "x-antigravity-csrf-token" = $csrf
            }
            $resp = Invoke-RestMethod -Method Post -Uri "http://$lsAddr/product.v1.ConversationService/CreateConversation" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $jsonBytes -TimeoutSec 10
            if ($resp -and $resp.conversation -and $resp.conversation.id) {
                $created = $true
                $newConvId = [string]$resp.conversation.id
            }
            else {
                $createError = "Réponse CreateConversation inattendue."
            }
        }
        catch {
            $createError = $_.Exception.Message
        }
    }
}

$outObj = [ordered]@{
    conversationId = $cid
    turns          = $turns
    handoffText    = $handoffText
}
if ($CreateConversation) {
    $outObj.created = $created
    $outObj.newConversationId = $newConvId
    if ($createError) { $outObj.createError = $createError }
}
$outObj | ConvertTo-Json -Depth 4
