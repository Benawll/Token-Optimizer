## Objectif en cours
Token Optimizer v2.1 déployé et poussé sur `main` (`f90aea3`) : workflow `/handoff` déterministe, alertes `0 token` (`workflow-nudge.ps1`), seuil lecture brute 800 lignes et dashboard recalibré (`15/25/40` tours, `60k/85k` tok).

## Fichiers modifiés
- `.agents/workflows/handoff.md`
- `plugin/rules/AGENTS.md`
- `plugin/hooks/workflow-nudge.ps1`, `guard-verbose-cli.ps1`, `compress-cli.ps1`, `session-cost-watch.ps1`
- `plugin/lib/token-core.ps1`
- `plugin/skills/token-report/scripts/serve-dashboard.ps1`, `templates/dashboard.html`

## Décisions prises
- Suppression du badge `[Audit Modèle]` et de `Gemini 3.8 Flash` ; `Gemini 4 Hydrogen (Low)` défini par défaut.
- Cache froid (`> 5 min`) : switch vers `Hydrogen Low` autorisé si contexte `< 50k`, sinon `/handoff`.
- Compteur de switches modèle restreint aux bascules sur cache chaud (`< 300s`) ; sessions hybrides `Pré+Post` exclues du comparatif moyen/tour.

## État des tests/builds
- `install.ps1` exécuté : validation JSON + syntaxe PowerShell OK, plugin déployé.
- Smoke-test `workflow-nudge.ps1` OK ; commit `f90aea3` poussé sur `origin/main` (working tree propre).

## Prochaine action immédiate
Regénérer/rafraîchir le dashboard (`token-report` ou `http://127.0.0.1:4891/`) si besoin et vérifier visuellement les nouveaux seuils `15/25/40` et `60k/85k`.
