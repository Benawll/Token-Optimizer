param(
    [int]$Latest = 15,
    [string]$OutputPath = (Join-Path $env:TEMP "token-optimizer-dashboard.html"),
    [switch]$Open
)

$ErrorActionPreference = "Stop"
$reportScript = Join-Path $PSScriptRoot "report-tokens.ps1"
$data = & powershell -NoProfile -ExecutionPolicy Bypass -File $reportScript -Latest $Latest | ConvertFrom-Json

$tot = $data.totals
$convRows = ($data.conversations | ForEach-Object {
    $shortId = if ($_.conversationId.Length -gt 8) { $_.conversationId.Substring(0, 8) } else { $_.conversationId }
    "<tr><td><code>$shortId</code></td><td>$($_.lastUpdated)</td><td>$($_.plannerTurns)</td><td>$([math]::Round($_.inputTokens / 1e6, 2)) M</td><td>$($_.cacheHitPct)%</td><td>$([math]::Round($_.outputTokens / 1e3, 1)) k</td><td><strong>`$$($_.estimatedUsd)</strong></td><td>`$$($_.projectedNext20TurnsUsd)</td></tr>"
}) -join "`n"

$modelRows = @()
if ($data.byModel) {
    foreach ($p in $data.byModel.PSObject.Properties) {
        $m = $p.Value
        $modelRows += "<tr><td><code>$($p.Name)</code></td><td>$($m.turns)</td><td>$([math]::Round($m.inputTokens / 1e6, 2)) M</td><td>$($m.cacheHitPct)%</td><td>$([math]::Round($m.outputTokens / 1e3, 1)) k</td><td><strong>`$$($m.estimatedUsd)</strong></td></tr>"
    }
}
$modelHtml = $modelRows -join "`n"

$html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8"/>
<title>Token Optimizer — Dashboard Antigravity</title>
<style>
  :root { --bg:#0f172a; --card:#1e293b; --text:#e2e8f0; --muted:#94a3b8; --accent:#38bdf8; --ok:#10b981; --border:#334155; }
  body { font-family: system-ui, -apple-system, Segoe UI, sans-serif; background:var(--bg); color:var(--text); margin:0; padding:24px; line-height:1.5; }
  h1 { margin:0 0 6px; font-size:22px; }
  .sub { color:var(--muted); margin:0 0 20px; font-size:13px; }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(180px,1fr)); gap:12px; margin-bottom:24px; }
  .card { background:var(--card); border:1px solid var(--border); border-radius:10px; padding:14px 16px; }
  .k { font-size:12px; color:var(--muted); text-transform:uppercase; letter-spacing:.04em; }
  .v { font-size:24px; font-weight:700; margin-top:4px; color:var(--accent); }
  .v.ok { color:var(--ok); }
  table { width:100%; border-collapse:collapse; background:var(--card); border:1px solid var(--border); border-radius:10px; overflow:hidden; margin-bottom:24px; font-size:13px; }
  th, td { padding:10px 12px; border-bottom:1px solid var(--border); text-align:left; }
  th { background:rgba(15,23,42,.5); color:var(--muted); font-weight:600; }
  code { background:rgba(56,189,248,.12); padding:2px 6px; border-radius:4px; color:#7dd3fc; }
</style>
</head>
<body>
  <h1>Token Optimizer — Dashboard Local Antigravity</h1>
  <p class="sub">Généré hors contexte modèle (0 token) à partir de $($data.sessionsAnalyzed) session(s) locale(s) — $(Get-Date -Format "yyyy-MM-dd HH:mm")</p>
  <div class="grid">
    <div class="card"><div class="k">Input total</div><div class="v">$([math]::Round($tot.inputTokens / 1e6, 2)) M</div></div>
    <div class="card"><div class="k">Cache Hit global</div><div class="v ok">$($tot.cacheHitPct)%</div></div>
    <div class="card"><div class="k">Output total</div><div class="v">$([math]::Round($tot.outputTokens / 1e3, 1)) k</div></div>
    <div class="card"><div class="k">Coût Gemini 4 est.</div><div class="v">`$$($tot.estimatedUsd)</div></div>
  </div>
  <h2>Répartition par modèle</h2>
  <table><thead><tr><th>Modèle</th><th>Tours</th><th>Input</th><th>Cache Hit</th><th>Output</th><th>Coût est.</th></tr></thead><tbody>$modelHtml</tbody></table>
  <h2>Sessions récentes</h2>
  <table><thead><tr><th>Session</th><th>Dernière MAJ</th><th>Tours</th><th>Input</th><th>Cache Hit</th><th>Output</th><th>Coût est.</th><th>Proj. +20 tours</th></tr></thead><tbody>$convRows</tbody></table>
</body>
</html>
"@

[System.IO.File]::WriteAllText($OutputPath, $html, [System.Text.UTF8Encoding]::new($false))
if ($Open) {
    Start-Process $OutputPath
}
[ordered]@{
    dashboardPath    = $OutputPath
    opened           = [bool]$Open
    sessionsAnalyzed = $data.sessionsAnalyzed
    totalInputM      = [math]::Round($tot.inputTokens / 1e6, 2)
    cacheHitPct      = $tot.cacheHitPct
    estimatedUsd     = $tot.estimatedUsd
} | ConvertTo-Json -Depth 3
