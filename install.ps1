param(
    [string]$TargetDir = (Join-Path $env:USERPROFILE ".gemini\config\plugins\token-optimizer"),
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

if ($Uninstall) {
    if (Test-Path $TargetDir) {
        Remove-Item -Path $TargetDir -Recurse -Force
        Write-Host "Plugin 'token-optimizer' désinstallé de : $TargetDir"
    }
    else {
        Write-Host "Plugin déjà absent : $TargetDir"
    }
    exit 0
}

$sourceDir = Join-Path $PSScriptRoot "plugin"
if (-not (Test-Path $sourceDir)) {
    throw "Dossier source introuvable : $sourceDir"
}

# Valider les JSON et scripts PowerShell avant installation
$null = Get-Content -Raw (Join-Path $sourceDir "plugin.json") | ConvertFrom-Json
$null = Get-Content -Raw (Join-Path $sourceDir "hooks.json") | ConvertFrom-Json
Get-ChildItem -Path $sourceDir -Filter "*.ps1" -Recurse -File | ForEach-Object {
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Erreur de syntaxe PowerShell dans $($_.FullName)"
    }
}

if (Test-Path $TargetDir) {
    Remove-Item -Path $TargetDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
Copy-Item -Path (Join-Path $sourceDir "*") -Destination $TargetDir -Recurse -Force

Write-Host "Plugin 'token-optimizer' installé avec succès dans : $TargetDir"
Write-Host "Il sera chargé automatiquement dès le prochain tour / nouvelle session Antigravity."
