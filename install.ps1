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

# Persister la date de première installation sans jamais l'écraser lors des mises à jour
$configRoot = Join-Path $env:USERPROFILE ".gemini\config"
$metaPath = Join-Path $configRoot "token-optimizer-meta.json"
$existingPluginJson = Join-Path $TargetDir "plugin.json"
if (-not (Test-Path $metaPath)) {
    if (-not (Test-Path $configRoot)) {
        New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
    }
    $initialUtc = if (Test-Path $existingPluginJson) {
        (Get-Item $existingPluginJson).CreationTimeUtc
    } else {
        (Get-Date).ToUniversalTime()
    }
    $metaJson = [ordered]@{
        installedAtUtc = $initialUtc.ToString("o")
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($metaPath, $metaJson, [System.Text.UTF8Encoding]::new($false))
}

if (Test-Path $TargetDir) {
    Remove-Item -Path $TargetDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
Copy-Item -Path (Join-Path $sourceDir "*") -Destination $TargetDir -Recurse -Force

Write-Host "Plugin 'token-optimizer' installé avec succès dans : $TargetDir"
Write-Host "Il sera chargé automatiquement dès le prochain tour / nouvelle session Antigravity."
