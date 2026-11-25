param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [int]$MaxEntries = 120
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Path)) {
    [ordered]@{ error = "Fichier introuvable : $Path" } | ConvertTo-Json
    exit 0
}

$resolved = (Resolve-Path $Path).Path
$ext = [System.IO.Path]::GetExtension($resolved).ToLowerInvariant()
$lines = [System.IO.File]::ReadAllLines($resolved)
$totalLines = $lines.Count

$pattern = switch -Regex ($ext) {
    '^\.(cs|java)$' {
        '^\s*(namespace\s+|(public|private|protected|internal|static|async|sealed|abstract|partial|virtual|override)\s+.*(\{|=>|\()|class\s+|struct\s+|interface\s+|enum\s+|record\s+)'
    }
    '^\.(ts|tsx|js|jsx|mjs|cjs)$' {
        '^\s*(export\s+(default\s+)?(async\s+)?(function|class|interface|type|const|enum)\b|(async\s+)?function\s+\w+|class\s+\w+|interface\s+\w+|type\s+\w+\s*=|const\s+\w+\s*=\s*(async\s*)?\()'
    }
    '^\.py$' {
        '^\s*(async\s+def\s+\w+|def\s+\w+|class\s+\w+)'
    }
    '^\.rs$' {
        '^\s*(pub(\([^)]+\))?\s+)?(async\s+)?(fn|struct|enum|trait|impl|mod)\b'
    }
    '^\.go$' {
        '^\s*(func\s+|type\s+\w+\s+(struct|interface)\b)'
    }
    '^\.ps1$' {
        '^\s*(function\s+[\w-]+|filter\s+[\w-]+|class\s+\w+)'
    }
    default {
        '^\s*(#|##|###|class\s+|def\s+|function\s+|func\s+|fn\s+|interface\s+|struct\s+|export\s+)'
    }
}

$entries = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $totalLines; $i++) {
    $ln = $lines[$i]
    if ($ln -match $pattern) {
        $trimmed = $ln.Trim()
        if ($trimmed.Length -gt 120) { $trimmed = $trimmed.Substring(0, 117) + "..." }
        $entries.Add(('L{0}: {1}' -f ($i + 1), $trimmed))
        if ($entries.Count -ge $MaxEntries) { break }
    }
}

$reduction = if ($totalLines -gt 0) { [math]::Round((1 - ($entries.Count / $totalLines)) * 100, 1) } else { 0.0 }

[ordered]@{
    file         = $resolved
    totalLines   = $totalLines
    outlineLines = $entries.Count
    reductionPct = $reduction
    outline      = @($entries)
} | ConvertTo-Json -Depth 4
