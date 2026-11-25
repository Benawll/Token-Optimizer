# Token Optimizer — Plugin Antigravity (`v1.2.0`)

Suite **100 % locale, sans dépendance externe et sans redondance** pour économiser un maximum de tokens sur **Google Antigravity** (**Neon**, **Hydrogen**, **Orchestrator**) sans perte de performance.

## Architecture consolidée (`v1.2.0`)

* **1 règle globale statique (`rules/AGENTS.md`, 931 octets)** — batching, lectures ciblées, micro-diffs, CLI silencieux, subagents.
* **1 librairie interne partagée (`lib/token-core.ps1`)** — zéro duplication de logique entre hooks et skills.
* **3 hooks automatiques à 0 token modèle (`hooks.json`)** :
  * `PreToolUse` (`guard-verbose-cli.ps1` + `compress-cli.ps1`) : bloque `cat`/`Get-Content` bruts ; compresse automatiquement les commandes dev/build/test/git verbeuses (`dotnet`, `npm`, `pytest`, `cargo`, `go`, `gradle`, `git log/diff`) et archive la sortie intégrale dans `%TEMP%\to-sandbox\`.
  * `SessionStart` (`session-start-check.ps1`) : détecte stacks, `.antigravityignore` manquant/dérivé, règles > 4 KB et MCP 3D/Unity inutilisés.
  * `PostInvocation` (`session-cost-watch.ps1`) : détecteur de boucles d'échec (3+ erreurs rapprochées) + prévision de coût/contexte (+20 tours).
* **4 skills nettes (menu allégé)** :
  1. **`token-setup`** : audit complet + détection multi-stack + synchro `.antigravityignore` sans perte (`setup-workspace.ps1`).
  2. **`token-report`** : rapport JSON, **dashboard visuel HTML** (`generate-dashboard.ps1`), **handoff compact** (`handoff-session.ps1`), archivage local (`archive-sessions.ps1`).
  3. **`token-mcp`** : profils MCP (`minimal`, `gamedev`, `full`, `none`) avec sauvegarde `full-catalog.json`.
  4. **`token-outline`** : squelette structurel de gros fichiers (`code-outline.ps1`).

## Installation & Synchronisation

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Pour générer et ouvrir le tableau de bord local à la demande : lancez `open-dashboard.cmd` ou passez `-Open` à `skills\token-report\scripts\generate-dashboard.ps1`.
