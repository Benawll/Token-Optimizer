# Token Optimizer Rules

1. **Batch parallel calls**: Issue independent searches, file reads, and edits in parallel in a single turn.
2. **Search before reading**: Locate targets with `rg`/grep first, then read bounded line ranges (`StartLine`/`EndLine`) unless the file is under 800 lines. Never dump whole directories or lockfiles.
3. **Surgical edits**: Use targeted `edit_file` diffs. Never reprint unchanged file sections in responses or tool calls.
4. **Quiet CLI output**: Chain dependent commands with `&&`. Pass quiet flags (`-q`, `--quiet`, `--silent`, `--no-progress`) and cap verbose output (`| Select-Object -Last 50` / `| tail -n 50`).
5. **Isolate noisy tasks**: Réserver les sous-agents (`research`, `browser`) aux **explorations massives ponctuelles** (`5+` fichiers, gros logs, navigation web). Jamais pour une lecture simple (un sous-agent repart à 0 % de cache).
6. **Concise output, full rigor**: Skip pleasantries and prompt restatements. Never skip required tests, builds, or verification steps.
7. **Stabilité Cache & Modèle (`1 session = 1 modèle + 1 niveau de raisonnement`)** :
   - **Cache chaud (inactivité < 5 min)** : ne jamais changer de modèle ni de niveau de thinking tant que le cache est chaud (casse 100 % du cache implicite).
   - **Session froide (inactivité > 5 min)** : le cache implicite a déjà expiré. Changer vers un modèle plus léger (ex. `Gemini 4 Hydrogen (Low)`) est autorisé si le contexte est `< 50k` tokens. Si le contexte dépasse `50k` tokens, lancer `/handoff` et ouvrir un nouveau fil.
   - **Handoff sans auto-création** : lors d'un `/handoff` ou d'un arrêt, ne jamais appeler l'outil natif de création de session (écrire `.agents/STATUS.md` et rendre la main).
   - Éviter aussi d'éditer `AGENTS.md`/`GEMINI.md` ou de réinstaller le plugin au milieu d'une session active.
   - **Modèle par défaut unique** : `Gemini 4 Hydrogen (Low)` (éditions, CLI, tests, formatage, audits/scans, tâches courantes).
   - **Guide de choix au démarrage uniquement** :
     - `Gemini 4 Hydrogen (Low)` *(défaut)* : tâches courantes, CLI, tests, revue, éditions ciblées.
     - `Gemini 4 Hydrogen (Medium)` : features multi-étapes, logique API standard.
     - `Gemini 4 Neon (Medium/High)` : refontes architecturales multi-fichiers ou déblocage complexe.
8. **Workflow Économe en 5 Étapes — Porte Obligatoire (Commandes slash)** :
   - **Étape 1 — Porte `/grill-me` (OBLIGATOIRE avant d'éditer)** : Pour toute demande de refonte, design UI/UX, architecture ou chantier multi-fichiers dont les choix ne sont pas encore verrouillés, **ne jamais commencer à coder directement** — proposer explicitement `/grill-me` (ou poser 3 questions de cadrage concises) avant le premier `write_file`/`edit_file`.
   - **Étape 2 (Build)** : Rester sur `Gemini 4 Hydrogen (Low)` par défaut (ou le palier choisi au démarrage tant que le cache est chaud).
   - **Étape 3 — Porte `/btw` (Questions & Détours)** : Sur toute question rapide hors-sujet en milieu de session, rappeler `/btw` en 1 ligne (sans alourdir la réponse) et déléguer la navigation web à `/browser`.
   - **Étape 4 (Itération massive)** : Recommander `/swarm` quand plusieurs chantiers parallèles peuvent être distribués.
   - **Étape 5 (Clôture)** : Livrer sur Git et suggérer `/automation` pour pérenniser les tâches récurrentes.
