## Objectif en cours
Alignement complet du dépôt Token Optimizer v2.1 sur les règles finales (`b48b1b7` sur `origin/main`) + correctif local de `plugin/open-dashboard.cmd`.

## Fichiers modifiés
- Poussés (`b48b1b7`) : `plugin/rules/AGENTS.md`, `.agents/workflows/handoff.md`, `plugin/hooks/session-cost-watch.ps1`, `plugin/skills/token-report/scripts/serve-dashboard.ps1`, `README.md`, `CHECKLIST_QUOTIDIENNE.md`, `GUIDE_TOKEN_OPTIMIZATION.md`, `.agents/STATUS.md`
- Local (non commité) : `plugin/open-dashboard.cmd`

## Décisions prises
- `Hydrogen Medium` par défaut pour coder ; `Hydrogen Low` pour le mécanique ; `Neon Medium` uniquement sur blocage complexe (via `/handoff`).
- Porte `/grill-me` assouplie aux demandes floues ; interdiction d'utiliser `browser` sur `127.0.0.1`/`localhost`.
- `serve-dashboard.ps1` durci (`try/catch` + `IgnoreWriteExceptions`) ; `open-dashboard.cmd` ne lance plus le navigateur avant le serveur.

## État des tests/builds
- `install.ps1` OK ; `GET /api/live` -> `/api/refresh` -> `GET /api/live` OK (`HTTP 200`, `183 030` octets sur `http://127.0.0.1:4891/`).

## Prochaine action immédiate
Commiter et pousser `plugin/open-dashboard.cmd` (et `.agents/STATUS.md`) sur `origin/main`.

## Modèle recommandé
`Gemini 4 Hydrogen (Low)` (tâche mécanique Git).
