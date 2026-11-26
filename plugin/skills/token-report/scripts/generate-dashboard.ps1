param(
    [int]$Latest = 20,
    [string]$OutputPath = (Join-Path $env:TEMP "token-optimizer-dashboard.html"),
    [switch]$Open
)

$ErrorActionPreference = "Stop"
$reportScript = Join-Path $PSScriptRoot "report-tokens.ps1"
$jsonRaw = & powershell -NoProfile -ExecutionPolicy Bypass -File $reportScript -Latest $Latest
$data = $jsonRaw | ConvertFrom-Json

$tot = $data.totals
$jsonDataEscaped = $jsonRaw.Replace("\", "\\").Replace("`$", "\`$")

$html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>Token Optimizer — Dashboard Économies & Métriques</title>
<style>
  :root {
    --bg: #0b1120;
    --card: #151f32;
    --card-hover: #1e2942;
    --text: #f1f5f9;
    --muted: #94a3b8;
    --accent: #38bdf8;
    --emerald: #10b981;
    --amber: #f59e0b;
    --rose: #f43f5e;
    --border: #24324d;
    --tab-active: #0284c7;
  }
  * { box-sizing: border-box; }
  body {
    font-family: system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
    margin: 0;
    padding: 24px;
    line-height: 1.5;
  }
  .header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    border-bottom: 1px solid var(--border);
    padding-bottom: 16px;
    margin-bottom: 20px;
    flex-wrap: wrap;
    gap: 12px;
  }
  h1 { margin: 0 0 4px; font-size: 24px; font-weight: 700; color: #fff; }
  .badge-env {
    display: inline-block;
    background: rgba(16, 185, 129, 0.15);
    color: var(--emerald);
    border: 1px solid rgba(16, 185, 129, 0.3);
    padding: 3px 8px;
    border-radius: 6px;
    font-size: 11px;
    font-weight: 600;
  }
  .sub { color: var(--muted); margin: 0; font-size: 13px; }
  
  /* Tabs */
  .tabs-nav {
    display: flex;
    gap: 8px;
    margin-bottom: 20px;
    border-bottom: 1px solid var(--border);
    padding-bottom: 10px;
  }
  .tab-btn {
    background: transparent;
    border: 1px solid var(--border);
    color: var(--muted);
    padding: 10px 18px;
    border-radius: 8px;
    cursor: pointer;
    font-size: 14px;
    font-weight: 600;
    transition: all .2s;
  }
  .tab-btn:hover { background: var(--card); color: #fff; }
  .tab-btn.active {
    background: var(--tab-active);
    color: #fff;
    border-color: var(--tab-active);
    box-shadow: 0 0 12px rgba(2, 132, 199, 0.4);
  }
  
  .tab-content { display: none; }
  .tab-content.active { display: block; }

  /* Filters */
  .filter-bar {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 12px 16px;
    margin-bottom: 20px;
    display: flex;
    flex-wrap: wrap;
    gap: 16px;
    align-items: center;
    font-size: 13px;
  }
  .filter-group { display: flex; align-items: center; gap: 8px; }
  .filter-group span { color: var(--muted); font-weight: 600; text-transform: uppercase; font-size: 11px; }
  .btn-pill {
    background: rgba(255,255,255,0.05);
    border: 1px solid var(--border);
    color: var(--text);
    padding: 5px 12px;
    border-radius: 20px;
    font-size: 12px;
    cursor: pointer;
    transition: all .15s;
  }
  .btn-pill:hover { background: rgba(56, 189, 248, 0.15); border-color: var(--accent); }
  .btn-pill.active {
    background: var(--accent);
    color: #0b1120;
    border-color: var(--accent);
    font-weight: 700;
  }

  /* KPI Grid */
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; margin-bottom: 24px; }
  .card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 16px 18px;
    position: relative;
    overflow: hidden;
  }
  .card::before {
    content: '';
    position: absolute;
    top: 0; left: 0; right: 0; height: 3px;
    background: var(--border);
  }
  .card.gain::before { background: linear-gradient(90deg, #10b981, #38bdf8); }
  .card.tokens::before { background: linear-gradient(90deg, #38bdf8, #818cf8); }
  .card.spent::before { background: linear-gradient(90deg, #f59e0b, #ef4444); }
  .card.cache::before { background: linear-gradient(90deg, #10b981, #059669); }
  
  .k { font-size: 12px; color: var(--muted); text-transform: uppercase; font-weight: 600; letter-spacing: .04em; }
  .v { font-size: 28px; font-weight: 800; margin-top: 6px; color: #fff; }
  .v.gain { color: var(--emerald); }
  .v.tokens { color: var(--accent); }
  .v.spent { color: var(--amber); }
  .v.cache { color: #34d399; }
  .hint { font-size: 11px; color: var(--muted); margin-top: 4px; }

  /* Tables */
  h2 { font-size: 16px; margin: 24px 0 10px; color: #fff; font-weight: 600; display: flex; align-items: center; gap: 8px; }
  table {
    width: 100%;
    border-collapse: collapse;
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 10px;
    overflow: hidden;
    margin-bottom: 24px;
    font-size: 13px;
  }
  th, td { padding: 10px 14px; border-bottom: 1px solid var(--border); text-align: left; }
  th { background: rgba(11, 17, 32, 0.6); color: var(--muted); font-weight: 600; font-size: 12px; text-transform: uppercase; }
  tr:hover td { background: rgba(255, 255, 255, 0.02); }
  code { background: rgba(56, 189, 248, 0.12); padding: 2px 6px; border-radius: 4px; color: #7dd3fc; font-size: 12px; }
  .tag-proj {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 12px;
    font-size: 11px;
    font-weight: 600;
    background: rgba(129, 140, 248, 0.18);
    color: #a5b4fc;
    border: 1px solid rgba(129, 140, 248, 0.3);
  }
  .tag-proj.Career-Ops { background: rgba(16, 185, 129, 0.15); color: #6ee7b7; border-color: rgba(16, 185, 129, 0.3); }
  .tag-proj.Token-Optimizer { background: rgba(56, 189, 248, 0.15); color: #7dd3fc; border-color: rgba(56, 189, 248, 0.3); }
  .tag-proj.Awll { background: rgba(245, 158, 11, 0.15); color: #fcd34d; border-color: rgba(245, 158, 11, 0.3); }
  .eur-gain { color: var(--emerald); font-weight: 700; }
</style>
</head>
<body>

  <div class="header">
    <div>
      <h1>Token Optimizer — Tableau de Bord</h1>
      <p class="sub">Fuseau horaire : <strong>Europe/Paris (UTC+1)</strong> — Analyse hors-contexte (0 token IA) générée à $(Get-Date -Format "dd/MM/yyyy HH:mm")</p>
    </div>
    <div>
      <span class="badge-env">Devise : EUR (€)</span>
    </div>
  </div>

  <div class="tabs-nav">
    <button class="tab-btn active" onclick="switchTab('tab-roi')">💰 Économies & ROI (Prioritaire)</button>
    <button class="tab-btn" onclick="switchTab('tab-tech')">⚙️ Métriques Techniques & Modèles</button>
  </div>

  <!-- ONGLET 1 : ÉCONOMIES & ROI -->
  <div id="tab-roi" class="tab-content active">

    <!-- Barres de filtres -->
    <div class="filter-bar">
      <div class="filter-group">
        <span>Période :</span>
        <button class="btn-pill active" onclick="setPeriodFilter('all', this)">Toutes</button>
        <button class="btn-pill" onclick="setPeriodFilter('today', this)">Aujourd'hui</button>
        <button class="btn-pill" onclick="setPeriodFilter('24h', this)">Dernières 24h</button>
        <button class="btn-pill" onclick="setPeriodFilter('7d', this)">7 derniers jours</button>
      </div>
      <div class="filter-group">
        <span>Projet :</span>
        <button class="btn-pill active" onclick="setProjectFilter('all', this)">Tous</button>
        <button class="btn-pill" onclick="setProjectFilter('Career Ops', this)">Career Ops</button>
        <button class="btn-pill" onclick="setProjectFilter('Token Optimizer', this)">Token Optimizer</button>
        <button class="btn-pill" onclick="setProjectFilter('Awll', this)">Awll</button>
        <button class="btn-pill" onclick="setProjectFilter('Général', this)">Autres</button>
      </div>
    </div>

    <!-- Double Compteur et KPIs -->
    <div class="grid">
      <div class="card gain">
        <div class="k">Argent Économisé (€)</div>
        <div class="v gain" id="kpi-saved-eur">0,00 €</div>
        <div class="hint">Gain net comparé au tarif Neon brut non optimisé</div>
      </div>
      <div class="card tokens">
        <div class="k">Tokens Épargnés</div>
        <div class="v tokens" id="kpi-saved-tokens">0 M</div>
        <div class="hint">Tokens en cache & compression CLI économisés</div>
      </div>
      <div class="card spent">
        <div class="k">Coût Réel Consommé</div>
        <div class="v spent" id="kpi-cost-eur">0,00 €</div>
        <div class="hint">Facture réelle estimée sur les sessions filtrées</div>
      </div>
      <div class="card cache">
        <div class="k">Taux de Cache Global</div>
        <div class="v cache" id="kpi-cache-pct">0%</div>
        <div class="hint">Pourcentage de requêtes servies par le cache</div>
      </div>
    </div>

    <h2>📁 Répartition des Économies par Projet</h2>
    <table>
      <thead>
        <tr>
          <th>Projet</th>
          <th>Sessions</th>
          <th>Tours d'IA</th>
          <th>Tokens Épargnés</th>
          <th>Coût Réel (€)</th>
          <th>Argent Économisé (€)</th>
        </tr>
      </thead>
      <tbody id="project-rows"></tbody>
    </table>

    <h2>⏱️ Détail par Conversation (Heure de Paris)</h2>
    <table>
      <thead>
        <tr>
          <th>Projet</th>
          <th>Session</th>
          <th>Dernière Activité</th>
          <th>Tours</th>
          <th>Tokens Épargnés</th>
          <th>Cache Hit</th>
          <th>Coût Réel</th>
          <th>Économies Réalisées</th>
        </tr>
      </thead>
      <tbody id="session-roi-rows"></tbody>
    </table>
  </div>

  <!-- ONGLET 2 : MÉTRIQUES TECHNIQUES -->
  <div id="tab-tech" class="tab-content">
    <h2>🤖 Répartition de l'Utilisation par Modèle</h2>
    <table>
      <thead>
        <tr>
          <th>Modèle</th>
          <th>Tours</th>
          <th>Input</th>
          <th>Cache Hit</th>
          <th>Output</th>
          <th>Coût (€)</th>
        </tr>
      </thead>
      <tbody id="model-rows"></tbody>
    </table>

    <h2>⚠️ Commandes CLI les Plus Volumineuses (Compressées par le plugin)</h2>
    <table>
      <thead>
        <tr>
          <th>Session</th>
          <th>Projet</th>
          <th>Étape</th>
          <th>Caractères</th>
          <th>Tokens Épargnés</th>
          <th>Aperçu</th>
        </tr>
      </thead>
      <tbody id="verbose-rows"></tbody>
    </table>

    <h2>📋 Sessions Complètes & Projections</h2>
    <table>
      <thead>
        <tr>
          <th>Session</th>
          <th>Projet</th>
          <th>Date (France)</th>
          <th>Input Total</th>
          <th>Cache Hit</th>
          <th>Output</th>
          <th>Coût Réel (€)</th>
          <th>Projection +20 tours</th>
        </tr>
      </thead>
      <tbody id="session-tech-rows"></tbody>
    </table>
  </div>

<script>
  const RAW_DATA = $jsonDataEscaped;

  let currentPeriod = 'all';
  let currentProject = 'all';

  function switchTab(tabId) {
    document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
    document.querySelectorAll('.tab-btn').forEach(el => el.classList.remove('active'));
    document.getElementById(tabId).classList.add('active');
    event.currentTarget.classList.add('active');
  }

  function setPeriodFilter(p, btn) {
    currentPeriod = p;
    btn.parentElement.querySelectorAll('.btn-pill').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    render();
  }

  function setProjectFilter(proj, btn) {
    currentProject = proj;
    btn.parentElement.querySelectorAll('.btn-pill').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    render();
  }

  function isWithinPeriod(dateIso, period) {
    if (period === 'all') return true;
    const d = new Date(dateIso);
    const now = new Date();
    const diffHours = (now - d) / (1000 * 60 * 60);
    if (period === '24h') return diffHours <= 24;
    if (period === '7d') return diffHours <= (24 * 7);
    if (period === 'today') {
      return d.toDateString() === now.toDateString();
    }
    return true;
  }

  function render() {
    const filteredConv = RAW_DATA.conversations.filter(c => {
      const matchProj = (currentProject === 'all') || (c.project === currentProject);
      const matchPeriod = isWithinPeriod(c.lastUpdatedIso, currentPeriod);
      return matchProj && matchPeriod;
    });

    let totalSavedEur = 0;
    let totalSavedTokens = 0;
    let totalCostEur = 0;
    let totalInputTokens = 0;
    let totalCacheTokens = 0;

    filteredConv.forEach(c => {
      totalSavedEur += (c.savedEur || 0);
      totalSavedTokens += (c.savedTokens || 0);
      totalCostEur += (c.costEur || 0);
      totalInputTokens += (c.inputTokens || 0);
      totalCacheTokens += (c.cacheReadTokens || 0);
    });

    const cachePct = totalInputTokens > 0 ? ((totalCacheTokens / totalInputTokens) * 100).toFixed(1) : 0;

    document.getElementById('kpi-saved-eur').innerText = totalSavedEur.toFixed(2).replace('.', ',') + ' €';
    document.getElementById('kpi-saved-tokens').innerText = (totalSavedTokens / 1e6).toFixed(2) + ' M';
    document.getElementById('kpi-cost-eur').innerText = totalCostEur.toFixed(2).replace('.', ',') + ' €';
    document.getElementById('kpi-cache-pct').innerText = cachePct + ' %';

    // Rendu table sessions ROI
    const roiTbody = document.getElementById('session-roi-rows');
    roiTbody.innerHTML = filteredConv.map(c => {
      const pClass = c.project.replace(/\s+/g, '-');
      const shortId = c.conversationId.length > 8 ? c.conversationId.substring(0, 8) : c.conversationId;
      return `<tr>
        <td><span class="tag-proj \${pClass}">\${c.project}</span></td>
        <td><code>\${shortId}</code></td>
        <td>\${c.lastUpdated}</td>
        <td>\${c.plannerTurns}</td>
        <td>\${(c.savedTokens / 1e6).toFixed(2)} M</td>
        <td>\${c.cacheHitPct} %</td>
        <td>\${c.costEur.toFixed(2)} €</td>
        <td class="eur-gain">+\${c.savedEur.toFixed(2)} €</td>
      </tr>`;
    }).join('') || '<tr><td colspan="8" style="text-align:center; color:var(--muted)">Aucune session ne correspond aux filtres.</td></tr>';

    // Rendu projets
    const projTbody = document.getElementById('project-rows');
    projTbody.innerHTML = (RAW_DATA.byProject || []).map(p => {
      const pClass = p.project.replace(/\s+/g, '-');
      return `<tr>
        <td><span class="tag-proj \${pClass}">\${p.project}</span></td>
        <td>\${p.sessions}</td>
        <td>\${p.turns}</td>
        <td>\${(p.savedTokens / 1e6).toFixed(2)} M</td>
        <td>\${p.costEur.toFixed(2)} €</td>
        <td class="eur-gain">+\${p.savedEur.toFixed(2)} €</td>
      </tr>`;
    }).join('');

    // Rendu onglet technique
    const modelTbody = document.getElementById('model-rows');
    const models = RAW_DATA.byModel || {};
    modelTbody.innerHTML = Object.keys(models).map(mName => {
      const m = models[mName];
      return `<tr>
        <td><code>\${mName}</code></td>
        <td>\${m.turns}</td>
        <td>\${(m.inputTokens / 1e6).toFixed(2)} M</td>
        <td>\${m.cacheHitPct} %</td>
        <td>\${(m.outputTokens / 1e3).toFixed(1)} k</td>
        <td>\${m.costEur ? m.costEur.toFixed(2) : (m.estimatedUsd * 0.92).toFixed(2)} €</td>
      </tr>`;
    }).join('');

    // Verbose rows
    const verboseTbody = document.getElementById('verbose-rows');
    verboseTbody.innerHTML = (RAW_DATA.topVerboseToolOutputs || []).map(v => {
      const shortId = v.conversationId.length > 8 ? v.conversationId.substring(0, 8) : v.conversationId;
      return `<tr>
        <td><code>\${shortId}</code></td>
        <td>\${v.project || 'Général'}</td>
        <td>Étape \${v.stepIndex}</td>
        <td>\${v.chars}</td>
        <td>~\${v.estTokens} tok</td>
        <td style="color:var(--muted); font-size:11px;">\${v.preview.substring(0, 75)}...</td>
      </tr>`;
    }).join('');

    // Tech session rows
    const techTbody = document.getElementById('session-tech-rows');
    techTbody.innerHTML = RAW_DATA.conversations.map(c => {
      const shortId = c.conversationId.length > 8 ? c.conversationId.substring(0, 8) : c.conversationId;
      return `<tr>
        <td><code>\${shortId}</code></td>
        <td>\${c.project}</td>
        <td>\${c.lastUpdated}</td>
        <td>\${(c.inputTokens / 1e6).toFixed(2)} M</td>
        <td>\${c.cacheHitPct} %</td>
        <td>\${(c.outputTokens / 1e3).toFixed(1)} k</td>
        <td>\${c.costEur.toFixed(2)} €</td>
        <td>\${(c.projectedNext20TurnsUsd * 0.92).toFixed(2)} €</td>
      </tr>`;
    }).join('');
  }

  // Initial render
  render();
</script>
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
    currency         = "EUR (€)"
    timezone         = "Europe/Paris"
    sessionsAnalyzed = $data.sessionsAnalyzed
    totalSavedTokens = $tot.savedTokens
    totalSavedEur    = $tot.savedEur
    actualCostEur    = $tot.costEur
} | ConvertTo-Json -Depth 3
