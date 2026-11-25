# Token Optimizer pour Google Antigravity (`v1.2.0`)

Plugin **100 % local, sans dépendance externe et sans télémétrie** pour réduire de **30 % à 55 %** la consommation de tokens sur **Google Antigravity** (**Gemini 4 Neon**, **Hydrogen** et **Orchestrator**), sans dégrader la qualité du code.

---

## Fonctionnalités incluses

| Composant | Rôle | Coût modèle |
| :--- | :--- | :---: |
| **Règle statique globale** ([AGENTS.md](plugin/rules/AGENTS.md)) | Batching parallèle, lectures ciblées, micro-diffs, CLI silencieux, subagents (931 octets) | Ultra-léger (préfixe statique) |
| **Hook `PreToolUse`** ([guard-verbose-cli.ps1](plugin/hooks/guard-verbose-cli.ps1) + [compress-cli.ps1](plugin/hooks/compress-cli.ps1)) | Bloque `cat`/`Get-Content` bruts ; compresse les commandes dev/test/build verbeuses (`dotnet`, `npm`, `pytest`, `cargo`, `go`, `gradle`, `git log/diff`) et sauve le log brut dans `%TEMP%\to-sandbox\` | **0 token** |
| **Hook `SessionStart`** ([session-start-check.ps1](plugin/hooks/session-start-check.ps1)) | Détecte à l'ouverture les stacks, `.antigravityignore` manquant/dérivé, règles > 4 KB et MCP 3D/Unity inutilisés | **0 token** |
| **Hook `PostInvocation`** ([session-cost-watch.ps1](plugin/hooks/session-cost-watch.ps1)) | Détecteur de boucles d'échec (3+ erreurs) + alertes paliers (35/70/120 tours, ≥150k contexte, ≥\$2/\$5/\$10) avec projection +20 tours | **0 token** |
| **Skill `token-setup`** | Audit complet, détection multi-stack (JS/TS, Python, .NET/C#, Unity, Blender, Rust, Go, Java, C/C++) et synchro `.antigravityignore` sans perte | À la demande |
| **Skill `token-report`** | Bilan réel des `transcript.jsonl`, dashboard HTML hors ligne (`-Open`), handoff compact (< 300 tokens) et archivage local | À la demande |
| **Skill `token-mcp`** | Bascule entre profils MCP (`minimal`, `gamedev`, `full`, `none`) avec sauvegarde dans `full-catalog.json` | À la demande |
| **Skill `token-outline`** | Extraction de squelette de code (`L<ligne>: signature`) avant `read_file` (-85 % à -97 %) | À la demande |

---

## Installation rapide (Windows / PowerShell)

```powershell
git clone https://github.com/Benawll/Token-Optimizer.git
cd Token-Optimizer
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Le plugin est installé dans `~/.gemini/config/plugins/token-optimizer/` et chargé dès le tour suivant dans Antigravity.

### Désinstallation

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

### Ouvrir le tableau de bord local à tout moment

Exécutez `open-dashboard.cmd` depuis le dossier du plugin installé (`~/.gemini/config/plugins/token-optimizer/open-dashboard.cmd`) ou demandez simplement dans Antigravity : *"Ouvre mon dashboard avec token-report"*. Aucune donnée personnelle n'est jamais écrite dans le dépôt.

---

## Structure du dépôt

```text
├── README.md
├── LICENSE
├── GUIDE_TOKEN_OPTIMIZATION.md   # Guide complet Neon / Hydrogen / Orchestrator
├── CHECKLIST_QUOTIDIENNE.md      # Aide-mémoire 1 page
├── install.ps1                   # Installeur / désinstalleur + validation JSON/PS
├── plugin/                       # Source distribuable du plugin Antigravity
│   ├── plugin.json
│   ├── hooks.json
│   ├── open-dashboard.cmd
│   ├── assets/logo.svg
│   ├── lib/token-core.ps1
│   ├── hooks/
│   ├── rules/AGENTS.md
│   └── skills/ (token-setup, token-report, token-mcp, token-outline)
└── templates/                    # Modèles statiques réutilisables (.antigravityignore, GEMINI.md, prompts)
```
